-- SIGVE v5.5.0 ESTABLE
-- Zumba: mes trabajado independiente de la fecha real del aporte.
-- Ejecutar completo en Supabase > SQL Editor.

begin;

alter table if exists public.zumba_pagos
  add column if not exists periodo date;

update public.zumba_pagos
set periodo = date_trunc('month', fecha)::date
where periodo is null;

alter table public.zumba_pagos
  alter column periodo set not null;

create index if not exists zumba_pagos_periodo_idx
  on public.zumba_pagos(periodo desc);

comment on column public.zumba_pagos.periodo is
  'Primer día del mes trabajado. Puede ser distinto de la fecha real del pago.';

comment on column public.zumba_pagos.fecha is
  'Fecha real en que se recibió el aporte.';

create or replace function public.registrar_aporte_zumba_mensual(
  p_periodo date,
  p_fecha_pago date,
  p_cantidad_clases integer,
  p_valor_clase numeric,
  p_medio text,
  p_observaciones text default null
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid;
  v_periodo date;
  v_monto numeric(12,0);
  v_nombre_mes text;
begin
  if auth.uid() is null or not public.es_admin() then
    raise exception 'Acceso no autorizado';
  end if;

  if p_periodo is null or p_fecha_pago is null then
    raise exception 'Debes indicar el mes trabajado y la fecha real del aporte';
  end if;
  if coalesce(p_cantidad_clases,0) <= 0 then
    raise exception 'No hay clases activas para registrar en el mes seleccionado';
  end if;
  if coalesce(p_valor_clase,0) <= 0 then
    raise exception 'El valor por clase debe ser mayor que cero';
  end if;
  if p_medio not in ('efectivo','transferencia') then
    raise exception 'Medio de pago inválido';
  end if;

  v_periodo := date_trunc('month',p_periodo)::date;
  v_monto := round(p_cantidad_clases * p_valor_clase);

  if exists(select 1 from public.zumba_cierres where mes=v_periodo) then
    raise exception 'El mes seleccionado ya está cerrado';
  end if;
  if exists(select 1 from public.zumba_pagos where periodo=v_periodo) then
    raise exception 'Ya existe un aporte registrado para este mes';
  end if;

  v_nombre_mes := trim(to_char(v_periodo,'TMMonth YYYY'));

  insert into public.zumba_pagos(
    periodo, fecha, nombre_referencia, monto, medio, observaciones, creado_por
  ) values (
    v_periodo,
    p_fecha_pago,
    'Aporte Taller de Zumba - ' || v_nombre_mes,
    v_monto,
    p_medio,
    coalesce(nullif(btrim(p_observaciones),''),
      p_cantidad_clases || ' clases a $' || trim(to_char(p_valor_clase,'FM999G999G990')) || ' cada una'),
    auth.uid()
  ) returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.registrar_aporte_zumba_mensual(date,date,integer,numeric,text,text) from public;
grant execute on function public.registrar_aporte_zumba_mensual(date,date,integer,numeric,text,text) to authenticated;

commit;

notify pgrst, 'reload schema';
