-- SIGVE v5.5.2
-- Separa el mes al que corresponde el aporte de Zumba de la fecha real de pago.
-- Ejecutar completo en Supabase > SQL Editor.

begin;

alter table if exists public.zumba_pagos
  add column if not exists periodo date;

-- Los registros anteriores quedan asociados al mes de su fecha de pago.
update public.zumba_pagos
set periodo = date_trunc('month', fecha)::date
where periodo is null;

alter table public.zumba_pagos
  alter column periodo set default date_trunc('month', current_date)::date,
  alter column periodo set not null;

create index if not exists zumba_pagos_periodo_idx
  on public.zumba_pagos(periodo desc);

commit;
