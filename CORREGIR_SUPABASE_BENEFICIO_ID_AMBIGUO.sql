-- SIGVE · Corrección beneficio_id ambiguo
-- Ejecutar completo en Supabase > SQL Editor.
-- No crea tablas nuevas. Mantiene los permisos actuales y vuelve a otorgar EXECUTE.

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
  v_desde date:=(date_trunc('month',p_fecha)-interval '11 months')::date;
  v_hasta date:=(date_trunc('month',p_fecha)+interval '1 month - 1 day')::date;
begin
  if auth.uid() is null or not public.es_admin() then
    raise exception 'Acceso no autorizado';
  end if;

  select s.estado into v_estado
  from public.socios s
  where s.id=p_socio_id;

  if not found then raise exception 'Socio no encontrado.'; end if;

  select count(*) into pagadas
  from public.cuotas_socios cs
  where cs.socio_id=p_socio_id
    and cs.estado='pagado'
    and cs.periodo>=v_desde
    and cs.periodo<=v_hasta;

  select count(*) into deuda
  from public.cuotas_socios cs
  where cs.socio_id=p_socio_id
    and cs.estado='pendiente'
    and cs.periodo<date_trunc('month',p_fecha)::date;

  for b in
    select bc.*
    from public.beneficios_config bc
    where bc.activo
      and bc.categoria='operativo'
      and bc.aplica_a='arriendo_sede'
      and (bc.vigencia_desde is null or bc.vigencia_desde<=p_fecha)
      and (bc.vigencia_hasta is null or bc.vigencia_hasta>=p_fecha)
    order by bc.prioridad asc,bc.nombre asc
  loop
    select count(*) into usados
    from public.beneficios_usos bu
    where bu.socio_id=p_socio_id
      and bu.beneficio_id=b.id
      and bu.anio=a
      and coalesce(bu.estado,'aplicado')<>'revertido';

    beneficio_id:=b.id;
    nombre:=b.nombre;
    tipo:=b.tipo;
    cumple:=(deuda<3)
      and (not b.exigir_socio_activo or v_estado='activo')
      and pagadas>=b.cuotas_minimas
      and (not b.exigir_sin_deuda or deuda=0)
      and usados<b.usos_maximos_anuales;

    motivo:=case
      when deuda>=3 then 'Beneficios suspendidos por morosidad: mantiene '||deuda||' cuotas vencidas.'
      when b.exigir_socio_activo and coalesce(v_estado,'')<>'activo' then 'El socio no se encuentra vigente.'
      when pagadas<b.cuotas_minimas then 'Tiene '||pagadas||' de '||b.cuotas_minimas||' cuotas requeridas dentro de los últimos 12 meses.'
      when b.exigir_sin_deuda and deuda>0 then 'Mantiene '||deuda||' cuota(s) vencida(s).'
      when usados>=b.usos_maximos_anuales then 'Ya alcanzó el máximo de '||b.usos_maximos_anuales||' uso(s) para '||a||'.'
      else 'Cumple los requisitos.'
    end;

    detalle:=pagadas||' cuota(s) pagada(s) en los últimos 12 meses'
      ||' · '||deuda||' cuota(s) vencida(s)'
      ||case when b.tipo='gratis' then ' · gratuidad'
              when b.tipo='porcentaje' then ' · '||b.valor||'% de descuento'
              else ' · descuento de $'||b.valor end
      ||case when b.usos_maximos_anuales<999 then ' · '||usados||' de '||b.usos_maximos_anuales||' uso(s) utilizados en '||a else '' end;

    valor_final:=case
      when not cumple then p_valor_original
      when b.tipo='gratis' then 0
      when b.tipo='porcentaje' then greatest(0,round(p_valor_original*(1-b.valor/100)))
      else greatest(0,p_valor_original-b.valor)
    end;
    return next;
  end loop;
end $$;

revoke all on function public.evaluar_beneficios_socio(uuid,date,numeric) from public;
revoke all on function public.evaluar_beneficios_socio(uuid,date,numeric) from anon;
grant execute on function public.evaluar_beneficios_socio(uuid,date,numeric) to authenticated;

commit;
notify pgrst,'reload schema';
