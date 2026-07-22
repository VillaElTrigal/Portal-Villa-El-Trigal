-- Portal Vecinal Villa El Trigal v1.0
-- Actualización del módulo Socios, niños y niñas, bajas y auditoría.
-- Ejecutar una sola vez en Supabase > SQL Editor.

begin;

-- 1) Nuevos campos y estados del socio
alter table public.socios
  add column if not exists autoriza_whatsapp boolean not null default false,
  add column if not exists registro_ninos_token uuid not null default gen_random_uuid(),
  add column if not exists fecha_baja date,
  add column if not exists motivo_baja text,
  add column if not exists observaciones_baja text;

create unique index if not exists socios_registro_ninos_token_unique
  on public.socios(registro_ninos_token);

alter table public.solicitudes_socios
  add column if not exists autoriza_whatsapp boolean not null default false;

-- Sustituye la validación antigua de estados.
do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid='public.socios'::regclass and contype='c'
  loop
    if pg_get_constraintdef(c.oid) ilike '%estado%' then
      execute format('alter table public.socios drop constraint %I',c.conname);
    end if;
  end loop;
end $$;

update public.socios set estado='baja' where estado='inactivo';
update public.socios set estado='pendiente' where estado='rechazado';

alter table public.socios
  add constraint socios_estado_check
  check (estado in ('pendiente','activo','baja','suspendido','fallecido'));

-- 2) Número correlativo solo al quedar activo.
-- Se elimina el identity que consumía números aun cuando se borraban pruebas.
alter table public.socios alter column numero_socio drop identity if exists;
create sequence if not exists public.socios_numero_socio_seq;
alter sequence public.socios_numero_socio_seq owned by public.socios.numero_socio;
alter table public.socios alter column numero_socio drop default;

create or replace function public.asignar_numero_socio()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.estado='activo' and new.numero_socio is null then
    new.numero_socio := nextval('public.socios_numero_socio_seq');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_asignar_numero_socio on public.socios;
create trigger trg_asignar_numero_socio
before insert or update of estado on public.socios
for each row execute function public.asignar_numero_socio();

-- Ajusta la secuencia al máximo existente. Si no hay socios, vuelve a 1.
select setval(
  'public.socios_numero_socio_seq',
  greatest(coalesce((select max(numero_socio) from public.socios),0),1),
  coalesce((select max(numero_socio) from public.socios),0) > 0
);

-- 3) Niños y niñas del hogar. La dirección se obtiene siempre desde socios.
create table if not exists public.ninos_hogar (
  id uuid primary key default gen_random_uuid(),
  socio_id uuid not null references public.socios(id) on delete restrict,
  nombre_completo text not null,
  fecha_nacimiento date not null,
  sexo text not null check(sexo in ('F','M')),
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  creado_por uuid references auth.users(id)
);

create index if not exists ninos_hogar_socio_idx on public.ninos_hogar(socio_id);

-- Migra registros antiguos que correspondan a niños/as, sin duplicarlos.
insert into public.ninos_hogar(socio_id,nombre_completo,fecha_nacimiento,sexo,creado_en,actualizado_en,creado_por)
select gf.socio_id,gf.nombre_completo,gf.fecha_nacimiento,gf.sexo,gf.creado_en,gf.actualizado_en,gf.creado_por
from public.grupo_familiar gf
where not exists (
  select 1 from public.ninos_hogar nh
  where nh.socio_id=gf.socio_id
    and lower(nh.nombre_completo)=lower(gf.nombre_completo)
    and nh.fecha_nacimiento=gf.fecha_nacimiento
);

-- 4) Auditoría inmutable desde el panel.
create table if not exists public.auditoria (
  id bigint generated always as identity primary key,
  modulo text not null,
  registro_id uuid,
  accion text not null,
  detalle jsonb not null default '{}'::jsonb,
  usuario_id uuid references auth.users(id),
  creado_en timestamptz not null default now()
);

create index if not exists auditoria_registro_idx on public.auditoria(registro_id,creado_en desc);

-- Evita borrar socios físicamente. Deben cambiarse a estado Baja/Fallecido.
create or replace function public.impedir_borrado_socio()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Los socios no se eliminan. Cambie su estado a Baja, Suspendido o Fallecido.';
end;
$$;

drop trigger if exists trg_impedir_borrado_socio on public.socios;
create trigger trg_impedir_borrado_socio
before delete on public.socios
for each row execute function public.impedir_borrado_socio();

-- Auditoría automática de cambios de estado.
create or replace function public.auditar_estado_socio()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if tg_op='INSERT' then
    insert into public.auditoria(modulo,registro_id,accion,detalle,usuario_id)
    values('socios',new.id,'socio creado',jsonb_build_object('estado',new.estado,'numero_socio',new.numero_socio),auth.uid());
  elsif old.estado is distinct from new.estado then
    insert into public.auditoria(modulo,registro_id,accion,detalle,usuario_id)
    values('socios',new.id,'cambio de estado',jsonb_build_object('estado_anterior',old.estado,'estado_nuevo',new.estado),auth.uid());
  end if;
  return new;
end;
$$;

drop trigger if exists trg_auditar_estado_socio on public.socios;
create trigger trg_auditar_estado_socio
after insert or update of estado on public.socios
for each row execute function public.auditar_estado_socio();

-- 5) Funciones públicas seguras para que el socio registre niños/as con su enlace personal.
create or replace function public.obtener_socio_por_token_ninos(p_token uuid)
returns table(nombre_completo text,direccion text)
language sql
security definer
stable
set search_path=public
as $$
  select s.nombre_completo,s.direccion
  from public.socios s
  where s.registro_ninos_token=p_token
    and s.estado='activo';
$$;

create or replace function public.listar_ninos_por_token(p_token uuid)
returns table(nombre_completo text,fecha_nacimiento date,sexo text)
language sql
security definer
stable
set search_path=public
as $$
  select n.nombre_completo,n.fecha_nacimiento,n.sexo
  from public.ninos_hogar n
  join public.socios s on s.id=n.socio_id
  where s.registro_ninos_token=p_token
    and s.estado='activo'
    and n.activo=true
  order by n.fecha_nacimiento;
$$;

create or replace function public.registrar_nino_por_token(
  p_token uuid,
  p_nombre text,
  p_fecha_nacimiento date,
  p_sexo text
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
  if v_socio is null then raise exception 'Enlace inválido o socio no activo'; end if;
  if nullif(trim(p_nombre),'') is null then raise exception 'Debe indicar el nombre'; end if;
  if p_fecha_nacimiento is null or p_fecha_nacimiento>current_date then raise exception 'Fecha de nacimiento inválida'; end if;
  if p_sexo not in ('F','M') then raise exception 'Sexo inválido'; end if;
  insert into public.ninos_hogar(socio_id,nombre_completo,fecha_nacimiento,sexo)
  values(v_socio,trim(p_nombre),p_fecha_nacimiento,p_sexo)
  returning id into v_id;
  insert into public.auditoria(modulo,registro_id,accion,detalle)
  values('socios',v_socio,'niño/a registrado por socio',jsonb_build_object('nino_id',v_id,'nombre',trim(p_nombre)));
  return v_id;
end;
$$;

grant execute on function public.obtener_socio_por_token_ninos(uuid) to anon,authenticated;
grant execute on function public.listar_ninos_por_token(uuid) to anon,authenticated;
grant execute on function public.registrar_nino_por_token(uuid,text,date,text) to anon,authenticated;

-- 6) RLS
alter table public.ninos_hogar enable row level security;
alter table public.auditoria enable row level security;

drop policy if exists "Admin gestiona ninos_hogar" on public.ninos_hogar;
create policy "Admin gestiona ninos_hogar" on public.ninos_hogar
for all to authenticated using(public.es_admin()) with check(public.es_admin());

drop policy if exists "Admin consulta auditoria" on public.auditoria;
create policy "Admin consulta auditoria" on public.auditoria
for select to authenticated using(public.es_admin());

drop policy if exists "Admin registra auditoria" on public.auditoria;
create policy "Admin registra auditoria" on public.auditoria
for insert to authenticated with check(public.es_admin());

commit;
