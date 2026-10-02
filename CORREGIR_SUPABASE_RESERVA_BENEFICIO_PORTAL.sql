-- SIGVE · Corrección integral reserva Portal Socio + beneficio
-- 1) Cuenta cuotas por FECHA REAL DE PAGO dentro de los últimos 12 meses.
-- 2) Al aprobar, confirma el beneficio solicitado, registra un solo uso y sincroniza los campos visibles de la reserva.
-- No crea tablas nuevas.

begin;

create or replace function public.evaluar_beneficios_socio(
  p_socio_id uuid,p_fecha date,p_valor_original numeric
)
returns table(beneficio_id uuid,nombre text,tipo text,cumple boolean,motivo text,detalle text,valor_final numeric)
language plpgsql security definer set search_path=public as $$
declare
  b record; pagadas integer; deuda integer; usados integer;
  a integer:=extract(year from p_fecha); v_estado text;
  v_desde date:=(p_fecha-interval '12 months')::date;
begin
  if auth.uid() is null or not public.es_admin() then raise exception 'Acceso no autorizado'; end if;
  select s.estado into v_estado from public.socios s where s.id=p_socio_id;
  if not found then raise exception 'Socio no encontrado.'; end if;

  select count(*) into pagadas
  from public.cuotas_socios cs
  where cs.socio_id=p_socio_id and cs.estado='pagado'
    and cs.fecha_pago is not null
    and cs.fecha_pago>v_desde and cs.fecha_pago<=p_fecha;

  select count(*) into deuda
  from public.cuotas_socios cs
  where cs.socio_id=p_socio_id and cs.estado='pendiente'
    and cs.periodo<date_trunc('month',p_fecha)::date;

  for b in select bc.* from public.beneficios_config bc
    where bc.activo and bc.categoria='operativo' and bc.aplica_a='arriendo_sede'
      and (bc.vigencia_desde is null or bc.vigencia_desde<=p_fecha)
      and (bc.vigencia_hasta is null or bc.vigencia_hasta>=p_fecha)
    order by bc.prioridad,bc.nombre
  loop
    select count(*) into usados from public.beneficios_usos bu
    where bu.socio_id=p_socio_id and bu.beneficio_id=b.id and bu.anio=a
      and coalesce(bu.estado,'aplicado')<>'revertido';
    beneficio_id:=b.id; nombre:=b.nombre; tipo:=b.tipo;
    cumple:=(deuda<3)
      and (not b.exigir_socio_activo or v_estado='activo')
      and pagadas>=b.cuotas_minimas
      and (not b.exigir_sin_deuda or deuda=0)
      and usados<b.usos_maximos_anuales;
    motivo:=case
      when deuda>=3 then 'Beneficios suspendidos por morosidad: mantiene '||deuda||' cuotas vencidas.'
      when b.exigir_socio_activo and coalesce(v_estado,'')<>'activo' then 'El socio no se encuentra vigente.'
      when pagadas<b.cuotas_minimas then 'Tiene '||pagadas||' de '||b.cuotas_minimas||' cuotas pagadas dentro de los últimos 12 meses.'
      when b.exigir_sin_deuda and deuda>0 then 'Mantiene '||deuda||' cuota(s) vencida(s).'
      when usados>=b.usos_maximos_anuales then 'Ya alcanzó el máximo de '||b.usos_maximos_anuales||' uso(s) para '||a||'.'
      else 'Cumple los requisitos.' end;
    detalle:=pagadas||' cuota(s) pagada(s) en los últimos 12 meses · '||deuda||' cuota(s) vencida(s)';
    valor_final:=case when not cumple then p_valor_original when b.tipo='gratis' then 0
      when b.tipo='porcentaje' then greatest(0,round(p_valor_original*(1-b.valor/100)))
      else greatest(0,p_valor_original-b.valor) end;
    return next;
  end loop;
end $$;

revoke all on function public.evaluar_beneficios_socio(uuid,date,numeric) from public;
revoke all on function public.evaluar_beneficios_socio(uuid,date,numeric) from anon;
grant execute on function public.evaluar_beneficios_socio(uuid,date,numeric) to authenticated;

create or replace function public.portal_socio_mis_beneficios(p_token text)
returns table(beneficio_id uuid,nombre text,tipo text,valor numeric,cuotas_minimas integer,cumple boolean,motivo text,detalle text,valor_final numeric)
language plpgsql security definer set search_path=public as $$
declare
  v_socio_id uuid; v_valor_arriendo numeric:=0; v_estado text; v_pagadas integer; v_deuda integer; v_usados integer;
  v_anio integer:=extract(year from current_date); v_desde date:=(current_date-interval '12 months')::date; b record;
begin
  v_socio_id:=public.portal_socio_validar_sesion(p_token);
  if v_socio_id is null then raise exception 'Sesión inválida o expirada'; end if;
  select s.estado into v_estado from public.socios s where s.id=v_socio_id;
  select coalesce(cg.valor_arriendo,0) into v_valor_arriendo from public.configuracion_gestion cg where cg.id=1;
  select count(*) into v_pagadas from public.cuotas_socios cs
   where cs.socio_id=v_socio_id and cs.estado='pagado' and cs.fecha_pago is not null
     and cs.fecha_pago>v_desde and cs.fecha_pago<=current_date;
  select count(*) into v_deuda from public.cuotas_socios cs
   where cs.socio_id=v_socio_id and cs.estado='pendiente' and cs.periodo<date_trunc('month',current_date)::date;
  for b in select bc.* from public.beneficios_config bc
   where bc.activo and bc.categoria='operativo' and bc.aplica_a='arriendo_sede'
    and (bc.vigencia_desde is null or bc.vigencia_desde<=current_date)
    and (bc.vigencia_hasta is null or bc.vigencia_hasta>=current_date)
   order by bc.prioridad,bc.nombre
  loop
   select count(*) into v_usados from public.beneficios_usos bu
    where bu.socio_id=v_socio_id and bu.beneficio_id=b.id and bu.anio=v_anio
      and coalesce(bu.estado,'aplicado')<>'revertido';
   beneficio_id:=b.id; nombre:=b.nombre; tipo:=b.tipo; valor:=b.valor; cuotas_minimas:=b.cuotas_minimas;
   cumple:=(v_deuda<3) and (not b.exigir_socio_activo or v_estado='activo') and v_pagadas>=b.cuotas_minimas
      and (not b.exigir_sin_deuda or v_deuda=0) and v_usados<b.usos_maximos_anuales;
   motivo:=case when v_deuda>=3 then 'Beneficios suspendidos por morosidad: mantiene '||v_deuda||' cuotas vencidas.'
    when b.exigir_socio_activo and coalesce(v_estado,'')<>'activo' then 'El socio no se encuentra vigente.'
    when v_pagadas<b.cuotas_minimas then 'Tiene '||v_pagadas||' de '||b.cuotas_minimas||' cuotas pagadas dentro de los últimos 12 meses.'
    when b.exigir_sin_deuda and v_deuda>0 then 'Mantiene '||v_deuda||' cuota(s) vencida(s).'
    when v_usados>=b.usos_maximos_anuales then 'Ya alcanzó el máximo de '||b.usos_maximos_anuales||' uso(s) para '||v_anio||'.'
    else 'Cumple los requisitos.' end;
   detalle:=v_pagadas||' cuota(s) pagada(s) en los últimos 12 meses · '||v_deuda||' cuota(s) vencida(s)';
   valor_final:=case when not cumple then v_valor_arriendo when b.tipo='gratis' then 0
    when b.tipo='porcentaje' then greatest(0,round(v_valor_arriendo*(1-b.valor/100))) else greatest(0,v_valor_arriendo-b.valor) end;
   return next;
  end loop;
end $$;
revoke all on function public.portal_socio_mis_beneficios(text) from public;
grant execute on function public.portal_socio_mis_beneficios(text) to anon,authenticated;

create or replace function public.confirmar_beneficio_reserva(p_reserva_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare
 r record; b record; v_anio integer; v_base numeric:=0; v_final numeric:=0; v_cumple boolean:=false; v_motivo text;
begin
 if auth.uid() is null or not public.es_admin() then raise exception 'Acceso no autorizado'; end if;
 select rs.id,rs.socio_id,rs.fecha_evento,rs.beneficio_solicitado_id,rs.beneficio_confirmado_id into r
 from public.reservas_sede rs where rs.id=p_reserva_id for update;
 if r.id is null or r.socio_id is null or r.beneficio_solicitado_id is null then return; end if;
 if r.beneficio_confirmado_id is not null then return; end if;
 select coalesce(cg.valor_arriendo,0) into v_base from public.configuracion_gestion cg where cg.id=1;
 select e.cumple,e.motivo,e.valor_final into v_cumple,v_motivo,v_final
 from public.evaluar_beneficios_socio(r.socio_id,r.fecha_evento,v_base) e
 where e.beneficio_id=r.beneficio_solicitado_id limit 1;
 if not coalesce(v_cumple,false) then raise exception 'El beneficio ya no está disponible: %',coalesce(v_motivo,'no cumple los requisitos actuales.'); end if;
 select bc.id,bc.nombre into b from public.beneficios_config bc where bc.id=r.beneficio_solicitado_id;
 v_anio:=extract(year from r.fecha_evento);
 insert into public.beneficios_usos(socio_id,beneficio_id,beneficio_nombre,reserva_id,anio,fecha_uso,estado,valor_original,valor_final,descuento)
 values(r.socio_id,r.beneficio_solicitado_id,b.nombre,r.id,v_anio,r.fecha_evento,'aplicado',v_base,v_final,greatest(0,v_base-v_final))
 on conflict do nothing;
 update public.reservas_sede set beneficio_confirmado_id=r.beneficio_solicitado_id,
   beneficio_id=r.beneficio_solicitado_id,beneficio_nombre=b.nombre,valor_original=v_base,
   valor_total=v_final,descuento_aplicado=greatest(0,v_base-v_final),actualizado_en=now()
 where id=r.id;
end $$;
revoke all on function public.confirmar_beneficio_reserva(uuid) from public;
revoke all on function public.confirmar_beneficio_reserva(uuid) from anon;
grant execute on function public.confirmar_beneficio_reserva(uuid) to authenticated;

commit;
notify pgrst,'reload schema';
