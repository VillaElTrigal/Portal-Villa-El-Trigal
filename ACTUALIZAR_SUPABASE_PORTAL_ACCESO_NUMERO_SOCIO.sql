-- SIGVE · Cambio de acceso del Portal del Socio
-- Ejecutar DESPUÉS de ACTUALIZAR_SUPABASE_SIGVE_V3_PORTAL_SOCIO.sql.
begin;
create extension if not exists pgcrypto;
create table if not exists public.portal_socio_intentos (
  id bigint generated always as identity primary key,
  rut_hash text not null,
  exitoso boolean not null default false,
  creado_en timestamptz not null default now()
);
create index if not exists portal_socio_intentos_rut_fecha_idx on public.portal_socio_intentos(rut_hash,creado_en desc);
alter table public.portal_socio_intentos enable row level security;
revoke all on public.portal_socio_intentos from anon,authenticated;

create or replace function public.portal_socio_ingresar(p_rut text,p_numero_socio bigint)
returns text language plpgsql security definer set search_path=public as $$
declare v_rut text; v_hash text; v_socio uuid; v_token text; v_fallos int;
begin
  v_rut:=upper(regexp_replace(coalesce(p_rut,''),'[^0-9Kk]','','g'));
  v_hash:=encode(digest(v_rut,'sha256'),'hex');
  select count(*) into v_fallos from public.portal_socio_intentos
   where rut_hash=v_hash and exitoso=false and creado_en>now()-interval '15 minutes';
  if v_fallos>=5 then raise exception 'Demasiados intentos. Intenta nuevamente en 15 minutos'; end if;
  select id into v_socio from public.socios
   where upper(regexp_replace(coalesce(rut,''),'[^0-9Kk]','','g'))=v_rut
     and numero_socio=p_numero_socio and estado='activo' limit 1;
  insert into public.portal_socio_intentos(rut_hash,exitoso) values(v_hash,v_socio is not null);
  if v_socio is null then return null; end if;
  v_token:=encode(gen_random_bytes(32),'hex');
  insert into public.portal_socio_sesiones(socio_id,token_hash,expira_en)
   values(v_socio,encode(digest(v_token,'sha256'),'hex'),now()+interval '8 hours');
  insert into public.portal_socio_auditoria(socio_id,accion) values(v_socio,'inicio_sesion_numero_socio');
  return v_token;
end; $$;

grant execute on function public.portal_socio_ingresar(text,bigint) to anon,authenticated;

create or replace function public.portal_socio_validar_sesion(p_token text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_socio uuid;
begin
 if p_token is null or length(p_token)<32 then return null; end if;
 select ps.socio_id into v_socio from public.portal_socio_sesiones ps join public.socios s on s.id=ps.socio_id
 where ps.token_hash=encode(digest(p_token,'sha256'),'hex') and ps.revocado_en is null
 and ps.expira_en>now() and ps.ultimo_uso_en>now()-interval '30 minutes' and s.estado='activo';
 if v_socio is not null then update public.portal_socio_sesiones set ultimo_uso_en=now() where token_hash=encode(digest(p_token,'sha256'),'hex'); end if;
 return v_socio;
end; $$;
revoke all on function public.portal_socio_validar_sesion(text) from public;

create or replace function public.portal_socio_renunciar_numero(p_token text,p_numero_socio bigint,p_motivo text default null)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_socio uuid;
begin
 v_socio:=public.portal_socio_validar_sesion(p_token);
 if v_socio is null then raise exception 'Sesión inválida o vencida'; end if;
 if not exists(select 1 from public.socios where id=v_socio and numero_socio=p_numero_socio and estado='activo') then raise exception 'El número de socio no coincide'; end if;
 update public.socios set estado='renunciado',renuncia_fecha=now(),renuncia_medio='Portal del Socio',renuncia_motivo=nullif(btrim(p_motivo),''),actualizado_en=now() where id=v_socio;
 insert into public.portal_socio_auditoria(socio_id,accion,detalle) values(v_socio,'renuncia_voluntaria',jsonb_build_object('motivo',nullif(btrim(p_motivo),'')));
 update public.portal_socio_sesiones set revocado_en=now() where socio_id=v_socio and revocado_en is null;
 return true;
end; $$;
grant execute on function public.portal_socio_renunciar_numero(text,bigint,text) to anon,authenticated;
commit;
