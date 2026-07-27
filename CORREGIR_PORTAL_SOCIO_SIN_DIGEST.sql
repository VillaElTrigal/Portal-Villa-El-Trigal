-- SIGVE · CORRECCIÓN DEFINITIVA DEL ACCESO AL PORTAL DEL SOCIO
-- Ejecutar completo en Supabase > SQL Editor.
-- Reemplaza únicamente las funciones de sesión que usaban digest().
-- No modifica socios, niños, reservas, finanzas ni otros módulos.

begin;

-- Elimina posibles sobrecargas antiguas para evitar llamadas ambiguas.
drop function if exists public.portal_socio_ingresar(text,text);
drop function if exists public.portal_socio_ingresar(text,bigint);

create or replace function public.portal_socio_ingresar(
  p_rut text,
  p_numero_socio bigint
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rut text;
  v_rut_clave text;
  v_socio uuid;
  v_token text;
  v_fallos integer;
begin
  v_rut := upper(regexp_replace(coalesce(p_rut, ''), '[^0-9Kk]', '', 'g'));

  if v_rut = '' or p_numero_socio is null or p_numero_socio < 0 then
    return null;
  end if;

  -- md5() es nativa de PostgreSQL y solo se usa para no guardar el RUT visible
  -- en la tabla de intentos. No depende de pgcrypto ni de digest().
  v_rut_clave := md5(v_rut);

  select count(*)
    into v_fallos
  from public.portal_socio_intentos
  where rut_hash = v_rut_clave
    and exitoso = false
    and creado_en > now() - interval '15 minutes';

  if v_fallos >= 5 then
    raise exception 'Demasiados intentos. Intenta nuevamente en 15 minutos';
  end if;

  select s.id
    into v_socio
  from public.socios s
  where upper(regexp_replace(coalesce(s.rut, ''), '[^0-9Kk]', '', 'g')) = v_rut
    and s.numero_socio::bigint = p_numero_socio
    and lower(btrim(coalesce(s.estado, ''))) = 'activo'
  limit 1;

  insert into public.portal_socio_intentos(rut_hash, exitoso)
  values (v_rut_clave, v_socio is not null);

  if v_socio is null then
    return null;
  end if;

  -- Dos UUID entregan un token impredecible. En la tabla solo se guarda md5(token).
  v_token := gen_random_uuid()::text || gen_random_uuid()::text;

  insert into public.portal_socio_sesiones(socio_id, token_hash, expira_en)
  values (v_socio, md5(v_token), now() + interval '8 hours');

  insert into public.portal_socio_auditoria(socio_id, accion)
  values (v_socio, 'inicio_sesion_numero_socio');

  return v_token;
end;
$$;

grant execute on function public.portal_socio_ingresar(text,bigint)
  to anon, authenticated;

create or replace function public.portal_socio_validar_sesion(p_token text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_socio uuid;
  v_token_clave text;
begin
  if p_token is null or length(p_token) < 60 then
    return null;
  end if;

  v_token_clave := md5(p_token);

  select ps.socio_id
    into v_socio
  from public.portal_socio_sesiones ps
  join public.socios s on s.id = ps.socio_id
  where ps.token_hash = v_token_clave
    and ps.revocado_en is null
    and ps.expira_en > now()
    and ps.ultimo_uso_en > now() - interval '30 minutes'
    and lower(btrim(coalesce(s.estado, ''))) = 'activo'
  limit 1;

  if v_socio is not null then
    update public.portal_socio_sesiones
    set ultimo_uso_en = now()
    where token_hash = v_token_clave
      and revocado_en is null;
  end if;

  return v_socio;
end;
$$;

revoke all on function public.portal_socio_validar_sesion(text) from public;

create or replace function public.portal_socio_cerrar_sesion(p_token text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_token is null then
    return true;
  end if;

  update public.portal_socio_sesiones
  set revocado_en = now()
  where token_hash = md5(p_token)
    and revocado_en is null;

  return true;
end;
$$;

grant execute on function public.portal_socio_cerrar_sesion(text)
  to anon, authenticated;

commit;

-- PRUEBA OPCIONAL DESPUÉS DE EJECUTAR ESTE ARCHIVO:
-- select public.portal_socio_ingresar('18.162.605-4', 1);
-- Debe devolver un token largo, no un error de digest().
