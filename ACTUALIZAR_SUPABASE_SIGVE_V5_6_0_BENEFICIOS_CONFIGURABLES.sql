-- SIGVE v5.6.0 · Beneficios configurables
-- Ejecutar completo en Supabase > SQL Editor.
-- Conserva los beneficios y usos existentes.
begin;
alter table public.beneficios_config
  add column if not exists categoria text not null default 'operativo',
  add column if not exists requisitos_texto text,
  add column if not exists mostrar_portal boolean not null default true,
  add column if not exists exigir_socio_activo boolean not null default true,
  add column if not exists aplica_a text not null default 'arriendo_sede';
update public.beneficios_config set categoria=coalesce(categoria,'operativo'), exigir_socio_activo=coalesce(exigir_socio_activo,true), aplica_a=case when categoria='informativo' then 'informativo' else coalesce(aplica_a,'arriendo_sede') end;
create or replace function public.evaluar_beneficios_socio(p_socio_id uuid,p_fecha date,p_valor_original numeric)
returns table(beneficio_id uuid,nombre text,tipo text,cumple boolean,motivo text,detalle text,valor_final numeric)
language plpgsql security definer set search_path=public as $$
declare b record; pagadas integer; deuda integer; usados integer; a integer:=extract(year from p_fecha); v_estado text;
begin
 select estado into v_estado from socios where id=p_socio_id;
 select count(*) into pagadas from cuotas_socios where socio_id=p_socio_id and estado='pagado' and extract(year from periodo)=a;
 select count(*) into deuda from cuotas_socios where socio_id=p_socio_id and estado='pendiente' and periodo < date_trunc('month',p_fecha)::date;
 for b in select * from beneficios_config where activo and categoria='operativo' and aplica_a='arriendo_sede' and (vigencia_desde is null or vigencia_desde<=p_fecha) and (vigencia_hasta is null or vigencia_hasta>=p_fecha) order by prioridad asc,nombre asc loop
  select count(*) into usados from beneficios_usos where socio_id=p_socio_id and beneficio_id=b.id and anio=a and coalesce(estado,'aplicado')<>'revertido';
  beneficio_id:=b.id; nombre:=b.nombre; tipo:=b.tipo;
  cumple:=(not b.exigir_socio_activo or v_estado='activo') and pagadas>=b.cuotas_minimas and (not b.exigir_sin_deuda or deuda=0) and usados<b.usos_maximos_anuales;
  motivo:=case when b.exigir_socio_activo and coalesce(v_estado,'')<>'activo' then 'El socio no se encuentra vigente.' when pagadas<b.cuotas_minimas then 'Tiene '||pagadas||' de '||b.cuotas_minimas||' cuotas requeridas.' when b.exigir_sin_deuda and deuda>0 then 'Mantiene '||deuda||' cuota(s) vencida(s).' when usados>=b.usos_maximos_anuales then 'Ya alcanzó el máximo de '||b.usos_maximos_anuales||' uso(s) durante el año.' else 'Cumple los requisitos.' end;
  detalle:=pagadas||' cuotas pagadas en '||a||case when b.tipo='gratis' then ' · gratuidad' when b.tipo='porcentaje' then ' · '||b.valor||'% de descuento' else ' · descuento de $'||b.valor end||case when b.usos_maximos_anuales<999 then ' · '||usados||' de '||b.usos_maximos_anuales||' uso(s) utilizados' else '' end;
  valor_final:=case when not cumple then p_valor_original when b.tipo='gratis' then 0 when b.tipo='porcentaje' then greatest(0,round(p_valor_original*(1-b.valor/100))) else greatest(0,p_valor_original-b.valor) end;
  return next;
 end loop;
end $$;
grant execute on function public.evaluar_beneficios_socio(uuid,date,numeric) to authenticated;
create or replace function public.portal_socio_beneficios_informativos(p_token text)
returns table(beneficio_id uuid,nombre text,descripcion text,requisitos_texto text,vigencia_desde date,vigencia_hasta date)
language plpgsql security definer set search_path=public as $$
declare v_socio uuid;
begin
 v_socio:=public.portal_socio_validar_sesion(p_token);
 if v_socio is null then raise exception 'Sesión inválida o expirada'; end if;
 return query select b.id,b.nombre,b.descripcion,b.requisitos_texto,b.vigencia_desde,b.vigencia_hasta from public.beneficios_config b where b.activo and b.categoria='informativo' and b.mostrar_portal and (b.vigencia_desde is null or b.vigencia_desde<=current_date) and (b.vigencia_hasta is null or b.vigencia_hasta>=current_date) order by b.prioridad asc,b.nombre asc;
end $$;
grant execute on function public.portal_socio_beneficios_informativos(text) to anon,authenticated;
commit;
