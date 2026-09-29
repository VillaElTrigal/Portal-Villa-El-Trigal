-- SIGVE - UTM vigente y limite estatutario de caja (2 UTM)
-- Ejecutar una sola vez en Supabase > SQL Editor.

alter table public.configuracion_gestion
  add column if not exists valor_utm numeric(12,0);

comment on column public.configuracion_gestion.valor_utm is
  'Valor mensual vigente de la UTM en pesos. Se usa para controlar el limite de caja de 2 UTM.';
