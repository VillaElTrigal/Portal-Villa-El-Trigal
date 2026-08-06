-- SIGVE v5.5.7
-- Zumba: nombres de meses siempre en español y corrección de registros existentes.
-- Ejecutar completo en Supabase > SQL Editor.

begin;

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
    raise exception 'Debes indicar el período trabajado y la fecha real del pago';
  end if;
  if coalesce(p_cantidad_clases,0) <= 0 then
    raise exception 'No hay clases activas para registrar en el período seleccionado';
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
    raise exception 'El período seleccionado ya está cerrado';
  end if;
  if exists(select 1 from public.zumba_pagos where periodo=v_periodo) then
    raise exception 'Ya existe un aporte registrado para este período';
  end if;

  v_nombre_mes :=
    (array['Enero','Febrero','Marzo','Abril','Mayo','Junio',
           'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'])
      [extract(month from v_periodo)::integer]
    || ' ' || extract(year from v_periodo)::integer;

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

-- Corrige los aportes ya registrados que muestran el mes en inglés.
update public.zumba_pagos
set nombre_referencia =
  'Aporte Taller de Zumba - ' ||
  (array['Enero','Febrero','Marzo','Abril','Mayo','Junio',
         'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'])
    [extract(month from periodo)::integer]
  || ' ' || extract(year from periodo)::integer
where periodo is not null
  and nombre_referencia like 'Aporte Taller de Zumba%';

revoke all on function public.registrar_aporte_zumba_mensual(date,date,integer,numeric,text,text) from public;
grant execute on function public.registrar_aporte_zumba_mensual(date,date,integer,numeric,text,text) to authenticated;

commit;

notify pgrst, 'reload schema';
