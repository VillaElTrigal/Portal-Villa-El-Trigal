-- SIGVE 3.0.2 - Datos completos y fecha de ingreso
begin;

update public.socios
set fecha_ingreso = date '2026-07-27'
where numero_socio = 1 and fecha_ingreso = date '2026-07-28';

drop function if exists public.portal_socio_mis_datos(text);
create function public.portal_socio_mis_datos(p_token text)
returns table(
  id uuid, numero_socio bigint, nombres text, apellido_paterno text, apellido_materno text,
  nombre_completo text, rut text, fecha_nacimiento date, estado_civil text,
  ocupacion text, ocupacion_otro text, via_id uuid, numero_domicilio text,
  direccion text, telefono text, correo text, fecha_ingreso date, estado text,
  registro_ninos_estado text, ultima_cuota_pagada date, cuotas_pendientes bigint,
  monto_adeudado numeric
)
language plpgsql security definer set search_path=public
as $$
declare v_socio uuid;
begin
  v_socio:=public.portal_socio_validar_sesion(p_token);
  if v_socio is null then raise exception 'Sesión inválida o vencida'; end if;
  return query
  select s.id,s.numero_socio,s.nombres,s.apellido_paterno,s.apellido_materno,
    s.nombre_completo,s.rut,s.fecha_nacimiento,s.estado_civil,s.ocupacion,s.ocupacion_otro,
    s.via_id,s.numero_domicilio,s.direccion,s.telefono,s.correo,s.fecha_ingreso,s.estado,
    coalesce(s.registro_ninos_estado,'pendiente'),
    (select max(c.periodo) from public.cuotas_socios c where c.socio_id=s.id and c.estado='pagado'),
    (select count(*) from public.cuotas_socios c where c.socio_id=s.id and c.estado='pendiente'),
    (select coalesce(sum(c.monto),0) from public.cuotas_socios c where c.socio_id=s.id and c.estado='pendiente')
  from public.socios s where s.id=v_socio;
end;
$$;

drop function if exists public.portal_socio_actualizar_datos(text,uuid,text,text,text);
drop function if exists public.portal_socio_actualizar_datos(text,text,text,text,date,text,text,text,uuid,text,text,text);
create function public.portal_socio_actualizar_datos(
  p_token text, p_nombres text, p_apellido_paterno text, p_apellido_materno text,
  p_fecha_nacimiento date, p_estado_civil text, p_ocupacion text, p_ocupacion_otro text,
  p_via_id uuid, p_numero_domicilio text, p_telefono text, p_correo text
)
returns boolean
language plpgsql security definer set search_path=public
as $$
declare
  v_socio uuid; v_old public.socios%rowtype; v_correo text;
  v_via public.vias%rowtype; v_direccion text; v_nombre_completo text;
begin
  v_socio:=public.portal_socio_validar_sesion(p_token);
  if v_socio is null then raise exception 'Sesión inválida o vencida'; end if;
  if btrim(coalesce(p_nombres,''))='' or btrim(coalesce(p_apellido_paterno,''))='' or btrim(coalesce(p_apellido_materno,''))='' then raise exception 'Completa nombres y apellidos'; end if;
  if p_fecha_nacimiento is null or p_fecha_nacimiento > (now() at time zone 'America/Santiago')::date then raise exception 'La fecha de nacimiento no es válida'; end if;
  if p_estado_civil not in ('Soltero(a)','Casado(a)','Divorciado(a)','Viudo(a)') then raise exception 'Selecciona un estado civil válido'; end if;
  if p_ocupacion not in ('Estudiante','Trabajador dependiente','Trabajador independiente','Dueño(a) de casa','Otro') then raise exception 'Selecciona una ocupación válida'; end if;
  if p_ocupacion='Otro' and btrim(coalesce(p_ocupacion_otro,''))='' then raise exception 'Especifica tu ocupación'; end if;
  select * into v_via from public.vias where id=p_via_id and activa=true;
  if not found then raise exception 'Selecciona una calle, pasaje o avenida válida'; end if;
  if btrim(coalesce(p_numero_domicilio,''))='' or p_numero_domicilio !~ '^[0-9]{1,10}$' then raise exception 'El número del domicilio no es válido'; end if;
  v_direccion:=btrim(v_via.tipo||' '||v_via.nombre||' '||btrim(p_numero_domicilio));
  v_correo:=lower(btrim(coalesce(p_correo,'')));
  if v_correo='' or v_correo !~ '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$' then raise exception 'El correo electrónico no es válido'; end if;
  v_nombre_completo:=concat_ws(' ',btrim(p_nombres),btrim(p_apellido_paterno),btrim(p_apellido_materno));
  select * into v_old from public.socios where id=v_socio for update;
  update public.socios set
    nombres=btrim(p_nombres), apellido_paterno=btrim(p_apellido_paterno), apellido_materno=btrim(p_apellido_materno),
    nombre_completo=v_nombre_completo, fecha_nacimiento=p_fecha_nacimiento, estado_civil=p_estado_civil,
    ocupacion=p_ocupacion, ocupacion_otro=case when p_ocupacion='Otro' then btrim(p_ocupacion_otro) else null end,
    via_id=p_via_id, numero_domicilio=btrim(p_numero_domicilio), direccion=v_direccion,
    telefono=nullif(btrim(p_telefono),''), correo=v_correo, actualizado_en=now()
  where id=v_socio;
  insert into public.portal_socio_auditoria(socio_id,accion,detalle)
  values(v_socio,'actualizar_datos',jsonb_build_object('nombre_anterior',v_old.nombre_completo,'nombre_nuevo',v_nombre_completo,'direccion_anterior',v_old.direccion,'direccion_nueva',v_direccion));
  return true;
end;
$$;

grant execute on function public.portal_socio_mis_datos(text) to anon,authenticated;
grant execute on function public.portal_socio_actualizar_datos(text,text,text,text,date,text,text,text,uuid,text,text,text) to anon,authenticated;
commit;
