-- SIGVE v5.5.4
-- Separa de forma definitiva el mes trabajado de Zumba y la fecha real de pago.
-- Es seguro ejecutarlo aunque ya se haya ejecutado una versión anterior.

begin;

alter table if exists public.zumba_pagos
  add column if not exists periodo date;

update public.zumba_pagos
set periodo = date_trunc('month', fecha)::date
where periodo is null;

alter table public.zumba_pagos
  alter column periodo set default date_trunc('month', current_date)::date,
  alter column periodo set not null;

create index if not exists zumba_pagos_periodo_idx
  on public.zumba_pagos(periodo desc);

comment on column public.zumba_pagos.periodo is
  'Primer día del mes al que corresponde el aporte; puede ser distinto de la fecha real de pago.';

comment on column public.zumba_pagos.fecha is
  'Fecha real en que se recibió o registró el pago.';

commit;

notify pgrst, 'reload schema';
