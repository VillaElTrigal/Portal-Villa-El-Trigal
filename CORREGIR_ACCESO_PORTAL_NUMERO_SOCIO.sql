-- SIGVE · Corrección de acceso por RUT + número de socio
-- Acepta 1, 01, 001, etc. como el mismo número de socio.
-- Ejecutar una sola vez en Supabase > SQL Editor.

begin;

-- Se eliminan las versiones anteriores para evitar ambigüedad en RPC.
drop function if exists public.portal_socio_ingresar(text,bigint);
drop function if exists public.portal_socio_ingresar(text,text);
drop function if exists public.portal_socio_renunciar_numero(text,bigint,text);
drop function if exists public.portal_socio_renunciar_numero(text,text,text);

create or replace function public.portal_socio_ingresar(
  p_rut text,
  p_numero_socio text
)
returns text
language plpgsql
security definer
set search_path=public
as $$
declare
  v_rut text;
  v_numero text;
  v_hash text;
  v_socio uuid;
  v_token text;
  v_fallos integer;
begin
  v_rut := upper(regexp_replace(coalesce(p_rut,''), '[^0-9Kk]', '', 'g'));
  v_numero := regexp_replace(coalesce(p_numero_socio,''), '[^0-9]', '', 'g');

  -- Quita ceros iniciales: 001 -> 1. Conserva 0 si ese fuera el valor.
  v_numero := coalesce(nullif(ltrim(v_numero, '0'), ''), '0');

  if v_rut = '' or regexp_replace(coalesce(p_numero_socio,''), '[^0-9]', '', 'g') = '' then
    return null;
  end if;

  v_hash := encode(digest(v_rut, 'sha256'), 'hex');

  select count(*) into v_fallos
  from public.portal_socio_intentos
  where rut_hash = v_hash
    and exitoso = false
    and creado_en > now() - interval '15 minutes';

  if v_fallos >= 5 then
    raise exception 'Demasiados intentos. Intenta nuevamente en 15 minutos';
  end if;

  select s.id into v_socio
  from public.socios s
  where upper(regexp_replace(coalesce(s.rut,''), '[^0-9Kk]', '', 'g')) = v_rut
    and coalesce(nullif(ltrim(regexp_replace(coalesce(s.numero_socio::text,''), '[^0-9]', '', 'g'), '0'), ''), '0') = v_numero
    and lower(btrim(coalesce(s.estado,''))) = 'activo'
  limit 1;

  insert into public.portal_socio_intentos(rut_hash, exitoso)
  values (v_hash, v_socio is not null);

  if v_socio is null then
    return null;
  end if;

  v_token := encode(gen_random_bytes(32), 'hex');

  insert into public.portal_socio_sesiones(socio_id, token_hash, expira_en)
  values (
    v_socio,
    encode(digest(v_token, 'sha256'), 'hex'),
    now() + interval '8 hours'
  );

  insert into public.portal_socio_auditoria(socio_id, accion)
  values (v_socio, 'inicio_sesion_numero_socio');

  return v_token;
end;
$$;

grant execute on function public.portal_socio_ingresar(text,text) to anon, authenticated;

create or replace function public.portal_socio_renunciar_numero(
  p_token text,
  p_numero_socio text,
  p_motivo text default null
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  v_socio uuid;
  v_numero text;
begin
  v_socio := public.portal_socio_validar_sesion(p_token);

  if v_socio is null then
    raise exception 'Sesión inválida o vencida';
  end if;

  v_numero := regexp_replace(coalesce(p_numero_socio,''), '[^0-9]', '', 'g');
  v_numero := coalesce(nullif(ltrim(v_numero, '0'), ''), '0');

  if not exists (
    select 1
    from public.socios s
    where s.id = v_socio
      and coalesce(nullif(ltrim(regexp_replace(coalesce(s.numero_socio::text,''), '[^0-9]', '', 'g'), '0'), ''), '0') = v_numero
      and lower(btrim(coalesce(s.estado,''))) = 'activo'
  ) then
    raise exception 'El número de socio no coincide';
  end if;

  update public.socios
  set estado = 'renunciado',
      renuncia_fecha = now(),
      renuncia_medio = 'Portal del Socio',
      renuncia_motivo = nullif(btrim(p_motivo), ''),
      actualizado_en = now()
  where id = v_socio;

  insert into public.portal_socio_auditoria(socio_id, accion, detalle)
  values (
    v_socio,
    'renuncia_voluntaria',
    jsonb_build_object('motivo', nullif(btrim(p_motivo), ''))
  );

  update public.portal_socio_sesiones
  set revocado_en = now()
  where socio_id = v_socio
    and revocado_en is null;

  return true;
end;
$$;

grant execute on function public.portal_socio_renunciar_numero(text,text,text) to anon, authenticated;

commit;
