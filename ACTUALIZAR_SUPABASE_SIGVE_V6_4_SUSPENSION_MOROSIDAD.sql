-- SIGVE v6.4 · Suspensión automática de beneficios por morosidad
-- Regla: 3 o más cuotas VENCIDAS suspenden beneficios.
-- El mes en curso no se considera vencido.
-- NO cambia el estado institucional del socio.
-- Ejecutar completo en Supabase > SQL Editor.

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

  select estado into v_estado
  from public.socios
  where id=p_socio_id;

  if not found then
    raise exception 'Socio no encontrado.';
  end if;

  select count(*) into pagadas
  from public.cuotas_socios
  where socio_id=p_socio_id
    and estado='pagado'
    and periodo>=v_desde
    and periodo<=v_hasta;

  select count(*) into deuda
  from public.cuotas_socios
  where socio_id=p_socio_id
    and estado='pendiente'
    and periodo<date_trunc('month',p_fecha)::date;

  for b in
    select *
    from public.beneficios_config
    where activo
      and categoria='operativo'
      and aplica_a='arriendo_sede'
      and (vigencia_desde is null or vigencia_desde<=p_fecha)
      and (vigencia_hasta is null or vigencia_hasta>=p_fecha)
    order by prioridad asc,nombre asc
  loop
    select count(*) into usados
    from public.beneficios_usos
    where socio_id=p_socio_id
      and beneficio_id=b.id
      and anio=a
      and coalesce(estado,'aplicado')<>'revertido';

    beneficio_id:=b.id;
    nombre:=b.nombre;
    tipo:=b.tipo;

    -- Regla transversal SIGVE: con 3+ cuotas vencidas no se otorgan beneficios,
    -- independientemente de la configuración particular del beneficio.
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
notify pgrst, 'reload schema';

-- Verificación informativa de la regla para socios con 3+ cuotas vencidas al mes actual.
select
  s.numero_socio,
  s.nombre_completo,
  count(cs.id) as cuotas_vencidas,
  case when count(cs.id)>=3 then 'SUSPENDIDO BENEFICIOS' else 'HABILITADO' end as situacion_beneficios
from public.socios s
left join public.cuotas_socios cs
  on cs.socio_id=s.id
 and cs.estado='pendiente'
 and cs.periodo<date_trunc('month',current_date)::date
where s.estado='activo'
group by s.id,s.numero_socio,s.nombre_completo
having count(cs.id)>=3
order by count(cs.id) desc,s.numero_socio;

-- ============================================================
-- Portal Socio: aplica la misma regla sin depender del RPC administrativo.
-- La sesión del socio se valida mediante su token.
-- ============================================================
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
  v_desde date:=(date_trunc('month',current_date)-interval '11 months')::date;
  v_hasta date:=(date_trunc('month',current_date)+interval '1 month - 1 day')::date;
  b record;
begin
  v_socio_id:=public.portal_socio_validar_sesion(p_token);
  if v_socio_id is null then raise exception 'Sesión inválida o expirada'; end if;

  select s.estado into v_estado from public.socios s where s.id=v_socio_id;
  select coalesce(cg.valor_arriendo,0) into v_valor_arriendo from public.configuracion_gestion cg where cg.id=1;

  select count(*) into v_pagadas
  from public.cuotas_socios cs
  where cs.socio_id=v_socio_id and cs.estado='pagado'
    and cs.periodo>=v_desde and cs.periodo<=v_hasta;

  select count(*) into v_deuda
  from public.cuotas_socios cs
  where cs.socio_id=v_socio_id and cs.estado='pendiente'
    and cs.periodo<date_trunc('month',current_date)::date;

  for b in
    select * from public.beneficios_config bc
    where bc.activo
      and bc.categoria='operativo'
      and bc.aplica_a='arriendo_sede'
      and (bc.vigencia_desde is null or bc.vigencia_desde<=current_date)
      and (bc.vigencia_hasta is null or bc.vigencia_hasta>=current_date)
    order by bc.prioridad asc,bc.nombre asc
  loop
    select count(*) into v_usados
    from public.beneficios_usos bu
    where bu.socio_id=v_socio_id and bu.beneficio_id=b.id and bu.anio=v_anio
      and coalesce(bu.estado,'aplicado')<>'revertido';

    beneficio_id:=b.id;
    nombre:=b.nombre;
    tipo:=b.tipo;
    valor:=b.valor;
    cuotas_minimas:=b.cuotas_minimas;
    cumple:=(v_deuda<3)
      and (not b.exigir_socio_activo or v_estado='activo')
      and v_pagadas>=b.cuotas_minimas
      and (not b.exigir_sin_deuda or v_deuda=0)
      and v_usados<b.usos_maximos_anuales;

    motivo:=case
      when v_deuda>=3 then 'Beneficios suspendidos por morosidad: mantiene '||v_deuda||' cuotas vencidas.'
      when b.exigir_socio_activo and coalesce(v_estado,'')<>'activo' then 'El socio no se encuentra vigente.'
      when v_pagadas<b.cuotas_minimas then 'Tiene '||v_pagadas||' de '||b.cuotas_minimas||' cuotas requeridas dentro de los últimos 12 meses.'
      when b.exigir_sin_deuda and v_deuda>0 then 'Mantiene '||v_deuda||' cuota(s) vencida(s).'
      when v_usados>=b.usos_maximos_anuales then 'Ya alcanzó el máximo de '||b.usos_maximos_anuales||' uso(s) para '||v_anio||'.'
      else 'Cumple los requisitos.'
    end;

    detalle:=v_pagadas||' cuota(s) pagada(s) en los últimos 12 meses · '||v_deuda||' cuota(s) vencida(s)'
      ||case when b.tipo='gratis' then ' · gratuidad'
              when b.tipo='porcentaje' then ' · '||b.valor||'% de descuento'
              else ' · descuento de $'||b.valor end
      ||case when b.usos_maximos_anuales<999 then ' · '||v_usados||' de '||b.usos_maximos_anuales||' uso(s) utilizados en '||v_anio else '' end;

    valor_final:=case
      when not cumple then v_valor_arriendo
      when b.tipo='gratis' then 0
      when b.tipo='porcentaje' then greatest(0,round(v_valor_arriendo*(1-b.valor/100)))
      else greatest(0,v_valor_arriendo-b.valor)
    end;
    return next;
  end loop;
end $$;

revoke all on function public.portal_socio_mis_beneficios(text) from public;
grant execute on function public.portal_socio_mis_beneficios(text) to anon,authenticated;

-- ============================================================
-- Confirmación de reserva: vuelve a comprobar el beneficio en el momento
-- de confirmar, para que una solicitud antigua no salte la suspensión.
-- ============================================================
create or replace function public.confirmar_beneficio_reserva(p_reserva_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  r record;
  v_anio integer;
  v_valor numeric:=0;
  v_cumple boolean:=false;
  v_motivo text;
begin
  if auth.uid() is null or not public.es_admin() then
    raise exception 'Acceso no autorizado';
  end if;

  select rs.id,rs.socio_id,rs.fecha_evento,rs.beneficio_solicitado_id,rs.beneficio_confirmado_id
    into r
  from public.reservas_sede rs
  where rs.id=p_reserva_id
  for update;

  if r.id is null or r.socio_id is null or r.beneficio_solicitado_id is null then return; end if;
  if r.beneficio_confirmado_id is not null then return; end if;

  select coalesce(cg.valor_arriendo,0) into v_valor from public.configuracion_gestion cg where cg.id=1;

  select e.cumple,e.motivo into v_cumple,v_motivo
  from public.evaluar_beneficios_socio(r.socio_id,r.fecha_evento,v_valor) e
  where e.beneficio_id=r.beneficio_solicitado_id
  limit 1;

  if coalesce(v_cumple,false)=false then
    raise exception 'El beneficio ya no está disponible: %',coalesce(v_motivo,'no cumple los requisitos actuales.');
  end if;

  v_anio:=extract(year from r.fecha_evento);
  insert into public.beneficios_usos(socio_id,beneficio_id,anio,fecha_uso,estado,reserva_id)
  values(r.socio_id,r.beneficio_solicitado_id,v_anio,r.fecha_evento,'aplicado',r.id)
  on conflict do nothing;

  update public.reservas_sede
  set beneficio_confirmado_id=r.beneficio_solicitado_id
  where id=r.id;
end $$;

revoke all on function public.confirmar_beneficio_reserva(uuid) from public;
revoke all on function public.confirmar_beneficio_reserva(uuid) from anon;
grant execute on function public.confirmar_beneficio_reserva(uuid) to authenticated;

notify pgrst, 'reload schema';
