-- ============================================================
-- SIGVE v1.0.0 Alpha 10
-- RUT obligatorio, parentesco y consideraciones especiales
-- Ejecutar una sola vez DESPUÉS de Alpha 9.
-- ============================================================
begin;

alter table public.ninos_hogar
  add column if not exists rut text,
  add column if not exists parentesco text,
  add column if not exists participa_actividades boolean not null default true,
  add column if not exists tiene_condicion_especial boolean not null default false,
  add column if not exists condiciones_especiales text[] not null default '{}',
  add column if not exists condicion_otro text,
  add column if not exists observaciones_especiales text,
  add column if not exists autoriza_datos_sensibles boolean not null default false;

create or replace function public.normalizar_rut_chileno(p_rut text)
returns text
language sql
immutable
strict
as $$
  select upper(regexp_replace(p_rut,'[^0-9kK]','','g'));
$$;

create or replace function public.validar_rut_chileno(p_rut text)
returns boolean
language plpgsql
immutable
as $$
declare
  v text := public.normalizar_rut_chileno(coalesce(p_rut,''));
  cuerpo text;
  dv text;
  suma integer := 0;
  multiplicador integer := 2;
  i integer;
  resto integer;
  esperado text;
begin
  if length(v) < 7 then return false; end if;
  cuerpo := left(v,length(v)-1);
  dv := right(v,1);
  if cuerpo !~ '^[0-9]+$' then return false; end if;
  for i in reverse length(cuerpo)..1 loop
    suma := suma + substring(cuerpo from i for 1)::integer * multiplicador;
    multiplicador := case when multiplicador=7 then 2 else multiplicador+1 end;
  end loop;
  resto := 11 - (suma % 11);
  esperado := case when resto=11 then '0' when resto=10 then 'K' else resto::text end;
  return dv=esperado;
end;
$$;

-- Un RUT activo no puede aparecer en dos hogares.
create unique index if not exists ninos_hogar_rut_activo_unique
  on public.ninos_hogar(public.normalizar_rut_chileno(rut))
  where activo=true and rut is not null;

create or replace function public.validar_nino_hogar()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_rut text;
begin
  -- Permite retirar registros antiguos incompletos sin obligar a editarlos primero.
  if tg_op='UPDATE' and new.activo=false then
    new.actualizado_en := now();
    return new;
  end if;
  if new.rut is null or btrim(new.rut)='' then
    raise exception 'El RUT del niño o niña es obligatorio';
  end if;
  if not public.validar_rut_chileno(new.rut) then
    raise exception 'El RUT ingresado no es válido';
  end if;
  v_rut := public.normalizar_rut_chileno(new.rut);
  new.rut := v_rut;

  if new.parentesco is null or btrim(new.parentesco)='' then
    raise exception 'El parentesco es obligatorio';
  end if;
  if new.parentesco not in ('Hijo(a)','Nieto(a)','Sobrino(a)','Bisnieto(a)','Hermano(a)','Tutelado(a)','Otro') then
    raise exception 'Parentesco no válido';
  end if;

  if exists(
    select 1 from public.socios s
    where public.normalizar_rut_chileno(s.rut)=v_rut
  ) then
    raise exception 'Este RUT ya se encuentra registrado como socio';
  end if;

  if new.tiene_condicion_especial and not new.autoriza_datos_sensibles then
    raise exception 'Se requiere autorización para registrar información sensible';
  end if;
  if not new.tiene_condicion_especial then
    new.condiciones_especiales := '{}';
    new.condicion_otro := null;
    new.observaciones_especiales := null;
    new.autoriza_datos_sensibles := false;
  end if;
  new.actualizado_en := now();
  return new;
end;
$$;

drop trigger if exists trg_validar_nino_hogar on public.ninos_hogar;
create trigger trg_validar_nino_hogar
before insert or update on public.ninos_hogar
for each row execute function public.validar_nino_hogar();

-- Reemplazar las RPC anteriores por las versiones ampliadas.
drop function if exists public.listar_ninos_por_token(uuid);
drop function if exists public.registrar_nino_por_token(uuid,text,date,text);
drop function if exists public.actualizar_nino_por_token(uuid,uuid,text,date,text);

create function public.listar_ninos_por_token(p_token uuid)
returns table(
  id uuid,rut text,nombre_completo text,fecha_nacimiento date,sexo text,
  parentesco text,participa_actividades boolean,tiene_condicion_especial boolean,
  condiciones_especiales text[],condicion_otro text,
  observaciones_especiales text,autoriza_datos_sensibles boolean
)
language sql
security definer
stable
set search_path=public
as $$
  select n.id,n.rut,n.nombre_completo,n.fecha_nacimiento,n.sexo,
         n.parentesco,n.participa_actividades,n.tiene_condicion_especial,
         n.condiciones_especiales,n.condicion_otro,
         n.observaciones_especiales,n.autoriza_datos_sensibles
  from public.ninos_hogar n
  join public.socios s on s.id=n.socio_id
  where s.registro_ninos_token=p_token
    and s.estado='activo'
    and n.activo=true
  order by n.fecha_nacimiento,n.nombre_completo;
$$;

create function public.registrar_nino_por_token(
  p_token uuid,p_rut text,p_nombre text,p_fecha_nacimiento date,p_sexo text,
  p_parentesco text,p_participa_actividades boolean,
  p_tiene_condicion_especial boolean,p_condiciones_especiales text[],
  p_condicion_otro text,p_observaciones_especiales text,
  p_autoriza_datos_sensibles boolean
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare v_socio uuid; v_id uuid;
begin
  select id into v_socio from public.socios
  where registro_ninos_token=p_token and estado='activo';
  if v_socio is null then raise exception 'Enlace inválido o vencido'; end if;
  if length(trim(coalesce(p_nombre,'')))<3 then raise exception 'Debe indicar el nombre completo'; end if;
  if p_fecha_nacimiento is null or p_fecha_nacimiento>current_date then raise exception 'Fecha inválida'; end if;
  if p_sexo not in('M','F') then raise exception 'Sexo inválido'; end if;

  insert into public.ninos_hogar(
    socio_id,rut,nombre_completo,fecha_nacimiento,sexo,parentesco,
    participa_actividades,tiene_condicion_especial,condiciones_especiales,
    condicion_otro,observaciones_especiales,autoriza_datos_sensibles
  ) values(
    v_socio,p_rut,trim(p_nombre),p_fecha_nacimiento,p_sexo,p_parentesco,
    coalesce(p_participa_actividades,true),coalesce(p_tiene_condicion_especial,false),
    coalesce(p_condiciones_especiales,'{}'),nullif(trim(coalesce(p_condicion_otro,'')),''),
    nullif(trim(coalesce(p_observaciones_especiales,'')),''),
    coalesce(p_autoriza_datos_sensibles,false)
  ) returning id into v_id;
  return v_id;
end;
$$;

create function public.actualizar_nino_por_token(
  p_token uuid,p_nino_id uuid,p_rut text,p_nombre text,p_fecha_nacimiento date,p_sexo text,
  p_parentesco text,p_participa_actividades boolean,
  p_tiene_condicion_especial boolean,p_condiciones_especiales text[],
  p_condicion_otro text,p_observaciones_especiales text,
  p_autoriza_datos_sensibles boolean
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare v_socio uuid; v_rut_actual text;
begin
  select id into v_socio from public.socios
  where registro_ninos_token=p_token and estado='activo';
  if v_socio is null then raise exception 'Enlace inválido o vencido'; end if;
  select rut into v_rut_actual from public.ninos_hogar
   where id=p_nino_id and socio_id=v_socio and activo=true;
  if not found then raise exception 'Registro no encontrado'; end if;
  if v_rut_actual is not null and public.normalizar_rut_chileno(v_rut_actual)<>public.normalizar_rut_chileno(p_rut) then
    raise exception 'El RUT no puede modificarse después de guardar el registro';
  end if;
  if length(trim(coalesce(p_nombre,'')))<3 then raise exception 'Debe indicar el nombre completo'; end if;
  if p_fecha_nacimiento is null or p_fecha_nacimiento>current_date then raise exception 'Fecha inválida'; end if;
  if p_sexo not in('M','F') then raise exception 'Sexo inválido'; end if;

  update public.ninos_hogar set
    rut=p_rut,nombre_completo=trim(p_nombre),fecha_nacimiento=p_fecha_nacimiento,
    sexo=p_sexo,parentesco=p_parentesco,
    participa_actividades=coalesce(p_participa_actividades,true),
    tiene_condicion_especial=coalesce(p_tiene_condicion_especial,false),
    condiciones_especiales=coalesce(p_condiciones_especiales,'{}'),
    condicion_otro=nullif(trim(coalesce(p_condicion_otro,'')),''),
    observaciones_especiales=nullif(trim(coalesce(p_observaciones_especiales,'')),''),
    autoriza_datos_sensibles=coalesce(p_autoriza_datos_sensibles,false)
  where id=p_nino_id and socio_id=v_socio and activo=true;
  return true;
end;
$$;

revoke all on function public.listar_ninos_por_token(uuid) from public;
revoke all on function public.registrar_nino_por_token(uuid,text,text,date,text,text,boolean,boolean,text[],text,text,boolean) from public;
revoke all on function public.actualizar_nino_por_token(uuid,uuid,text,text,date,text,text,boolean,boolean,text[],text,text,boolean) from public;
grant execute on function public.listar_ninos_por_token(uuid) to anon,authenticated;
grant execute on function public.registrar_nino_por_token(uuid,text,text,date,text,text,boolean,boolean,text[],text,text,boolean) to anon,authenticated;
grant execute on function public.actualizar_nino_por_token(uuid,uuid,text,text,date,text,text,boolean,boolean,text[],text,text,boolean) to anon,authenticated;

commit;
notify pgrst,'reload schema';
