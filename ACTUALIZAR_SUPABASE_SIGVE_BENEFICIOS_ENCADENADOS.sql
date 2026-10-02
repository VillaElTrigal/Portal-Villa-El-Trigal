-- SIGVE · Beneficios encadenados · 02-10-2026
-- Permite exigir que un beneficio solo se desbloquee después de haber usado otros beneficios en el mismo año.
begin;

create table if not exists public.beneficios_requisitos_previos (
  beneficio_id uuid not null references public.beneficios_config(id) on delete cascade,
  beneficio_requerido_id uuid not null references public.beneficios_config(id) on delete cascade,
  creado_en timestamptz not null default now(),
  primary key (beneficio_id, beneficio_requerido_id),
  constraint beneficio_no_se_requiere_a_si_mismo check (beneficio_id <> beneficio_requerido_id)
);

alter table public.beneficios_requisitos_previos enable row level security;
drop policy if exists "beneficios requisitos autenticados" on public.beneficios_requisitos_previos;
create policy "beneficios requisitos autenticados" on public.beneficios_requisitos_previos
for all to authenticated using (true) with check (true);
grant select,insert,update,delete on public.beneficios_requisitos_previos to authenticated;

create or replace function public.evaluar_beneficios_socio(p_socio_id uuid,p_fecha date,p_valor_original numeric)
returns table(beneficio_id uuid,nombre text,tipo text,cumple boolean,motivo text,detalle text,valor_final numeric)
language plpgsql security definer set search_path=public as $$
declare
 b record; pagadas integer; deuda integer; usados integer; a integer:=extract(year from p_fecha);
 v_estado text; v_prev_total integer; v_prev_usados integer; v_prev_nombres text;
begin
 if auth.uid() is null or not public.es_admin() then raise exception 'Acceso no autorizado'; end if;
 select s.estado into v_estado from public.socios s where s.id=p_socio_id;
 if not found then raise exception 'Socio no encontrado.'; end if;
 -- Cuotas efectivamente pagadas durante los 12 meses anteriores a la fecha del arriendo.
 select count(*) into pagadas from public.cuotas_socios cs
 where cs.socio_id=p_socio_id and cs.estado='pagado'
   and coalesce(cs.fecha_pago,cs.periodo::timestamptz) >= (p_fecha::timestamptz-interval '12 months')
   and coalesce(cs.fecha_pago,cs.periodo::timestamptz) < (p_fecha::timestamptz+interval '1 day');
 select count(*) into deuda from public.cuotas_socios cs where cs.socio_id=p_socio_id and cs.estado='pendiente' and cs.periodo<date_trunc('month',p_fecha)::date;
 for b in select * from public.beneficios_config bc where bc.activo and bc.categoria='operativo' and bc.aplica_a='arriendo_sede' and (bc.vigencia_desde is null or bc.vigencia_desde<=p_fecha) and (bc.vigencia_hasta is null or bc.vigencia_hasta>=p_fecha) order by bc.prioridad,bc.nombre loop
   select count(*) into usados from public.beneficios_usos bu where bu.socio_id=p_socio_id and bu.beneficio_id=b.id and bu.anio=a and coalesce(bu.estado,'aplicado')<>'revertido';
   select count(*), string_agg(bc.nombre, ' + ' order by bc.nombre) into v_prev_total,v_prev_nombres
   from public.beneficios_requisitos_previos rp join public.beneficios_config bc on bc.id=rp.beneficio_requerido_id where rp.beneficio_id=b.id;
   select count(distinct rp.beneficio_requerido_id) into v_prev_usados
   from public.beneficios_requisitos_previos rp
   where rp.beneficio_id=b.id and exists(select 1 from public.beneficios_usos bu where bu.socio_id=p_socio_id and bu.beneficio_id=rp.beneficio_requerido_id and bu.anio=a and coalesce(bu.estado,'aplicado')<>'revertido');
   beneficio_id:=b.id; nombre:=b.nombre; tipo:=b.tipo;
   cumple:=(deuda<3) and (not b.exigir_socio_activo or v_estado='activo') and pagadas>=b.cuotas_minimas and (not b.exigir_sin_deuda or deuda=0) and usados<b.usos_maximos_anuales and v_prev_usados=v_prev_total;
   motivo:=case when deuda>=3 then 'Beneficios suspendidos por morosidad: mantiene '||deuda||' cuotas vencidas.' when b.exigir_socio_activo and coalesce(v_estado,'')<>'activo' then 'El socio no se encuentra vigente.' when pagadas<b.cuotas_minimas then 'Tiene '||pagadas||' de '||b.cuotas_minimas||' cuotas requeridas dentro de los últimos 12 meses.' when b.exigir_sin_deuda and deuda>0 then 'Mantiene '||deuda||' cuota(s) vencida(s).' when v_prev_usados<v_prev_total then 'Disponible después de utilizar: '||coalesce(v_prev_nombres,'los beneficios requeridos')||'.' when usados>=b.usos_maximos_anuales then 'Ya alcanzó el máximo de '||b.usos_maximos_anuales||' uso(s) para '||a||'.' else 'Cumple los requisitos.' end;
   detalle:=pagadas||' cuota(s) pagada(s) en los últimos 12 meses · '||deuda||' cuota(s) vencida(s)'||case when v_prev_total>0 then ' · beneficios previos: '||v_prev_usados||' de '||v_prev_total else '' end||case when b.tipo='gratis' then ' · gratuidad' when b.tipo='porcentaje' then ' · '||b.valor||'% de descuento' else ' · descuento de $'||b.valor end||case when b.usos_maximos_anuales<999 then ' · '||usados||' de '||b.usos_maximos_anuales||' uso(s) utilizados en '||a else '' end;
   valor_final:=case when not cumple then p_valor_original when b.tipo='gratis' then 0 when b.tipo='porcentaje' then greatest(0,round(p_valor_original*(1-b.valor/100))) else greatest(0,p_valor_original-b.valor) end;
   return next;
 end loop;
end $$;
revoke all on function public.evaluar_beneficios_socio(uuid,date,numeric) from public;
revoke all on function public.evaluar_beneficios_socio(uuid,date,numeric) from anon;
grant execute on function public.evaluar_beneficios_socio(uuid,date,numeric) to authenticated;

-- Portal Socio: misma regla, sin exponer funciones administrativas.
create or replace function public.portal_socio_mis_beneficios(p_token text)
returns table(beneficio_id uuid,nombre text,tipo text,valor numeric,cuotas_minimas integer,cumple boolean,motivo text,detalle text,valor_final numeric)
language plpgsql security definer set search_path=public as $$
declare
 v_socio_id uuid; v_valor_arriendo numeric:=0; v_estado text; v_pagadas integer; v_deuda integer; v_usados integer; v_anio integer:=extract(year from current_date)::integer; b record; v_prev_total integer; v_prev_usados integer; v_prev_nombres text;
begin
 v_socio_id:=public.portal_socio_validar_sesion(p_token); if v_socio_id is null then raise exception 'Sesión inválida o expirada'; end if;
 select s.estado into v_estado from public.socios s where s.id=v_socio_id;
 select coalesce(cg.valor_arriendo,0) into v_valor_arriendo from public.configuracion_gestion cg where cg.id=1;
 select count(*) into v_pagadas from public.cuotas_socios cs where cs.socio_id=v_socio_id and cs.estado='pagado' and coalesce(cs.fecha_pago,cs.periodo::timestamptz)>=(current_date::timestamptz-interval '12 months') and coalesce(cs.fecha_pago,cs.periodo::timestamptz)<(current_date::timestamptz+interval '1 day');
 select count(*) into v_deuda from public.cuotas_socios cs where cs.socio_id=v_socio_id and cs.estado='pendiente' and cs.periodo<date_trunc('month',current_date)::date;
 for b in select * from public.beneficios_config bc where bc.activo and bc.categoria='operativo' and bc.aplica_a='arriendo_sede' and (bc.vigencia_desde is null or bc.vigencia_desde<=current_date) and (bc.vigencia_hasta is null or bc.vigencia_hasta>=current_date) order by bc.prioridad,bc.nombre loop
   select count(*) into v_usados from public.beneficios_usos bu where bu.socio_id=v_socio_id and bu.beneficio_id=b.id and bu.anio=v_anio and coalesce(bu.estado,'aplicado')<>'revertido';
   select count(*),string_agg(bc.nombre,' + ' order by bc.nombre) into v_prev_total,v_prev_nombres from public.beneficios_requisitos_previos rp join public.beneficios_config bc on bc.id=rp.beneficio_requerido_id where rp.beneficio_id=b.id;
   select count(distinct rp.beneficio_requerido_id) into v_prev_usados from public.beneficios_requisitos_previos rp where rp.beneficio_id=b.id and exists(select 1 from public.beneficios_usos bu where bu.socio_id=v_socio_id and bu.beneficio_id=rp.beneficio_requerido_id and bu.anio=v_anio and coalesce(bu.estado,'aplicado')<>'revertido');
   beneficio_id:=b.id;nombre:=b.nombre;tipo:=b.tipo;valor:=b.valor;cuotas_minimas:=b.cuotas_minimas;
   cumple:=(v_deuda<3) and (not b.exigir_socio_activo or v_estado='activo') and v_pagadas>=b.cuotas_minimas and (not b.exigir_sin_deuda or v_deuda=0) and v_usados<b.usos_maximos_anuales and v_prev_usados=v_prev_total;
   motivo:=case when v_deuda>=3 then 'Beneficios suspendidos por morosidad: mantiene '||v_deuda||' cuotas vencidas.' when b.exigir_socio_activo and coalesce(v_estado,'')<>'activo' then 'El socio no se encuentra vigente.' when v_pagadas<b.cuotas_minimas then 'Tiene '||v_pagadas||' de '||b.cuotas_minimas||' cuotas requeridas dentro de los últimos 12 meses.' when b.exigir_sin_deuda and v_deuda>0 then 'Mantiene '||v_deuda||' cuota(s) vencida(s).' when v_prev_usados<v_prev_total then 'Disponible después de utilizar: '||coalesce(v_prev_nombres,'los beneficios requeridos')||'.' when v_usados>=b.usos_maximos_anuales then 'Ya alcanzó el máximo de '||b.usos_maximos_anuales||' uso(s) para '||v_anio||'.' else 'Cumple los requisitos.' end;
   detalle:=v_pagadas||' cuota(s) pagada(s) en los últimos 12 meses · '||v_deuda||' cuota(s) vencida(s)'||case when v_prev_total>0 then ' · beneficios previos: '||v_prev_usados||' de '||v_prev_total else '' end||case when b.tipo='gratis' then ' · gratuidad' when b.tipo='porcentaje' then ' · '||b.valor||'% de descuento' else ' · descuento de $'||b.valor end||case when b.usos_maximos_anuales<999 then ' · '||v_usados||' de '||b.usos_maximos_anuales||' uso(s) utilizados en '||v_anio else '' end;
   valor_final:=case when not cumple then v_valor_arriendo when b.tipo='gratis' then 0 when b.tipo='porcentaje' then greatest(0,round(v_valor_arriendo*(1-b.valor/100))) else greatest(0,v_valor_arriendo-b.valor) end; return next;
 end loop;
end $$;
revoke all on function public.portal_socio_mis_beneficios(text) from public;
grant execute on function public.portal_socio_mis_beneficios(text) to anon,authenticated;
commit;
notify pgrst,'reload schema';
