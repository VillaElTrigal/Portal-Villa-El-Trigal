-- PORTAL VILLA EL TRIGAL v7.1 - MIGRACION/REPARACION INTEGRAL
-- Seguro para bases donde v7 se ejecuto completa, parcialmente o donde ya existian tablas.
-- Ejecutar UNA VEZ en Supabase > SQL Editor con rol postgres.

begin;

create extension if not exists pgcrypto;

-- Funcion de autorizacion ya utilizada por el portal.
create or replace function public.es_admin()
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists(
    select 1 from public.administradores a
    where a.user_id=auth.uid() and coalesce(a.activo,true)=true
  )
$$;

-- CONFIGURACION
create table if not exists public.configuracion_gestion (id integer primary key);
alter table public.configuracion_gestion
  add column if not exists valor_arriendo numeric(12,0) default 40000,
  add column if not exists abono_minimo numeric(12,0) default 10000,
  add column if not exists valor_certificado numeric(12,0) default 1000,
  add column if not exists valor_cuota numeric(12,0) default 2000,
  add column if not exists valor_zumba numeric(12,0) default 2000,
  add column if not exists edad_max_navidad integer default 10,
  add column if not exists actualizado_en timestamptz default now(),
  add column if not exists actualizado_por uuid references auth.users(id);
insert into public.configuracion_gestion(id) values(1) on conflict(id) do nothing;
update public.configuracion_gestion set
 valor_arriendo=coalesce(valor_arriendo,40000), abono_minimo=coalesce(abono_minimo,10000),
 valor_certificado=coalesce(valor_certificado,1000), valor_cuota=coalesce(valor_cuota,2000),
 valor_zumba=coalesce(valor_zumba,2000), edad_max_navidad=coalesce(edad_max_navidad,10)
where id=1;

-- SOCIOS
create table if not exists public.socios (id uuid primary key default gen_random_uuid());
alter table public.socios
  add column if not exists numero_socio bigint,
  add column if not exists nombre_completo text,
  add column if not exists rut text,
  add column if not exists direccion text,
  add column if not exists telefono text,
  add column if not exists correo text,
  add column if not exists fecha_ingreso date default current_date,
  add column if not exists estado text default 'activo',
  add column if not exists observaciones text,
  add column if not exists foto_url text,
  add column if not exists creado_en timestamptz default now(),
  add column if not exists actualizado_en timestamptz default now(),
  add column if not exists creado_por uuid references auth.users(id);

-- Numeracion automatica compatible con tablas antiguas.
create sequence if not exists public.socios_numero_socio_seq;
select setval('public.socios_numero_socio_seq', greatest(coalesce((select max(numero_socio) from public.socios),0),1), true);
alter table public.socios alter column numero_socio set default nextval('public.socios_numero_socio_seq');
update public.socios set numero_socio=nextval('public.socios_numero_socio_seq') where numero_socio is null;
create unique index if not exists socios_numero_socio_uidx on public.socios(numero_socio);
create unique index if not exists socios_rut_uidx on public.socios(rut) where rut is not null and btrim(rut)<>'';
update public.socios set estado=lower(btrim(estado)) where estado is not null;
update public.socios set estado='activo' where estado is null or estado not in ('activo','inactivo','pendiente','rechazado');
alter table public.socios drop constraint if exists socios_estado_check;
alter table public.socios add constraint socios_estado_check check(estado in ('activo','inactivo','pendiente','rechazado'));

-- GRUPO FAMILIAR
create table if not exists public.grupo_familiar (id uuid primary key default gen_random_uuid());
alter table public.grupo_familiar
  add column if not exists socio_id uuid references public.socios(id) on delete cascade,
  add column if not exists nombre_completo text,
  add column if not exists rut text,
  add column if not exists fecha_nacimiento date,
  add column if not exists sexo text,
  add column if not exists parentesco text default 'Hijo(a)',
  add column if not exists direccion text,
  add column if not exists observaciones text,
  add column if not exists creado_en timestamptz default now(),
  add column if not exists actualizado_en timestamptz default now(),
  add column if not exists creado_por uuid references auth.users(id);
update public.grupo_familiar set sexo=upper(btrim(sexo)) where sexo is not null;
alter table public.grupo_familiar drop constraint if exists grupo_familiar_sexo_check;
alter table public.grupo_familiar add constraint grupo_familiar_sexo_check check(sexo is null or sexo in ('F','M'));
create unique index if not exists grupo_familiar_rut_unique on public.grupo_familiar(rut) where rut is not null and btrim(rut)<>'';

-- SOLICITUDES PUBLICAS DE SOCIOS
create table if not exists public.solicitudes_socios (id uuid primary key default gen_random_uuid());
alter table public.solicitudes_socios
  add column if not exists nombre_completo text,
  add column if not exists rut text,
  add column if not exists direccion text,
  add column if not exists telefono text,
  add column if not exists correo text,
  add column if not exists observaciones text,
  add column if not exists estado text default 'pendiente',
  add column if not exists creado_en timestamptz default now(),
  add column if not exists revisado_en timestamptz,
  add column if not exists revisado_por uuid references auth.users(id);
update public.solicitudes_socios set estado=lower(btrim(estado)) where estado is not null;
update public.solicitudes_socios set estado='pendiente' where estado is null or estado not in ('pendiente','aprobado','rechazado');
alter table public.solicitudes_socios drop constraint if exists solicitudes_socios_estado_check;
alter table public.solicitudes_socios add constraint solicitudes_socios_estado_check check(estado in ('pendiente','aprobado','rechazado'));

-- RESERVAS / ACTIVIDADES DE SEDE
create table if not exists public.reservas_sede (id uuid primary key default gen_random_uuid());
alter table public.reservas_sede
  add column if not exists nombre_arrendatario text,
  add column if not exists rut text,
  add column if not exists telefono text,
  add column if not exists fecha_evento date,
  add column if not exists hora_inicio time default '08:00',
  add column if not exists hora_termino time default '22:00',
  add column if not exists tipo text default 'arriendo',
  add column if not exists descripcion text,
  add column if not exists valor_total numeric(12,0) default 40000,
  add column if not exists estado text default 'pendiente',
  add column if not exists whatsapp_enviado boolean default false,
  add column if not exists creado_en timestamptz default now(),
  add column if not exists actualizado_en timestamptz default now(),
  add column if not exists creado_por uuid references auth.users(id);
update public.reservas_sede set tipo=lower(btrim(tipo)), estado=lower(btrim(estado));
update public.reservas_sede set tipo='arriendo' where tipo is null or tipo not in ('arriendo','actividad','bloqueo','zumba');
update public.reservas_sede set estado='pendiente' where estado is null or estado not in ('pendiente','aprobado','confirmado','finalizado','cancelado','archivado');
alter table public.reservas_sede drop constraint if exists reservas_sede_tipo_check;
alter table public.reservas_sede drop constraint if exists reservas_sede_estado_check;
alter table public.reservas_sede add constraint reservas_sede_tipo_check check(tipo in ('arriendo','actividad','bloqueo','zumba'));
alter table public.reservas_sede add constraint reservas_sede_estado_check check(estado in ('pendiente','aprobado','confirmado','finalizado','cancelado','archivado'));
create unique index if not exists reserva_fecha_unica_activa on public.reservas_sede(fecha_evento) where estado not in ('cancelado','archivado');

-- FINANZAS
create table if not exists public.movimientos_financieros (id uuid primary key default gen_random_uuid());
alter table public.movimientos_financieros
  add column if not exists fecha date default current_date,
  add column if not exists tipo text,
  add column if not exists concepto text,
  add column if not exists categoria text,
  add column if not exists monto numeric(12,0),
  add column if not exists fondo text,
  add column if not exists fondo_origen text,
  add column if not exists fondo_destino text,
  add column if not exists reserva_id uuid references public.reservas_sede(id) on delete set null,
  add column if not exists socio_id uuid references public.socios(id) on delete set null,
  add column if not exists comprobante_url text,
  add column if not exists proveedor text,
  add column if not exists numero_documento text,
  add column if not exists observaciones text,
  add column if not exists sin_respaldo boolean default false,
  add column if not exists creado_en timestamptz default now(),
  add column if not exists creado_por uuid references auth.users(id);
alter table public.movimientos_financieros drop constraint if exists movimientos_financieros_tipo_check;
alter table public.movimientos_financieros drop constraint if exists movimientos_financieros_fondo_check;
alter table public.movimientos_financieros drop constraint if exists movimientos_financieros_fondo_origen_check;
alter table public.movimientos_financieros drop constraint if exists movimientos_financieros_fondo_destino_check;
alter table public.movimientos_financieros drop constraint if exists movimiento_fondos_validos;
alter table public.movimientos_financieros add constraint movimientos_financieros_tipo_check check(tipo in ('ingreso','gasto','transferencia'));
alter table public.movimientos_financieros add constraint movimientos_financieros_fondo_check check(fondo is null or fondo in ('caja','banco'));
alter table public.movimientos_financieros add constraint movimientos_financieros_fondo_origen_check check(fondo_origen is null or fondo_origen in ('caja','banco'));
alter table public.movimientos_financieros add constraint movimientos_financieros_fondo_destino_check check(fondo_destino is null or fondo_destino in ('caja','banco'));
alter table public.movimientos_financieros add constraint movimiento_fondos_validos check(
 (tipo in ('ingreso','gasto') and fondo is not null and fondo_origen is null and fondo_destino is null)
 or (tipo='transferencia' and fondo is null and fondo_origen is not null and fondo_destino is not null and fondo_origen<>fondo_destino)
);

-- CERTIFICADOS (preparado para la siguiente pantalla)
create table if not exists public.certificados_emitidos (id uuid primary key default gen_random_uuid());
alter table public.certificados_emitidos
  add column if not exists numero bigint,
  add column if not exists socio_id uuid references public.socios(id) on delete set null,
  add column if not exists nombre text,
  add column if not exists rut text,
  add column if not exists direccion text,
  add column if not exists tipo text default 'Residencia',
  add column if not exists fecha date default current_date,
  add column if not exists valor numeric(12,0) default 1000,
  add column if not exists movimiento_id uuid references public.movimientos_financieros(id) on delete set null,
  add column if not exists observaciones text,
  add column if not exists creado_por uuid references auth.users(id),
  add column if not exists creado_en timestamptz default now();
create sequence if not exists public.certificados_numero_seq;
select setval('public.certificados_numero_seq', greatest(coalesce((select max(numero) from public.certificados_emitidos),0),1), true);
alter table public.certificados_emitidos alter column numero set default nextval('public.certificados_numero_seq');
update public.certificados_emitidos set numero=nextval('public.certificados_numero_seq') where numero is null;
create unique index if not exists certificados_numero_uidx on public.certificados_emitidos(numero);

-- RLS
alter table public.configuracion_gestion enable row level security;
alter table public.socios enable row level security;
alter table public.grupo_familiar enable row level security;
alter table public.solicitudes_socios enable row level security;
alter table public.reservas_sede enable row level security;
alter table public.movimientos_financieros enable row level security;
alter table public.certificados_emitidos enable row level security;

do $$ declare t text; begin
 foreach t in array array['configuracion_gestion','socios','grupo_familiar','reservas_sede','movimientos_financieros','certificados_emitidos'] loop
  execute format('drop policy if exists %I on public.%I','Admin gestiona '||t,t);
  execute format('create policy %I on public.%I for all to authenticated using (public.es_admin()) with check (public.es_admin())','Admin gestiona '||t,t);
 end loop;
end $$;

drop policy if exists "Publico crea solicitud socio" on public.solicitudes_socios;
create policy "Publico crea solicitud socio" on public.solicitudes_socios for insert to anon,authenticated with check(estado='pendiente');
drop policy if exists "Admin revisa solicitudes socio" on public.solicitudes_socios;
create policy "Admin revisa solicitudes socio" on public.solicitudes_socios for all to authenticated using(public.es_admin()) with check(public.es_admin());

-- RESPALDOS PRIVADOS
insert into storage.buckets(id,name,public) values('respaldos-finanzas','respaldos-finanzas',false) on conflict(id) do update set public=false;
drop policy if exists "Admin gestiona respaldos finanzas" on storage.objects;
create policy "Admin gestiona respaldos finanzas" on storage.objects for all to authenticated
using(bucket_id='respaldos-finanzas' and public.es_admin())
with check(bucket_id='respaldos-finanzas' and public.es_admin());

commit;

notify pgrst, 'reload schema';

-- Comprobacion: debe devolver 7 filas.
select table_name from information_schema.tables
where table_schema='public' and table_name in (
 'configuracion_gestion','socios','grupo_familiar','solicitudes_socios',
 'reservas_sede','movimientos_financieros','certificados_emitidos'
) order by table_name;
