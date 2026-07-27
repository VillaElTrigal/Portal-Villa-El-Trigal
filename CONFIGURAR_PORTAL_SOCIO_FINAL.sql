-- SIGVE · CONFIGURACIÓN FINAL DEL PORTAL DEL SOCIO
-- Ejecutar completo una sola vez en Supabase > SQL Editor.
-- Esta versión reemplaza las funciones anteriores de acceso y evita conflictos de tipos.

begin;

create extension if not exists pgcrypto;

alter table public.socios drop constraint if exists socios_estado_check;
alter table public.socios add constraint socios_estado_check
  check (lower(estado) in ('activo','inactivo','pendiente','rechazado','renunciado'));

alter table public.socios
  add column if not exists renuncia_fecha timestamptz,
  add column if not exists renuncia_medio text,
  add column if not exists renuncia_motivo text;

create table if not exists public.portal_socio_sesiones (
  id uuid primary key default gen_random_uuid(),
  socio_id uuid not null references public.socios(id) on delete cascade,
  token_hash text not null unique,
  creado_en timestamptz not null default now(),
  expira_en timestamptz not null default (now() + interval '8 hours'),
  ultimo_uso_en timestamptz not null default now(),
  revocado_en timestamptz
);

create table if not exists public.portal_socio_auditoria (
  id bigint generated always as identity primary key,
  socio_id uuid not null references public.socios(id) on delete restrict,
  accion text not null,
  detalle jsonb not null default '{}'::jsonb,
  creado_en timestamptz not null default now()
);

create table if not exists public.portal_socio_intentos (
  id bigint generated always as identity primary key,
  rut_hash text not null,
  exitoso boolean not null default false,
  creado_en timestamptz not null default now()
);

create index if not exists portal_socio_sesiones_socio_idx
  on public.portal_socio_sesiones(socio_id, expira_en desc);
create index if not exists portal_socio_intentos_rut_fecha_idx
  on public.portal_socio_intentos(rut_hash, creado_en desc);

alter table public.portal_socio_sesiones enable row level security;
alter table public.portal_socio_auditoria enable row level security;
alter table public.portal_socio_intentos enable row level security;
revoke all on public.portal_socio_sesiones, public.portal_socio_auditoria, public.portal_socio_intentos from anon, authenticated;

-- Elimina versiones anteriores para que Supabase no encuentre funciones ambiguas.
drop function if exists public.portal_socio_ingresar(text,text);
drop function if exists public.portal_socio_ingresar(text,bigint);
drop function if exists public.portal_socio_renunciar_numero(text,text,text);
drop function if exists public.portal_socio_renunciar_numero(text,bigint,text);

create or replace function public.portal_socio_ingresar(p_rut text, p_numero_socio bigint)
returns text
language plpgsql
security definer
set search_path=public
as $$
declare
  v_rut text;
  v_hash text;
  v_socio uuid;
  v_token text;
  v_fallos integer;
begin
  v_rut := upper(regexp_replace(coalesce(p_rut,''), '[^0-9Kk]', '', 'g'));
  if v_rut = '' or p_numero_socio is null or p_numero_socio < 0 then return null; end if;

  v_hash := encode(digest(v_rut, 'sha256'), 'hex');
  select count(*) into v_fallos
  from public.portal_socio_intentos
  where rut_hash=v_hash and exitoso=false and creado_en>now()-interval '15 minutes';

  if v_fallos >= 5 then
    raise exception 'Demasiados intentos. Intenta nuevamente en 15 minutos';
  end if;

  select s.id into v_socio
  from public.socios s
  where upper(regexp_replace(coalesce(s.rut,''), '[^0-9Kk]', '', 'g')) = v_rut
    and s.numero_socio::bigint = p_numero_socio
    and lower(btrim(coalesce(s.estado,''))) = 'activo'
  limit 1;

  insert into public.portal_socio_intentos(rut_hash, exitoso)
  values(v_hash, v_socio is not null);

  if v_socio is null then return null; end if;

  v_token := encode(gen_random_bytes(32), 'hex');
  insert into public.portal_socio_sesiones(socio_id, token_hash, expira_en)
  values(v_socio, encode(digest(v_token,'sha256'),'hex'), now()+interval '8 hours');
  insert into public.portal_socio_auditoria(socio_id, accion)
  values(v_socio, 'inicio_sesion_numero_socio');
  return v_token;
end;
$$;

grant execute on function public.portal_socio_ingresar(text,bigint) to anon, authenticated;

create or replace function public.portal_socio_validar_sesion(p_token text)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare v_socio uuid;
begin
  if p_token is null or length(p_token)<32 then return null; end if;
  select ps.socio_id into v_socio
  from public.portal_socio_sesiones ps
  join public.socios s on s.id=ps.socio_id
  where ps.token_hash=encode(digest(p_token,'sha256'),'hex')
    and ps.revocado_en is null
    and ps.expira_en>now()
    and ps.ultimo_uso_en>now()-interval '30 minutes'
    and lower(btrim(coalesce(s.estado,'')))='activo';
  if v_socio is not null then
    update public.portal_socio_sesiones set ultimo_uso_en=now()
    where token_hash=encode(digest(p_token,'sha256'),'hex');
  end if;
  return v_socio;
end;
$$;
revoke all on function public.portal_socio_validar_sesion(text) from public;

create or replace function public.portal_socio_mis_datos(p_token text)
returns table(id uuid, numero_socio bigint, nombre_completo text, rut text,
  direccion text, telefono text, correo text, fecha_ingreso date, estado text,
  registro_ninos_estado text)
language plpgsql security definer set search_path=public as $$
declare v_socio uuid;
begin
  v_socio:=public.portal_socio_validar_sesion(p_token);
  if v_socio is null then raise exception 'Sesión inválida o vencida'; end if;
  return query select s.id,s.numero_socio,s.nombre_completo,s.rut,s.direccion,s.telefono,s.correo,
    s.fecha_ingreso,s.estado,coalesce(s.registro_ninos_estado,'pendiente')
  from public.socios s where s.id=v_socio;
end;
$$;

create or replace function public.portal_socio_actualizar_datos(p_token text,p_direccion text,p_telefono text,p_correo text)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_socio uuid; v_old public.socios%rowtype; v_correo text;
begin
  v_socio:=public.portal_socio_validar_sesion(p_token);
  if v_socio is null then raise exception 'Sesión inválida o vencida'; end if;
  if btrim(coalesce(p_direccion,''))='' then raise exception 'La dirección es obligatoria'; end if;
  v_correo:=lower(btrim(coalesce(p_correo,'')));
  if v_correo='' or v_correo !~ '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$' then raise exception 'El correo electrónico no es válido'; end if;
  select * into v_old from public.socios where id=v_socio for update;
  update public.socios set direccion=btrim(p_direccion),telefono=nullif(btrim(p_telefono),''),correo=v_correo,actualizado_en=now() where id=v_socio;
  insert into public.portal_socio_auditoria(socio_id,accion,detalle)
  values(v_socio,'actualizar_datos',jsonb_build_object('direccion_anterior',v_old.direccion,'direccion_nueva',btrim(p_direccion),'telefono_anterior',v_old.telefono,'telefono_nuevo',nullif(btrim(p_telefono),''),'correo_anterior',v_old.correo,'correo_nuevo',v_correo));
  return true;
end;
$$;

create or replace function public.portal_socio_listar_ninos(p_token text)
returns table(id uuid,nombre_completo text,rut text,fecha_nacimiento date,sexo text,parentesco text,
  participa_actividades boolean,tiene_condicion_especial boolean,condiciones_especiales text[],
  condicion_otro text,observaciones_especiales text,autoriza_datos_sensibles boolean)
language plpgsql security definer set search_path=public as $$
declare v_socio uuid;
begin
  v_socio:=public.portal_socio_validar_sesion(p_token);
  if v_socio is null then raise exception 'Sesión inválida o vencida'; end if;
  return query select n.id,n.nombre_completo,n.rut,n.fecha_nacimiento,n.sexo,n.parentesco,n.participa_actividades,
    n.tiene_condicion_especial,n.condiciones_especiales,n.condicion_otro,n.observaciones_especiales,n.autoriza_datos_sensibles
  from public.ninos_hogar n where n.socio_id=v_socio and n.activo=true order by n.fecha_nacimiento desc;
end;
$$;

create or replace function public.portal_socio_guardar_nino(p_token text,p_id uuid,p_nombre text,p_rut text,p_fecha date,p_sexo text,
  p_parentesco text,p_participa boolean,p_tiene_condicion boolean,p_condiciones text[],p_otro text,p_observaciones text,p_autoriza boolean)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_socio uuid; v_id uuid;
begin
  v_socio:=public.portal_socio_validar_sesion(p_token);
  if v_socio is null then raise exception 'Sesión inválida o vencida'; end if;
  if btrim(coalesce(p_nombre,''))='' or p_fecha is null or p_sexo not in ('M','F') then raise exception 'Completa los datos obligatorios'; end if;
  if p_fecha>current_date then raise exception 'La fecha de nacimiento no puede ser futura'; end if;
  if btrim(coalesce(p_rut,''))='' or not public.validar_rut_chileno(p_rut) then raise exception 'El RUT no es válido'; end if;
  if p_tiene_condicion and not coalesce(p_autoriza,false) then raise exception 'Debes autorizar el tratamiento de los datos sensibles'; end if;
  if p_id is null then
    insert into public.ninos_hogar(socio_id,nombre_completo,rut,fecha_nacimiento,sexo,parentesco,participa_actividades,tiene_condicion_especial,condiciones_especiales,condicion_otro,observaciones_especiales,autoriza_datos_sensibles)
    values(v_socio,btrim(p_nombre),btrim(p_rut),p_fecha,p_sexo,coalesce(nullif(btrim(p_parentesco),''),'Hijo(a)'),coalesce(p_participa,true),coalesce(p_tiene_condicion,false),coalesce(p_condiciones,'{}'),nullif(btrim(p_otro),''),nullif(btrim(p_observaciones),''),coalesce(p_autoriza,false)) returning id into v_id;
  else
    update public.ninos_hogar set nombre_completo=btrim(p_nombre),rut=btrim(p_rut),fecha_nacimiento=p_fecha,sexo=p_sexo,parentesco=coalesce(nullif(btrim(p_parentesco),''),'Hijo(a)'),participa_actividades=coalesce(p_participa,true),tiene_condicion_especial=coalesce(p_tiene_condicion,false),condiciones_especiales=case when p_tiene_condicion then coalesce(p_condiciones,'{}') else '{}' end,condicion_otro=case when p_tiene_condicion then nullif(btrim(p_otro),'') else null end,observaciones_especiales=case when p_tiene_condicion then nullif(btrim(p_observaciones),'') else null end,autoriza_datos_sensibles=case when p_tiene_condicion then coalesce(p_autoriza,false) else false end,actualizado_en=now()
    where id=p_id and socio_id=v_socio and activo=true returning id into v_id;
    if v_id is null then raise exception 'Registro no encontrado'; end if;
  end if;
  update public.socios set registro_ninos_estado='con_ninos',registro_ninos_completado_en=now(),actualizado_en=now() where id=v_socio;
  insert into public.portal_socio_auditoria(socio_id,accion,detalle) values(v_socio,case when p_id is null then 'agregar_nino' else 'editar_nino' end,jsonb_build_object('nino_id',v_id));
  return v_id;
end;
$$;

create or replace function public.portal_socio_eliminar_nino(p_token text,p_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_socio uuid; v_count integer;
begin
  v_socio:=public.portal_socio_validar_sesion(p_token);
  if v_socio is null then raise exception 'Sesión inválida o vencida'; end if;
  update public.ninos_hogar set activo=false,actualizado_en=now() where id=p_id and socio_id=v_socio and activo=true;
  if not found then raise exception 'Registro no encontrado'; end if;
  select count(*) into v_count from public.ninos_hogar where socio_id=v_socio and activo=true;
  update public.socios set registro_ninos_estado=case when v_count=0 then 'pendiente' else 'con_ninos' end,actualizado_en=now() where id=v_socio;
  insert into public.portal_socio_auditoria(socio_id,accion,detalle) values(v_socio,'eliminar_nino',jsonb_build_object('nino_id',p_id));
  return true;
end;
$$;

create or replace function public.portal_socio_declarar_sin_ninos(p_token text)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_socio uuid;
begin
  v_socio:=public.portal_socio_validar_sesion(p_token);
  if v_socio is null then raise exception 'Sesión inválida o vencida'; end if;
  if exists(select 1 from public.ninos_hogar where socio_id=v_socio and activo=true) then raise exception 'Primero debes retirar los registros vigentes del grupo familiar'; end if;
  update public.socios set registro_ninos_estado='sin_ninos',registro_ninos_completado_en=now(),actualizado_en=now() where id=v_socio;
  insert into public.portal_socio_auditoria(socio_id,accion) values(v_socio,'declarar_sin_ninos');
  return true;
end;
$$;

create or replace function public.portal_socio_renunciar_numero(p_token text,p_numero_socio bigint,p_motivo text default null)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_socio uuid;
begin
  v_socio:=public.portal_socio_validar_sesion(p_token);
  if v_socio is null then raise exception 'Sesión inválida o vencida'; end if;
  if not exists(select 1 from public.socios where id=v_socio and numero_socio::bigint=p_numero_socio and lower(btrim(coalesce(estado,'')))='activo') then raise exception 'El número de socio no coincide'; end if;
  update public.socios set estado='renunciado',renuncia_fecha=now(),renuncia_medio='Portal del Socio',renuncia_motivo=nullif(btrim(p_motivo),''),actualizado_en=now() where id=v_socio;
  insert into public.portal_socio_auditoria(socio_id,accion,detalle) values(v_socio,'renuncia_voluntaria',jsonb_build_object('motivo',nullif(btrim(p_motivo),'')));
  update public.portal_socio_sesiones set revocado_en=now() where socio_id=v_socio and revocado_en is null;
  return true;
end;
$$;

create or replace function public.portal_socio_cerrar_sesion(p_token text)
returns boolean language plpgsql security definer set search_path=public as $$
begin
  update public.portal_socio_sesiones set revocado_en=now() where token_hash=encode(digest(p_token,'sha256'),'hex') and revocado_en is null;
  return true;
end;
$$;

grant execute on function public.portal_socio_mis_datos(text) to anon,authenticated;
grant execute on function public.portal_socio_actualizar_datos(text,text,text,text) to anon,authenticated;
grant execute on function public.portal_socio_listar_ninos(text) to anon,authenticated;
grant execute on function public.portal_socio_guardar_nino(text,uuid,text,text,date,text,text,boolean,boolean,text[],text,text,boolean) to anon,authenticated;
grant execute on function public.portal_socio_eliminar_nino(text,uuid) to anon,authenticated;
grant execute on function public.portal_socio_declarar_sin_ninos(text) to anon,authenticated;
grant execute on function public.portal_socio_renunciar_numero(text,bigint,text) to anon,authenticated;
grant execute on function public.portal_socio_cerrar_sesion(text) to anon,authenticated;

commit;
