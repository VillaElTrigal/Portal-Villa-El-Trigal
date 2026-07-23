-- SIGVE Alpha 11: niños y niñas + calendarios mensuales + reservas administrativas + campanilla

begin;

-- Permitir reservas administrativas sin fines de lucro.
alter table public.reservas_sede drop constraint if exists reservas_sede_tipo_check;
alter table public.reservas_sede add constraint reservas_sede_tipo_check
  check (tipo in ('arriendo','actividad','administrativa','bloqueo','zumba'));

-- Las reservas administrativas no deben generar montos.
update public.reservas_sede set valor_total = 0 where tipo = 'administrativa';

-- Ejecuta también aquí la estructura completa del módulo de niños y niñas.
-- Este bloque es idempotente y puede volver a ejecutarse sin borrar registros.

commit;

-- IMPORTANTE: a continuación ejecuta el archivo ACTUALIZAR_SUPABASE_ALPHA10_NINOS.sql
-- incluido en esta misma carpeta, si todavía no lo ejecutaste.
