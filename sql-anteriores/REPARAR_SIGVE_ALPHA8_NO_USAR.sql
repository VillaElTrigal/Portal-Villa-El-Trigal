-- SIGVE Alpha 8 - REPARACIÓN REAL
-- Corrige: eliminación y renumeración de socios, reapertura Zumba y registro público de niños/as.
-- Ejecutar completo en Supabase > SQL Editor.

begin;
create extension if not exists pgcrypto;

-- ===== SOCIOS Y NUMERACIÓN =====
alter table public.socios alter column numero_socio drop identity if exists;
create sequence if not exists public.socios_numero_socio_seq;
alter sequence public.socios_numero_socio_seq owned by public.socios.numero_socio;
alter table public.socios alter column numero_socio drop default;

create or replace function public.asignar_numero_socio()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.estado='activo' and new.numero_socio is null then
    new.numero_socio:=nextval('public.socios_numero_socio_seq');
  end if;
  return new;
end;$$;
drop trigger if exists trg_asignar_numero_socio on public.socios;
create trigger trg_asignar_numero_socio before insert or update of estado on public.socios
for each row execute function public.asignar_numero_socio();

-- Permite borrado físico SOLO cuando la función segura activa una bandera local.
create or replace function public.impedir_borrado_socio()
returns trigger language plpgsql set search_path=public as $$
begin
  if current_setting('sigve.permitir_borrado_prueba',true)='on' then return old; end if;
  raise exception 'Los socios no se eliminan directamente. Use la función de eliminación de prueba.';
end;$$;
drop trigger if exists trg_impedir_borrado_socio on public.socios;
create trigger trg_impedir_borrado_socio before delete on public.socios
for each row execute function public.impedir_borrado_socio();

create or replace function public.renumerar_socios_desarrollo()
returns integer language plpgsql security definer set search_path=public as $$
declare v_count integer;
begin
  if auth.uid() is null or not public.es_admin() then raise exception 'Acceso no autorizado'; end if;
  -- Evita choques con la restricción única.
  with o as (
    select id,row_number() over(order by coalesce(numero_socio,9223372036854775807),coalesce(fecha_ingreso,current_date),id)::bigint n
    from public.socios where estado='activo'
  ) update public.socios s set numero_socio=-o.n from o where s.id=o.id;
  -- Los no activos no conservan número durante desarrollo.
  update public.socios set numero_socio=null where estado<>'activo';
  with o as (
    select id,row_number() over(order by abs(numero_socio),id)::bigint n
    from public.socios where numero_socio<0
  ) update public.socios s set numero_socio=o.n from o where s.id=o.id;
  select count(*) into v_count from public.socios where estado='activo';
  perform setval('public.socios_numero_socio_seq',greatest(v_count,1),v_count>0);
  return v_count;
end;$$;
revoke all on function public.renumerar_socios_desarrollo() from public;
grant execute on function public.renumerar_socios_desarrollo() to authenticated;

create or replace function public.eliminar_socio_prueba(p_socio_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or not public.es_admin() then raise exception 'Acceso no autorizado'; end if;
  if not exists(select 1 from public.socios where id=p_socio_id) then raise exception 'El socio no existe'; end if;
  delete from public.ninos_hogar where socio_id=p_socio_id;
  if to_regclass('public.grupo_familiar') is not null then execute 'delete from public.grupo_familiar where socio_id=$1' using p_socio_id; end if;
  if to_regclass('public.cuotas_socios') is not null then execute 'delete from public.cuotas_socios where socio_id=$1' using p_socio_id; end if;
  if to_regclass('public.certificados_emitidos') is not null then execute 'update public.certificados_emitidos set socio_id=null where socio_id=$1' using p_socio_id; end if;
  if to_regclass('public.movimientos_financieros') is not null then execute 'update public.movimientos_financieros set socio_id=null where socio_id=$1' using p_socio_id; end if;
  if to_regclass('public.auditoria') is not null then delete from public.auditoria where registro_id=p_socio_id and modulo='socios'; end if;
  perform set_config('sigve.permitir_borrado_prueba','on',true);
  delete from public.socios where id=p_socio_id;
  perform public.renumerar_socios_desarrollo();
  return true;
end;$$;
revoke all on function public.eliminar_socio_prueba(uuid) from public;
grant execute on function public.eliminar_socio_prueba(uuid) to authenticated;

-- Renumera ahora mismo desde 001.
select public.renumerar_socios_desarrollo();

-- ===== ZUMBA =====
create or replace function public.reabrir_cierre_zumba(p_mes date)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_cierre uuid; v_mov uuid;
begin
  if auth.uid() is null or not public.es_admin() then raise exception 'Acceso no autorizado'; end if;
  select id,movimiento_id into v_cierre,v_mov
  from public.zumba_cierres where mes=date_trunc('month',p_mes)::date limit 1;
  if v_cierre is null then raise exception 'No existe un cierre para ese mes'; end if;
  update public.zumba_pagos set cierre_id=null where cierre_id=v_cierre;
  delete from public.zumba_cierres where id=v_cierre;
  if v_mov is not null then delete from public.movimientos_financieros where id=v_mov; end if;
  return true;
end;$$;
revoke all on function public.reabrir_cierre_zumba(date) from public;
grant execute on function public.reabrir_cierre_zumba(date) to authenticated;

-- ===== NIÑOS Y NIÑAS =====
alter table public.socios add column if not exists registro_ninos_token uuid default gen_random_uuid();
update public.socios set registro_ninos_token=gen_random_uuid() where registro_ninos_token is null;
alter table public.socios alter column registro_ninos_token set not null;
create unique index if not exists socios_registro_ninos_token_unique on public.socios(registro_ninos_token);

create table if not exists public.ninos_hogar(
 id uuid primary key default gen_random_uuid(),
 socio_id uuid not null references public.socios(id) on delete restrict,
 nombre_completo text not null,
 fecha_nacimiento date not null,
 sexo text not null check(sexo in('M','F')),
 activo boolean not null default true,
 creado_en timestamptz not null default now(),
 actualizado_en timestamptz not null default now(),
 creado_por uuid null
);
alter table public.ninos_hogar enable row level security;
revoke all on public.ninos_hogar from anon;

create or replace function public.obtener_socio_por_token_ninos(p_token uuid)
returns table(nombre_completo text,direccion text,numero_socio bigint)
language sql security definer stable set search_path=public as $$
 select s.nombre_completo,s.direccion,s.numero_socio from public.socios s
 where s.registro_ninos_token=p_token and s.estado='activo' limit 1;
$$;
create or replace function public.listar_ninos_por_token(p_token uuid)
returns table(id uuid,nombre_completo text,fecha_nacimiento date,sexo text)
language sql security definer stable set search_path=public as $$
 select n.id,n.nombre_completo,n.fecha_nacimiento,n.sexo
 from public.ninos_hogar n join public.socios s on s.id=n.socio_id
 where s.registro_ninos_token=p_token and s.estado='activo' and n.activo=true
 order by n.fecha_nacimiento,n.nombre_completo;
$$;
create or replace function public.registrar_nino_por_token(p_token uuid,p_nombre text,p_fecha_nacimiento date,p_sexo text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_socio uuid; v_id uuid;
begin
 select id into v_socio from public.socios where registro_ninos_token=p_token and estado='activo';
 if v_socio is null then raise exception 'Enlace inválido o vencido'; end if;
 if length(trim(coalesce(p_nombre,'')))<3 then raise exception 'Debe indicar el nombre completo'; end if;
 if p_fecha_nacimiento is null or p_fecha_nacimiento>current_date then raise exception 'Fecha inválida'; end if;
 if p_sexo not in('M','F') then raise exception 'Sexo inválido'; end if;
 insert into public.ninos_hogar(socio_id,nombre_completo,fecha_nacimiento,sexo)
 values(v_socio,trim(p_nombre),p_fecha_nacimiento,p_sexo) returning id into v_id;
 return v_id;
end;$$;
create or replace function public.actualizar_nino_por_token(p_token uuid,p_nino_id uuid,p_nombre text,p_fecha_nacimiento date,p_sexo text)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_socio uuid;
begin
 select id into v_socio from public.socios where registro_ninos_token=p_token and estado='activo';
 if v_socio is null then raise exception 'Enlace inválido o vencido'; end if;
 update public.ninos_hogar set nombre_completo=trim(p_nombre),fecha_nacimiento=p_fecha_nacimiento,sexo=p_sexo,actualizado_en=now()
 where id=p_nino_id and socio_id=v_socio and activo=true;
 if not found then raise exception 'Registro no encontrado'; end if;
 return true;
end;$$;
create or replace function public.eliminar_nino_por_token(p_token uuid,p_nino_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_socio uuid;
begin
 select id into v_socio from public.socios where registro_ninos_token=p_token and estado='activo';
 if v_socio is null then raise exception 'Enlace inválido o vencido'; end if;
 update public.ninos_hogar set activo=false,actualizado_en=now()
 where id=p_nino_id and socio_id=v_socio and activo=true;
 if not found then raise exception 'Registro no encontrado'; end if;
 return true;
end;$$;
grant execute on function public.obtener_socio_por_token_ninos(uuid) to anon,authenticated;
grant execute on function public.listar_ninos_por_token(uuid) to anon,authenticated;
grant execute on function public.registrar_nino_por_token(uuid,text,date,text) to anon,authenticated;
grant execute on function public.actualizar_nino_por_token(uuid,uuid,text,date,text) to anon,authenticated;
grant execute on function public.eliminar_nino_por_token(uuid,uuid) to anon,authenticated;

commit;
notify pgrst,'reload schema';
