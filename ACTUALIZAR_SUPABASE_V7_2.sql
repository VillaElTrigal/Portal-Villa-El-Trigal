-- PORTAL VILLA EL TRIGAL v7.2 - REPARACION E INTEGRACION DEFINITIVA
-- Ejecutar completo UNA VEZ en Supabase > SQL Editor.
begin;
create extension if not exists pgcrypto;

-- Reparar columnas de finanzas creadas previamente con NOT NULL incompatibles.
alter table public.movimientos_financieros alter column fondo drop not null;
alter table public.movimientos_financieros alter column fondo_origen drop not null;
alter table public.movimientos_financieros alter column fondo_destino drop not null;
alter table public.movimientos_financieros alter column fecha set default current_date;
alter table public.movimientos_financieros alter column creado_en set default now();

-- Normalizar valores anteriores.
update public.movimientos_financieros set tipo=lower(btrim(tipo)) where tipo is not null;
update public.movimientos_financieros set fondo=lower(btrim(fondo)) where fondo is not null;
update public.movimientos_financieros set fondo_origen=lower(btrim(fondo_origen)) where fondo_origen is not null;
update public.movimientos_financieros set fondo_destino=lower(btrim(fondo_destino)) where fondo_destino is not null;
update public.movimientos_financieros set fondo=null where tipo='transferencia';
update public.movimientos_financieros set fondo_origen=null,fondo_destino=null where tipo in ('ingreso','gasto');

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

-- Asegurar borrado de grupo familiar al eliminar socio.
do $$
declare c text;
begin
 select conname into c from pg_constraint where conrelid='public.grupo_familiar'::regclass and contype='f' and pg_get_constraintdef(oid) like '%socio_id%';
 if c is not null then execute format('alter table public.grupo_familiar drop constraint %I',c); end if;
end $$;
alter table public.grupo_familiar add constraint grupo_familiar_socio_id_fkey foreign key(socio_id) references public.socios(id) on delete cascade;

-- Índices para búsquedas y reportes.
create index if not exists movimientos_fecha_idx on public.movimientos_financieros(fecha);
create index if not exists movimientos_tipo_fondo_idx on public.movimientos_financieros(tipo,fondo);
create index if not exists reservas_fecha_estado_idx on public.reservas_sede(fecha_evento,estado);
create index if not exists solicitudes_estado_idx on public.solicitudes_socios(estado);

-- Vista pública: nunca expone nombres, RUT, teléfono, valor ni pagos.
drop view if exists public.reservas_publicas;
create view public.reservas_publicas as
select fecha_evento,tipo,
 case when tipo='actividad' then coalesce(descripcion,'Actividad comunitaria')
      when tipo='zumba' then 'Clase de Zumba'
      when tipo='bloqueo' then 'Fecha no disponible'
      else 'Reservado' end as descripcion_publica
from public.reservas_sede
where estado not in ('cancelado','archivado');
grant select on public.reservas_publicas to anon,authenticated;

-- Confirmar RLS administrativa.
alter table public.movimientos_financieros enable row level security;
drop policy if exists "Admin gestiona movimientos_financieros" on public.movimientos_financieros;
create policy "Admin gestiona movimientos_financieros" on public.movimientos_financieros for all to authenticated using(public.es_admin()) with check(public.es_admin());

-- Solicitudes públicas: solo insertar, nunca leer.
drop policy if exists "Publico crea solicitud socio" on public.solicitudes_socios;
create policy "Publico crea solicitud socio" on public.solicitudes_socios for insert to anon,authenticated with check(estado='pendiente');

commit;
notify pgrst,'reload schema';

-- Diagnóstico final.
select 'movimientos_financieros' as componente,count(*) as registros from public.movimientos_financieros
union all select 'reservas_sede',count(*) from public.reservas_sede
union all select 'socios',count(*) from public.socios
union all select 'grupo_familiar',count(*) from public.grupo_familiar;
