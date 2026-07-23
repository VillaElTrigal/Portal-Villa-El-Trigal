-- SIGVE v1.0.0-alpha.7
-- Ejecutar UNA VEZ en Supabase > SQL Editor.
-- Incluye: numeración de socios desde 001, eliminación de pruebas con renumeración,
-- eliminación/reapertura del cierre de Zumba y formulario público de niños/as.

begin;
create extension if not exists pgcrypto;

alter table public.socios
  add column if not exists registro_ninos_token uuid not null default gen_random_uuid();
create unique index if not exists socios_registro_ninos_token_unique on public.socios(registro_ninos_token);

create table if not exists public.ninos_hogar (
  id uuid primary key default gen_random_uuid(),
  socio_id uuid not null references public.socios(id) on delete restrict,
  nombre_completo text not null,
  fecha_nacimiento date not null,
  sexo text not null check(sexo in ('M','F')),
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  creado_por uuid null
);
create index if not exists ninos_hogar_socio_idx on public.ninos_hogar(socio_id);

-- Renumera todos los socios que ya tienen número, desde 1, conservando el orden actual.
create or replace function public.renumerar_socios_desarrollo()
returns integer
language plpgsql security definer set search_path=public
as $$
declare v_count integer;
begin
  if auth.uid() is null or not public.es_admin() then raise exception 'Acceso no autorizado'; end if;
  -- Primero usa números negativos para evitar choques con el índice UNIQUE.
  with orden as (
    select id,row_number() over(order by numero_socio nulls last,fecha_ingreso nulls last,creado_en nulls last,id)::bigint nuevo
    from public.socios
    where numero_socio is not null or estado='activo'
  )
  update public.socios s set numero_socio=-o.nuevo from orden o where s.id=o.id;
  with orden as (
    select id,row_number() over(order by abs(numero_socio),id)::bigint nuevo
    from public.socios where numero_socio<0
  )
  update public.socios s set numero_socio=o.nuevo from orden o where s.id=o.id;
  get diagnostics v_count=row_count;
  perform setval('public.socios_numero_socio_seq',greatest(v_count,1),v_count>0);
  insert into public.auditoria(modulo,accion,detalle,usuario_id)
  values('socios','renumeración de desarrollo',jsonb_build_object('cantidad',v_count,'inicio',1),auth.uid());
  return v_count;
end;$$;
revoke all on function public.renumerar_socios_desarrollo() from public;
grant execute on function public.renumerar_socios_desarrollo() to authenticated;

-- Elimina un socio de prueba y luego recompone automáticamente la numeración.
create or replace function public.eliminar_socio_prueba(p_socio_id uuid)
returns boolean
language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null or not public.es_admin() then raise exception 'Acceso no autorizado'; end if;
  if not exists(select 1 from public.socios where id=p_socio_id) then raise exception 'El socio no existe'; end if;
  delete from public.ninos_hogar where socio_id=p_socio_id;
  if to_regclass('public.grupo_familiar') is not null then execute 'delete from public.grupo_familiar where socio_id=$1' using p_socio_id; end if;
  if to_regclass('public.cuotas_socios') is not null then execute 'delete from public.cuotas_socios where socio_id=$1' using p_socio_id; end if;
  if to_regclass('public.certificados_emitidos') is not null then update public.certificados_emitidos set socio_id=null where socio_id=p_socio_id; end if;
  if to_regclass('public.movimientos_financieros') is not null then update public.movimientos_financieros set socio_id=null where socio_id=p_socio_id; end if;
  if to_regclass('public.auditoria') is not null then delete from public.auditoria where registro_id=p_socio_id and modulo='socios'; end if;
  alter table public.socios disable trigger trg_impedir_borrado_socio;
  delete from public.socios where id=p_socio_id;
  alter table public.socios enable trigger trg_impedir_borrado_socio;
  perform public.renumerar_socios_desarrollo();
  return true;
exception when others then
  begin alter table public.socios enable trigger trg_impedir_borrado_socio; exception when others then null; end;
  raise;
end;$$;
revoke all on function public.eliminar_socio_prueba(uuid) from public;
grant execute on function public.eliminar_socio_prueba(uuid) to authenticated;

-- Reabre/elimina un cierre de Zumba y borra su movimiento financiero asociado.
create or replace function public.reabrir_cierre_zumba(p_mes date)
returns boolean
language plpgsql security definer set search_path=public
as $$
declare v_cierre uuid; v_mov uuid;
begin
  if auth.uid() is null or not public.es_admin() then raise exception 'Acceso no autorizado'; end if;
  select id,movimiento_id into v_cierre,v_mov from public.zumba_cierres where mes=date_trunc('month',p_mes)::date;
  if v_cierre is null then raise exception 'No existe un cierre para ese mes'; end if;
  update public.zumba_pagos set cierre_id=null where cierre_id=v_cierre;
  delete from public.zumba_cierres where id=v_cierre;
  if v_mov is not null then delete from public.movimientos_financieros where id=v_mov; end if;
  if to_regclass('public.auditoria') is not null then
    insert into public.auditoria(modulo,registro_id,accion,detalle,usuario_id)
    values('zumba',v_cierre,'cierre mensual eliminado',jsonb_build_object('mes',p_mes,'movimiento_financiero',v_mov),auth.uid());
  end if;
  return true;
end;$$;
revoke all on function public.reabrir_cierre_zumba(date) from public;
grant execute on function public.reabrir_cierre_zumba(date) to authenticated;

-- RPC públicas seguras para el enlace personal de niños y niñas.
drop function if exists public.obtener_socio_por_token_ninos(uuid);
drop function if exists public.listar_ninos_por_token(uuid);
create function public.obtener_socio_por_token_ninos(p_token uuid)
returns table(nombre_completo text,direccion text,numero_socio bigint)
language sql security definer stable set search_path=public
as $$ select s.nombre_completo,s.direccion,s.numero_socio from public.socios s where s.registro_ninos_token=p_token and s.estado='activo'; $$;

create function public.listar_ninos_por_token(p_token uuid)
returns table(id uuid,nombre_completo text,fecha_nacimiento date,sexo text)
language sql security definer stable set search_path=public
as $$
 select n.id,n.nombre_completo,n.fecha_nacimiento,n.sexo
 from public.ninos_hogar n join public.socios s on s.id=n.socio_id
 where s.registro_ninos_token=p_token and s.estado='activo' and n.activo=true
 order by n.fecha_nacimiento,n.nombre_completo;
$$;

create or replace function public.registrar_nino_por_token(p_token uuid,p_nombre text,p_fecha_nacimiento date,p_sexo text)
returns uuid language plpgsql security definer set search_path=public
as $$ declare v_socio uuid;v_id uuid;
begin
 select id into v_socio from public.socios where registro_ninos_token=p_token and estado='activo';
 if v_socio is null then raise exception 'Enlace inválido o socio no activo'; end if;
 if nullif(trim(p_nombre),'') is null or length(trim(p_nombre))<3 then raise exception 'Debe indicar el nombre completo'; end if;
 if p_fecha_nacimiento is null or p_fecha_nacimiento>current_date then raise exception 'Fecha de nacimiento inválida'; end if;
 if p_sexo not in ('M','F') then raise exception 'Sexo inválido'; end if;
 insert into public.ninos_hogar(socio_id,nombre_completo,fecha_nacimiento,sexo) values(v_socio,trim(p_nombre),p_fecha_nacimiento,p_sexo) returning id into v_id;
 return v_id;
end;$$;

create or replace function public.actualizar_nino_por_token(p_token uuid,p_nino_id uuid,p_nombre text,p_fecha_nacimiento date,p_sexo text)
returns boolean language plpgsql security definer set search_path=public
as $$ declare v_socio uuid;
begin
 select id into v_socio from public.socios where registro_ninos_token=p_token and estado='activo';
 if v_socio is null then raise exception 'Enlace inválido o socio no activo'; end if;
 if nullif(trim(p_nombre),'') is null or length(trim(p_nombre))<3 then raise exception 'Debe indicar el nombre completo'; end if;
 if p_fecha_nacimiento is null or p_fecha_nacimiento>current_date then raise exception 'Fecha de nacimiento inválida'; end if;
 if p_sexo not in ('M','F') then raise exception 'Sexo inválido'; end if;
 update public.ninos_hogar set nombre_completo=trim(p_nombre),fecha_nacimiento=p_fecha_nacimiento,sexo=p_sexo,actualizado_en=now()
 where id=p_nino_id and socio_id=v_socio and activo=true;
 if not found then raise exception 'Registro no encontrado'; end if;
 return true;
end;$$;

create or replace function public.eliminar_nino_por_token(p_token uuid,p_nino_id uuid)
returns boolean language plpgsql security definer set search_path=public
as $$ declare v_socio uuid;
begin
 select id into v_socio from public.socios where registro_ninos_token=p_token and estado='activo';
 if v_socio is null then raise exception 'Enlace inválido o socio no activo'; end if;
 update public.ninos_hogar set activo=false,actualizado_en=now() where id=p_nino_id and socio_id=v_socio and activo=true;
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
