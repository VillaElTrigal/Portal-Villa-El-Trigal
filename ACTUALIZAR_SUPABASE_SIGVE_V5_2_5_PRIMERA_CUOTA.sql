-- ============================================================
-- SIGVE v5.2.5 · Corrección primera cuota de socios
-- Regla:
--   Aprobación día 1 al 10  -> cobra el mismo mes.
--   Aprobación día 11 o más -> cobra desde el mes siguiente.
--
-- Ejecutar una vez en Supabase > SQL Editor.
-- No elimina pagos ni duplica cuotas.
-- ============================================================

begin;

-- Función central para calcular el primer período de cobro.
create or replace function public.primer_periodo_cobro(p_fecha_ingreso date)
returns date
language sql stable set search_path=public
as $$
  select case
    when p_fecha_ingreso is null then null
    when extract(day from p_fecha_ingreso)::integer <=
         coalesce((select dia_limite_cobro_mes from public.configuracion_gestion where id=1),10)
      then date_trunc('month',p_fecha_ingreso)::date
    else (date_trunc('month',p_fecha_ingreso) + interval '1 month')::date
  end;
$$;

-- Genera las cuotas faltantes de un socio desde su primer período de cobro
-- hasta el mes indicado, sin tocar cuotas pagadas ni crear duplicados.
create or replace function public.asegurar_cuotas_socio(
  p_socio_id uuid,
  p_hasta date default current_date
)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_socio public.socios%rowtype;
  v_inicio date;
  v_fin date := date_trunc('month',coalesce(p_hasta,current_date))::date;
  v_valor numeric(12,0);
  v_count integer := 0;
begin
  select * into v_socio
  from public.socios
  where id=p_socio_id;

  if not found or v_socio.estado <> 'activo' or v_socio.fecha_ingreso is null then
    return 0;
  end if;

  v_inicio := public.primer_periodo_cobro(v_socio.fecha_ingreso);
  if v_inicio is null or v_inicio > v_fin then
    return 0;
  end if;

  select valor_cuota into v_valor
  from public.configuracion_gestion
  where id=1;

  insert into public.cuotas_socios(
    socio_id,periodo,estado,monto,creado_por,actualizado_por
  )
  select
    v_socio.id,
    gs::date,
    'pendiente',
    v_valor,
    auth.uid(),
    auth.uid()
  from generate_series(v_inicio,v_fin,interval '1 month') gs
  on conflict(socio_id,periodo) do update
    set estado = case
          when public.cuotas_socios.estado='exento_incorporacion'
            then 'pendiente'
          else public.cuotas_socios.estado
        end,
        monto = case
          when public.cuotas_socios.estado='exento_incorporacion'
            then excluded.monto
          else public.cuotas_socios.monto
        end,
        actualizado_en = case
          when public.cuotas_socios.estado='exento_incorporacion'
            then now()
          else public.cuotas_socios.actualizado_en
        end,
        actualizado_por = case
          when public.cuotas_socios.estado='exento_incorporacion'
            then auth.uid()
          else public.cuotas_socios.actualizado_por
        end;

  get diagnostics v_count=row_count;
  return v_count;
end;
$$;

-- Trigger: al aprobar/activar un socio, crea de inmediato cualquier cuota
-- que ya corresponda hasta el mes actual. Esto evita que el socio quede fuera
-- si el mes fue preparado antes de su aprobación.
create or replace function public.trg_asegurar_cuotas_socio()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.estado='activo' and new.fecha_ingreso is not null then
    perform public.asegurar_cuotas_socio(new.id,current_date);
  end if;
  return new;
end;
$$;

drop trigger if exists socios_asegurar_cuotas_trg on public.socios;
create trigger socios_asegurar_cuotas_trg
after insert or update of estado,fecha_ingreso on public.socios
for each row execute function public.trg_asegurar_cuotas_socio();

-- Corrige también la generación manual mensual.
create or replace function public.generar_cuotas_mes(p_periodo date)
returns integer
language plpgsql security definer set search_path=public
as $$
declare
  v_periodo date := date_trunc('month',p_periodo)::date;
  v_valor numeric(12,0);
  v_count integer;
begin
  if not public.es_admin() then raise exception 'Acceso denegado'; end if;

  select valor_cuota into v_valor
  from public.configuracion_gestion
  where id=1;

  insert into public.cuotas_socios(socio_id,periodo,estado,monto,creado_por)
  select s.id,v_periodo,'pendiente',v_valor,auth.uid()
  from public.socios s
  where s.estado='activo'
    and public.primer_periodo_cobro(s.fecha_ingreso) <= v_periodo
  on conflict(socio_id,periodo) do nothing;

  get diagnostics v_count=row_count;
  return v_count;
end;
$$;

-- Reparación segura de socios activos existentes hasta el mes actual.
-- Para Claudio aprobado el 27/07/2026, crea agosto 2026 si faltaba.
do $$
declare
  r record;
begin
  for r in select id from public.socios where estado='activo' and fecha_ingreso is not null loop
    perform public.asegurar_cuotas_socio(r.id,current_date);
  end loop;
end;
$$;

-- La función auxiliar solo se usa internamente por el trigger.
revoke all on function public.asegurar_cuotas_socio(uuid,date) from public,anon,authenticated;
grant execute on function public.primer_periodo_cobro(date) to authenticated;
grant execute on function public.generar_cuotas_mes(date) to authenticated;

commit;
