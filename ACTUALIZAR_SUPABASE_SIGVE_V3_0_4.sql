-- SIGVE v3.0.4
-- Regularización de reservas migradas sin generar movimientos financieros.

alter table public.reservas_sede
  add column if not exists migracion_regularizada boolean not null default false,
  add column if not exists migracion_regularizada_monto numeric(12,2) not null default 0,
  add column if not exists migracion_regularizada_fecha timestamptz,
  add column if not exists migracion_regularizada_por text,
  add column if not exists migracion_regularizada_observacion text;

comment on column public.reservas_sede.migracion_regularizada is
  'Indica que el saldo histórico fue cerrado administrativamente por migración, sin ingreso en caja o banco.';
comment on column public.reservas_sede.migracion_regularizada_monto is
  'Monto histórico regularizado sin crear movimiento financiero.';

-- Verificación opcional
select id, fecha_evento, nombre_arrendatario, valor_total,
       migracion_regularizada, migracion_regularizada_monto,
       migracion_regularizada_fecha, migracion_regularizada_por
from public.reservas_sede
where descripcion ilike '%Migración desde Excel%'
order by fecha_evento;
