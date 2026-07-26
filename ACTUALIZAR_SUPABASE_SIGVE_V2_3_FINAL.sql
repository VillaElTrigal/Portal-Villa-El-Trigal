-- SIGVE v2.3 FINAL · Registro de niños y niñas
-- Migración incremental compatible con las funciones actuales de RC2.
-- No elimina tablas ni datos. Activa RLS en la única tabla nueva.

begin;

create extension if not exists pgcrypto;

alter table public.socios
  add column if not exists registro_ninos_expira_en timestamptz,
  add column if not exists registro_ninos_estado text not null default 'pendiente',
  add column if not exists registro_ninos_completado_en timestamptz,
  add column if not exists registro_ninos_ultimo_reenvio_en timestamptz,
  add column if not exists registro_ninos_reenvios integer not null default 0;

-- Estados permitidos sin depender de un CHECK previo que pudiera diferir entre versiones.
update public.socios
set registro_ninos_estado='pendiente'
where registro_ninos_estado is null
   or registro_ninos_estado not in ('pendiente','con_ninos','sin_ninos');

update public.socios
set registro_ninos_expira_en = now() + interval '30 days'
where registro_ninos_token is not null
  and registro_ninos_expira_en is null;

create table if not exists public.registro_ninos_envios (
  id uuid primary key default gen_random_uuid(),
  socio_id uuid not null references public.socios(id) on delete cascade,
  token_anterior uuid,
  token_nuevo uuid not null,
  medio text not null default 'ambos',
  estado text not null default 'pendiente',
  solicitado_en timestamptz not null default now(),
  enviado_en timestamptz,
  detalle text
);

alter table public.registro_ninos_envios enable row level security;
revoke all on table public.registro_ninos_envios from anon, authenticated;

create index if not exists registro_ninos_envios_socio_fecha_idx
  on public.registro_ninos_envios(socio_id, solicitado_en desc);

create or replace function public.sigve_preparar_token_ninos()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if tg_op='INSERT' then
    if new.registro_ninos_token is not null and new.registro_ninos_expira_en is null then
      new.registro_ninos_expira_en := now() + interval '30 days';
    end if;
  elsif new.registro_ninos_token is distinct from old.registro_ninos_token then
    if new.registro_ninos_token is not null then
      new.registro_ninos_expira_en := now() + interval '30 days';
      new.registro_ninos_estado := 'pendiente';
      new.registro_ninos_completado_en := null;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sigve_preparar_token_ninos on public.socios;
create trigger trg_sigve_preparar_token_ninos
before insert or update of registro_ninos_token on public.socios
for each row execute function public.sigve_preparar_token_ninos();

create or replace function public.estado_registro_ninos_por_token(p_token uuid)
returns table(
  estado text,
  nombre_completo text,
  numero_socio bigint,
  direccion text,
  expira_en timestamptz,
  puede_renovar boolean
)
language sql
security definer
stable
set search_path=public
as $$
  select
    case
      when s.id is null then 'invalido'
      when s.estado <> 'activo' then 'invalido'
      when s.registro_ninos_estado='sin_ninos' then 'sin_ninos'
      when s.registro_ninos_expira_en is null or s.registro_ninos_expira_en < now() then 'vencido'
      else 'vigente'
    end,
    s.nombre_completo,
    s.numero_socio,
    s.direccion,
    s.registro_ninos_expira_en,
    case
      when s.id is null or s.estado <> 'activo' then false
      when s.registro_ninos_ultimo_reenvio_en is null then true
      else s.registro_ninos_ultimo_reenvio_en <= now() - interval '24 hours'
    end
  from (select 1) q
  left join public.socios s on s.registro_ninos_token=p_token
  limit 1;
$$;

create or replace function public.declarar_hogar_sin_ninos(p_token uuid)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare v_socio uuid;
begin
  select id into v_socio
  from public.socios
  where registro_ninos_token=p_token
    and estado='activo'
    and registro_ninos_expira_en >= now();
  if v_socio is null then raise exception 'Enlace inválido o vencido'; end if;

  update public.socios
     set registro_ninos_estado='sin_ninos',
         registro_ninos_completado_en=now(),
         actualizado_en=now()
   where id=v_socio;
  return true;
end;
$$;

create or replace function public.solicitar_nuevo_enlace_ninos(
  p_token uuid,
  p_medio text default 'ambos'
)
returns table(
  ok boolean,
  mensaje text,
  nuevo_token uuid,
  telefono text,
  correo text,
  medio text
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_socio public.socios%rowtype;
  v_token uuid := gen_random_uuid();
  v_medio text := lower(coalesce(nullif(trim(p_medio),''),'ambos'));
begin
  select * into v_socio from public.socios where registro_ninos_token=p_token limit 1;
  if v_socio.id is null or v_socio.estado <> 'activo' then
    return query select false,'No fue posible identificar un socio activo.',null::uuid,null::text,null::text,v_medio;
    return;
  end if;
  if v_socio.registro_ninos_ultimo_reenvio_en is not null
     and v_socio.registro_ninos_ultimo_reenvio_en > now() - interval '24 hours' then
    return query select false,'Ya se solicitó un enlace durante las últimas 24 horas.',null::uuid,v_socio.telefono,v_socio.correo,v_medio;
    return;
  end if;
  if v_medio not in ('correo','whatsapp','ambos') then v_medio := 'ambos'; end if;

  update public.socios
     set registro_ninos_token=v_token,
         registro_ninos_expira_en=now()+interval '30 days',
         registro_ninos_estado='pendiente',
         registro_ninos_completado_en=null,
         registro_ninos_ultimo_reenvio_en=now(),
         registro_ninos_reenvios=coalesce(registro_ninos_reenvios,0)+1,
         actualizado_en=now()
   where id=v_socio.id;

  insert into public.registro_ninos_envios(
    socio_id,token_anterior,token_nuevo,medio,estado,detalle
  ) values(
    v_socio.id,p_token,v_token,v_medio,'pendiente',
    'Enlace renovado. Pendiente de entrega por proveedor externo o apertura del canal por el vecino.'
  );

  return query select true,'Se generó un nuevo enlace con vigencia de 30 días.',v_token,v_socio.telefono,v_socio.correo,v_medio;
end;
$$;

-- Mantiene exactamente las firmas y retornos actuales; solo incorpora la vigencia.
create or replace function public.obtener_socio_por_token_ninos(p_token uuid)
returns table(id uuid,numero_socio bigint,nombre_completo text,direccion text)
language sql
security definer
stable
set search_path=public
as $$
  select s.id,s.numero_socio,s.nombre_completo,s.direccion
  from public.socios s
  where s.registro_ninos_token=p_token
    and s.estado='activo'
    and s.registro_ninos_estado <> 'sin_ninos'
    and s.registro_ninos_expira_en >= now()
  limit 1;
$$;

create or replace function public.listar_ninos_por_token(p_token uuid)
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
    and s.registro_ninos_estado <> 'sin_ninos'
    and s.registro_ninos_expira_en >= now()
    and n.activo=true
  order by n.fecha_nacimiento,n.nombre_completo;
$$;

create or replace function public.registrar_nino_por_token(
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
  where registro_ninos_token=p_token and estado='activo'
    and registro_ninos_estado <> 'sin_ninos'
    and registro_ninos_expira_en >= now();
  if v_socio is null then raise exception 'Enlace inválido o vencido'; end if;
  if not public.rut_chileno_valido(p_rut) then raise exception 'El RUT ingresado no es válido'; end if;
  if length(trim(coalesce(p_nombre,'')))<3 then raise exception 'Debe indicar el nombre completo'; end if;
  if p_fecha_nacimiento is null or p_fecha_nacimiento>current_date then raise exception 'Fecha inválida'; end if;
  if p_sexo not in('M','F') then raise exception 'Sexo inválido'; end if;
  if nullif(trim(coalesce(p_parentesco,'')),'') is null then raise exception 'Debe indicar el parentesco'; end if;

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

  update public.socios set registro_ninos_estado='con_ninos',registro_ninos_completado_en=now(),actualizado_en=now()
  where id=v_socio;
  return v_id;
end;
$$;

create or replace function public.actualizar_nino_por_token(
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
  where registro_ninos_token=p_token and estado='activo'
    and registro_ninos_estado <> 'sin_ninos'
    and registro_ninos_expira_en >= now();
  if v_socio is null then raise exception 'Enlace inválido o vencido'; end if;
  select rut into v_rut_actual from public.ninos_hogar
   where id=p_nino_id and socio_id=v_socio and activo=true;
  if not found then raise exception 'Registro no encontrado'; end if;
  if not public.rut_chileno_valido(p_rut) then raise exception 'El RUT ingresado no es válido'; end if;
  if v_rut_actual is not null and public.normalizar_rut_chileno(v_rut_actual)<>public.normalizar_rut_chileno(p_rut) then
    raise exception 'El RUT no puede modificarse después de guardar el registro';
  end if;
  if length(trim(coalesce(p_nombre,'')))<3 then raise exception 'Debe indicar el nombre completo'; end if;
  if p_fecha_nacimiento is null or p_fecha_nacimiento>current_date then raise exception 'Fecha inválida'; end if;
  if p_sexo not in('M','F') then raise exception 'Sexo inválido'; end if;
  if nullif(trim(coalesce(p_parentesco,'')),'') is null then raise exception 'Debe indicar el parentesco'; end if;

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

create or replace function public.eliminar_nino_por_token(p_token uuid,p_nino_id uuid)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare v_socio uuid;
begin
  select id into v_socio from public.socios
  where registro_ninos_token=p_token and estado='activo'
    and registro_ninos_estado <> 'sin_ninos'
    and registro_ninos_expira_en >= now();
  if v_socio is null then raise exception 'Enlace inválido o vencido'; end if;
  update public.ninos_hogar set activo=false,actualizado_en=now()
   where id=p_nino_id and socio_id=v_socio and activo=true;
  if not found then raise exception 'Registro no encontrado'; end if;
  return true;
end;
$$;

revoke all on function public.estado_registro_ninos_por_token(uuid) from public;
revoke all on function public.declarar_hogar_sin_ninos(uuid) from public;
revoke all on function public.solicitar_nuevo_enlace_ninos(uuid,text) from public;
grant execute on function public.estado_registro_ninos_por_token(uuid) to anon,authenticated;
grant execute on function public.declarar_hogar_sin_ninos(uuid) to anon,authenticated;
grant execute on function public.solicitar_nuevo_enlace_ninos(uuid,text) to anon,authenticated;

-- Conserva los permisos públicos que ya utiliza el formulario.
revoke all on function public.obtener_socio_por_token_ninos(uuid) from public;
revoke all on function public.listar_ninos_por_token(uuid) from public;
revoke all on function public.registrar_nino_por_token(uuid,text,text,date,text,text,boolean,boolean,text[],text,text,boolean) from public;
revoke all on function public.actualizar_nino_por_token(uuid,uuid,text,text,date,text,text,boolean,boolean,text[],text,text,boolean) from public;
revoke all on function public.eliminar_nino_por_token(uuid,uuid) from public;
grant execute on function public.obtener_socio_por_token_ninos(uuid) to anon,authenticated;
grant execute on function public.listar_ninos_por_token(uuid) to anon,authenticated;
grant execute on function public.registrar_nino_por_token(uuid,text,text,date,text,text,boolean,boolean,text[],text,text,boolean) to anon,authenticated;
grant execute on function public.actualizar_nino_por_token(uuid,uuid,text,text,date,text,text,boolean,boolean,text[],text,text,boolean) to anon,authenticated;
grant execute on function public.eliminar_nino_por_token(uuid,uuid) to anon,authenticated;

commit;
