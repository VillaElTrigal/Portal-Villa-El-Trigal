-- SIGVE 3.0.2
-- Portal del Socio: dirección estructurada y estado de cuotas.
-- Hazte Socio: datos necesarios para preparar el futuro Libro de Socios.
-- Ejecutar una sola vez en Supabase > SQL Editor.

begin;

alter table public.solicitudes_socios
  add column if not exists nombres text,
  add column if not exists apellido_paterno text,
  add column if not exists apellido_materno text,
  add column if not exists fecha_nacimiento date,
  add column if not exists estado_civil text,
  add column if not exists ocupacion text,
  add column if not exists ocupacion_otro text;

alter table public.socios
  add column if not exists nombres text,
  add column if not exists apellido_paterno text,
  add column if not exists apellido_materno text,
  add column if not exists fecha_nacimiento date,
  add column if not exists estado_civil text,
  add column if not exists ocupacion text,
  add column if not exists ocupacion_otro text,
  add column if not exists via_id uuid,
  add column if not exists numero_domicilio text;

-- Mantiene los nuevos valores controlados sin bloquear registros históricos incompletos.
alter table public.solicitudes_socios drop constraint if exists solicitudes_estado_civil_check;
alter table public.solicitudes_socios add constraint solicitudes_estado_civil_check
  check (estado_civil is null or estado_civil in ('Soltero(a)','Casado(a)','Divorciado(a)','Viudo(a)'));
alter table public.solicitudes_socios drop constraint if exists solicitudes_ocupacion_check;
alter table public.solicitudes_socios add constraint solicitudes_ocupacion_check
  check (ocupacion is null or ocupacion in ('Estudiante','Trabajador dependiente','Trabajador independiente','Dueño(a) de casa','Otro'));

alter table public.socios drop constraint if exists socios_estado_civil_check;
alter table public.socios add constraint socios_estado_civil_check
  check (estado_civil is null or estado_civil in ('Soltero(a)','Casado(a)','Divorciado(a)','Viudo(a)'));
alter table public.socios drop constraint if exists socios_ocupacion_check;
alter table public.socios add constraint socios_ocupacion_check
  check (ocupacion is null or ocupacion in ('Estudiante','Trabajador dependiente','Trabajador independiente','Dueño(a) de casa','Otro'));

-- Permite que el Portal del Socio y Hazte Socio consulten únicamente las vías activas.
alter table public.vias enable row level security;
drop policy if exists "Publico consulta vias activas" on public.vias;
create policy "Publico consulta vias activas" on public.vias
  for select to anon, authenticated using (activa=true or public.es_admin());

-- Se elimina la versión previa porque cambia la estructura de retorno.
drop function if exists public.portal_socio_mis_datos(text);
create function public.portal_socio_mis_datos(p_token text)
returns table(
  id uuid, numero_socio bigint, nombre_completo text, rut text,
  via_id uuid, numero_domicilio text, direccion text, telefono text, correo text,
  fecha_ingreso date, estado text, registro_ninos_estado text,
  ultima_cuota_pagada date, cuotas_pendientes bigint, monto_adeudado numeric
)
language plpgsql
security definer
set search_path=public
as $$
declare v_socio uuid;
begin
  v_socio:=public.portal_socio_validar_sesion(p_token);
  if v_socio is null then raise exception 'Sesión inválida o vencida'; end if;
  return query
  select s.id,s.numero_socio,s.nombre_completo,s.rut,s.via_id,s.numero_domicilio,s.direccion,s.telefono,s.correo,
         s.fecha_ingreso,s.estado,coalesce(s.registro_ninos_estado,'pendiente'),
         (select max(c.periodo) from public.cuotas_socios c where c.socio_id=s.id and c.estado='pagado'),
         (select count(*) from public.cuotas_socios c where c.socio_id=s.id and c.estado='pendiente'),
         (select coalesce(sum(c.monto),0) from public.cuotas_socios c where c.socio_id=s.id and c.estado='pendiente')
  from public.socios s where s.id=v_socio;
end;
$$;

-- Nueva actualización segura: el nombre de la vía se obtiene desde la tabla oficial.
drop function if exists public.portal_socio_actualizar_datos(text,text,text,text);
drop function if exists public.portal_socio_actualizar_datos(text,uuid,text,text,text);
create function public.portal_socio_actualizar_datos(
  p_token text, p_via_id uuid, p_numero_domicilio text, p_telefono text, p_correo text
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  v_socio uuid; v_old public.socios%rowtype; v_correo text; v_via public.vias%rowtype; v_direccion text;
begin
  v_socio:=public.portal_socio_validar_sesion(p_token);
  if v_socio is null then raise exception 'Sesión inválida o vencida'; end if;
  select * into v_via from public.vias where id=p_via_id and activa=true;
  if not found then raise exception 'Selecciona una calle, pasaje o avenida válida'; end if;
  if btrim(coalesce(p_numero_domicilio,''))='' then raise exception 'El número del domicilio es obligatorio'; end if;
  if p_numero_domicilio !~ '^[0-9]{1,10}$' then raise exception 'El número del domicilio no es válido'; end if;
  v_direccion:=btrim(v_via.tipo||' '||v_via.nombre||' '||btrim(p_numero_domicilio));
  v_correo:=lower(btrim(coalesce(p_correo,'')));
  if v_correo='' or v_correo !~ '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$' then
    raise exception 'El correo electrónico no es válido';
  end if;
  select * into v_old from public.socios where id=v_socio for update;
  update public.socios set via_id=p_via_id, numero_domicilio=btrim(p_numero_domicilio), direccion=v_direccion,
    telefono=nullif(btrim(p_telefono),''), correo=v_correo, actualizado_en=now() where id=v_socio;
  insert into public.portal_socio_auditoria(socio_id,accion,detalle)
  values(v_socio,'actualizar_datos',jsonb_build_object(
    'direccion_anterior',v_old.direccion,'direccion_nueva',v_direccion,
    'telefono_anterior',v_old.telefono,'telefono_nuevo',nullif(btrim(p_telefono),''),
    'correo_anterior',v_old.correo,'correo_nuevo',v_correo));
  return true;
end;
$$;

grant execute on function public.portal_socio_mis_datos(text) to anon,authenticated;
grant execute on function public.portal_socio_actualizar_datos(text,uuid,text,text,text) to anon,authenticated;

commit;
