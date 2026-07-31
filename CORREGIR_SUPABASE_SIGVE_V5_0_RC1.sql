-- SIGVE v5.0 RC1 · Corrección estable del Programa de Beneficios
-- Ejecutar completo en Supabase > SQL Editor.
-- Puede ejecutarse aunque ya se hayan instalado los SQL v5.0.0 y v5.0.1.

create or replace function public.evaluar_beneficios_socio(
  p_socio_id uuid,
  p_fecha date,
  p_valor_original numeric
)
returns table(
  beneficio_id uuid,
  nombre text,
  tipo text,
  cumple boolean,
  motivo text,
  detalle text,
  valor_final numeric
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_beneficio record;
  v_pagadas integer;
  v_deuda integer;
  v_usados integer;
  v_anio integer := extract(year from p_fecha)::integer;
begin
  select count(*)::integer
    into v_pagadas
  from public.cuotas_socios cs
  where cs.socio_id = p_socio_id
    and cs.estado = 'pagado'
    and extract(year from cs.periodo)::integer = v_anio;

  select count(*)::integer
    into v_deuda
  from public.cuotas_socios cs
  where cs.socio_id = p_socio_id
    and cs.estado = 'pendiente'
    and cs.periodo < date_trunc('month', p_fecha)::date;

  for v_beneficio in
    select bc.*
    from public.beneficios_config bc
    where bc.activo = true
      and (bc.vigencia_desde is null or bc.vigencia_desde <= p_fecha)
      and (bc.vigencia_hasta is null or bc.vigencia_hasta >= p_fecha)
    order by bc.prioridad asc, bc.nombre asc
  loop
    select count(*)::integer
      into v_usados
    from public.beneficios_usos bu
    where bu.socio_id = p_socio_id
      and bu.beneficio_id = v_beneficio.id
      and bu.anio = v_anio;

    beneficio_id := v_beneficio.id;
    nombre := v_beneficio.nombre;
    tipo := v_beneficio.tipo;
    cumple := v_pagadas >= v_beneficio.cuotas_minimas
      and (not v_beneficio.exigir_sin_deuda or v_deuda = 0)
      and v_usados < v_beneficio.usos_maximos_anuales;

    motivo := case
      when v_pagadas < v_beneficio.cuotas_minimas
        then 'Tiene ' || v_pagadas || ' de ' || v_beneficio.cuotas_minimas || ' cuotas requeridas.'
      when v_beneficio.exigir_sin_deuda and v_deuda > 0
        then 'Mantiene ' || v_deuda || ' cuota(s) vencida(s).'
      when v_usados >= v_beneficio.usos_maximos_anuales
        then 'Ya utilizó este beneficio durante el año.'
      else 'Cumple los requisitos.'
    end;

    detalle := v_pagadas || ' cuotas pagadas en ' || v_anio ||
      case
        when v_beneficio.tipo = 'gratis' then ' · arriendo gratuito disponible'
        when v_beneficio.tipo = 'porcentaje' then ' · ' || v_beneficio.valor || '% de descuento'
        else ' · descuento de $' || v_beneficio.valor
      end;

    valor_final := case
      when not cumple then p_valor_original
      when v_beneficio.tipo = 'gratis' then 0
      when v_beneficio.tipo = 'porcentaje'
        then greatest(0, round(p_valor_original * (1 - v_beneficio.valor / 100)))
      else greatest(0, p_valor_original - v_beneficio.valor)
    end;

    return next;
  end loop;
end;
$$;

grant execute on function public.evaluar_beneficios_socio(uuid,date,numeric) to authenticated;

create or replace function public.portal_socio_mis_beneficios(p_token text)
returns table(
  beneficio_id uuid,
  nombre text,
  tipo text,
  valor numeric,
  cuotas_minimas integer,
  cumple boolean,
  motivo text,
  detalle text,
  valor_final numeric
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_socio_id uuid;
  v_valor_arriendo numeric := 0;
begin
  v_socio_id := public.portal_socio_validar_sesion(p_token);
  if v_socio_id is null then
    raise exception 'Sesión inválida o expirada';
  end if;

  select coalesce(cg.valor_arriendo, 0)
    into v_valor_arriendo
  from public.configuracion_gestion cg
  where cg.id = 1;

  return query
  select
    eb.beneficio_id,
    eb.nombre,
    eb.tipo,
    bc.valor,
    bc.cuotas_minimas,
    eb.cumple,
    eb.motivo,
    eb.detalle,
    eb.valor_final
  from public.evaluar_beneficios_socio(v_socio_id, current_date, v_valor_arriendo) eb
  join public.beneficios_config bc on bc.id = eb.beneficio_id
  order by bc.prioridad asc, bc.nombre asc;
end;
$$;

grant execute on function public.portal_socio_mis_beneficios(text) to anon, authenticated;
