-- SIGVE · Beneficios por año calendario de la reserva
-- 02-10-2026
-- Cada cuota cuenta para el año al que corresponde su PERIODO.
-- Ej.: una cuota de enero 2027 pagada anticipadamente en 2026 cuenta para beneficios 2027.
-- Mantiene beneficios encadenados, límites de uso anuales y reglas de morosidad.

begin;

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
  b record;
  pagadas integer;
  deuda integer;
  usados integer;
  a integer:=extract(year from p_fecha);
  v_estado text;
  v_prev_total integer;
  v_prev_usados integer;
  v_prev_nombres text;
begin
  if auth.uid() is null or not public.es_admin() then
    raise exception 'Acceso no autorizado';
  end if;

  select s.estado into v_estado
  from public.socios s
  where s.id=p_socio_id;

  if not found then
    raise exception 'Socio no encontrado.';
  end if;

  -- IMPORTANTE: cuenta por el AÑO DEL PERIODO de la cuota, no por fecha de pago.
  -- Las cuotas adelantadas sí cuentan, pero únicamente para el año al que pertenecen.
  select count(*) into pagadas
  from public.cuotas_socios cs
  where cs.socio_id=p_socio_id
    and cs.estado='pagado'
    and extract(year from cs.periodo)=a;

  select count(*) into deuda
  from public.cuotas_socios cs
  where cs.socio_id=p_socio_id
    and cs.estado='pendiente'
    and cs.periodo<date_trunc('month',p_fecha)::date;

  for b in
    select *
    from public.beneficios_config bc
    where bc.activo
      and bc.categoria='operativo'
      and bc.aplica_a='arriendo_sede'
      and (bc.vigencia_desde is null or bc.vigencia_desde<=p_fecha)
      and (bc.vigencia_hasta is null or bc.vigencia_hasta>=p_fecha)
    order by bc.prioridad,bc.nombre
  loop
    select count(*) into usados
    from public.beneficios_usos bu
    where bu.socio_id=p_socio_id
      and bu.beneficio_id=b.id
      and bu.anio=a
      and coalesce(bu.estado,'aplicado')<>'revertido';

    select count(*), string_agg(bc.nombre,' + ' order by bc.nombre)
    into v_prev_total,v_prev_nombres
    from public.beneficios_requisitos_previos rp
    join public.beneficios_config bc on bc.id=rp.beneficio_requerido_id
    where rp.beneficio_id=b.id;

    select count(distinct rp.beneficio_requerido_id)
    into v_prev_usados
    from public.beneficios_requisitos_previos rp
    where rp.beneficio_id=b.id
      and exists(
        select 1
        from public.beneficios_usos bu
        where bu.socio_id=p_socio_id
          and bu.beneficio_id=rp.beneficio_requerido_id
          and bu.anio=a
          and coalesce(bu.estado,'aplicado')<>'revertido'
      );

    beneficio_id:=b.id;
    nombre:=b.nombre;
    tipo:=b.tipo;

    cumple:=(deuda<3)
      and (not b.exigir_socio_activo or v_estado='activo')
      and pagadas>=b.cuotas_minimas
      and (not b.exigir_sin_deuda or deuda=0)
      and usados<b.usos_maximos_anuales
      and v_prev_usados=v_prev_total;

    motivo:=case
      when deuda>=3 then
        'Beneficios suspendidos por morosidad: mantiene '||deuda||' cuotas vencidas.'
      when b.exigir_socio_activo and coalesce(v_estado,'')<>'activo' then
        'El socio no se encuentra vigente.'
      when pagadas<b.cuotas_minimas then
        'Tiene '||pagadas||' de '||b.cuotas_minimas||' cuotas '||a||' requeridas.'
      when b.exigir_sin_deuda and deuda>0 then
        'Mantiene '||deuda||' cuota(s) vencida(s).'
      when v_prev_usados<v_prev_total then
        'Disponible después de utilizar: '||coalesce(v_prev_nombres,'los beneficios requeridos')||'.'
      when usados>=b.usos_maximos_anuales then
        'Ya alcanzó el máximo de '||b.usos_maximos_anuales||' uso(s) para '||a||'.'
      else
        'Cumple los requisitos.'
    end;

    detalle:='Cuotas '||a||': '||pagadas||' de 12 pagada(s)'
      ||' · '||deuda||' cuota(s) vencida(s)'
      ||case when v_prev_total>0
          then ' · beneficios previos: '||v_prev_usados||' de '||v_prev_total
          else ''
        end
      ||case
          when b.tipo='gratis' then ' · gratuidad'
          when b.tipo='porcentaje' then ' · '||b.valor||'% de descuento'
          else ' · descuento de $'||b.valor
        end
      ||case when b.usos_maximos_anuales<999
          then ' · '||usados||' de '||b.usos_maximos_anuales||' uso(s) utilizados en '||a
          else ''
        end;

    valor_final:=case
      when not cumple then p_valor_original
      when b.tipo='gratis' then 0
      when b.tipo='porcentaje' then greatest(0,round(p_valor_original*(1-b.valor/100)))
      else greatest(0,p_valor_original-b.valor)
    end;

    return next;
  end loop;
end
$$;

revoke all on function public.evaluar_beneficios_socio(uuid,date,numeric) from public;
revoke all on function public.evaluar_beneficios_socio(uuid,date,numeric) from anon;
grant execute on function public.evaluar_beneficios_socio(uuid,date,numeric) to authenticated;


-- Portal Socio: mismo criterio por año calendario.
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
  v_valor_arriendo numeric:=0;
  v_estado text;
  v_pagadas integer;
  v_deuda integer;
  v_usados integer;
  v_anio integer:=extract(year from current_date)::integer;
  b record;
  v_prev_total integer;
  v_prev_usados integer;
  v_prev_nombres text;
begin
  v_socio_id:=public.portal_socio_validar_sesion(p_token);
  if v_socio_id is null then
    raise exception 'Sesión inválida o expirada';
  end if;

  select s.estado into v_estado
  from public.socios s
  where s.id=v_socio_id;

  select coalesce(cg.valor_arriendo,0) into v_valor_arriendo
  from public.configuracion_gestion cg
  where cg.id=1;

  -- Portal muestra el progreso del año calendario actual.
  select count(*) into v_pagadas
  from public.cuotas_socios cs
  where cs.socio_id=v_socio_id
    and cs.estado='pagado'
    and extract(year from cs.periodo)=v_anio;

  select count(*) into v_deuda
  from public.cuotas_socios cs
  where cs.socio_id=v_socio_id
    and cs.estado='pendiente'
    and cs.periodo<date_trunc('month',current_date)::date;

  for b in
    select *
    from public.beneficios_config bc
    where bc.activo
      and bc.categoria='operativo'
      and bc.aplica_a='arriendo_sede'
      and (bc.vigencia_desde is null or bc.vigencia_desde<=current_date)
      and (bc.vigencia_hasta is null or bc.vigencia_hasta>=current_date)
    order by bc.prioridad,bc.nombre
  loop
    select count(*) into v_usados
    from public.beneficios_usos bu
    where bu.socio_id=v_socio_id
      and bu.beneficio_id=b.id
      and bu.anio=v_anio
      and coalesce(bu.estado,'aplicado')<>'revertido';

    select count(*),string_agg(bc.nombre,' + ' order by bc.nombre)
    into v_prev_total,v_prev_nombres
    from public.beneficios_requisitos_previos rp
    join public.beneficios_config bc on bc.id=rp.beneficio_requerido_id
    where rp.beneficio_id=b.id;

    select count(distinct rp.beneficio_requerido_id)
    into v_prev_usados
    from public.beneficios_requisitos_previos rp
    where rp.beneficio_id=b.id
      and exists(
        select 1
        from public.beneficios_usos bu
        where bu.socio_id=v_socio_id
          and bu.beneficio_id=rp.beneficio_requerido_id
          and bu.anio=v_anio
          and coalesce(bu.estado,'aplicado')<>'revertido'
      );

    beneficio_id:=b.id;
    nombre:=b.nombre;
    tipo:=b.tipo;
    valor:=b.valor;
    cuotas_minimas:=b.cuotas_minimas;

    cumple:=(v_deuda<3)
      and (not b.exigir_socio_activo or v_estado='activo')
      and v_pagadas>=b.cuotas_minimas
      and (not b.exigir_sin_deuda or v_deuda=0)
      and v_usados<b.usos_maximos_anuales
      and v_prev_usados=v_prev_total;

    motivo:=case
      when v_deuda>=3 then
        'Beneficios suspendidos por morosidad: mantiene '||v_deuda||' cuotas vencidas.'
      when b.exigir_socio_activo and coalesce(v_estado,'')<>'activo' then
        'El socio no se encuentra vigente.'
      when v_pagadas<b.cuotas_minimas then
        'Tiene '||v_pagadas||' de '||b.cuotas_minimas||' cuotas '||v_anio||' requeridas.'
      when b.exigir_sin_deuda and v_deuda>0 then
        'Mantiene '||v_deuda||' cuota(s) vencida(s).'
      when v_prev_usados<v_prev_total then
        'Disponible después de utilizar: '||coalesce(v_prev_nombres,'los beneficios requeridos')||'.'
      when v_usados>=b.usos_maximos_anuales then
        'Ya alcanzó el máximo de '||b.usos_maximos_anuales||' uso(s) para '||v_anio||'.'
      else
        'Cumple los requisitos.'
    end;

    detalle:='Cuotas '||v_anio||': '||v_pagadas||' de 12 pagada(s)'
      ||' · '||v_deuda||' cuota(s) vencida(s)'
      ||case when v_prev_total>0
          then ' · beneficios previos: '||v_prev_usados||' de '||v_prev_total
          else ''
        end
      ||case
          when b.tipo='gratis' then ' · gratuidad'
          when b.tipo='porcentaje' then ' · '||b.valor||'% de descuento'
          else ' · descuento de $'||b.valor
        end
      ||case when b.usos_maximos_anuales<999
          then ' · '||v_usados||' de '||b.usos_maximos_anuales||' uso(s) utilizados en '||v_anio
          else ''
        end;

    valor_final:=case
      when not cumple then v_valor_arriendo
      when b.tipo='gratis' then 0
      when b.tipo='porcentaje' then greatest(0,round(v_valor_arriendo*(1-b.valor/100)))
      else greatest(0,v_valor_arriendo-b.valor)
    end;

    return next;
  end loop;
end
$$;

revoke all on function public.portal_socio_mis_beneficios(text) from public;
grant execute on function public.portal_socio_mis_beneficios(text) to anon,authenticated;

commit;
notify pgrst,'reload schema';
