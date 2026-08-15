-- SIGVE v5.6.4 · Beneficios por últimos 12 meses
-- Ejecutar completo en Supabase > SQL Editor.
-- No modifica beneficios ni usos existentes; actualiza únicamente su evaluación.
begin;
create or replace function public.evaluar_beneficios_socio(p_socio_id uuid,p_fecha date,p_valor_original numeric)
returns table(beneficio_id uuid,nombre text,tipo text,cumple boolean,motivo text,detalle text,valor_final numeric)
language plpgsql security definer set search_path=public as $$
declare b record; pagadas integer; deuda integer; usados integer;
 a integer:=extract(year from p_fecha); v_estado text;
 v_desde date:=(date_trunc('month',p_fecha)-interval '11 months')::date;
 v_hasta date:=(date_trunc('month',p_fecha)+interval '1 month - 1 day')::date;
begin
 if auth.uid() is null or not public.es_admin() then raise exception 'Acceso no autorizado'; end if;
 select estado into v_estado from public.socios where id=p_socio_id;
 if not found then raise exception 'Socio no encontrado.'; end if;
 select count(*) into pagadas from public.cuotas_socios
  where socio_id=p_socio_id and estado='pagado' and periodo>=v_desde and periodo<=v_hasta;
 select count(*) into deuda from public.cuotas_socios
  where socio_id=p_socio_id and estado='pendiente' and periodo<date_trunc('month',p_fecha)::date;
 for b in select * from public.beneficios_config
  where activo and categoria='operativo' and aplica_a='arriendo_sede'
   and (vigencia_desde is null or vigencia_desde<=p_fecha)
   and (vigencia_hasta is null or vigencia_hasta>=p_fecha)
  order by prioridad asc,nombre asc
 loop
  select count(*) into usados from public.beneficios_usos
   where socio_id=p_socio_id and beneficio_id=b.id and anio=a
    and coalesce(estado,'aplicado')<>'revertido';
  beneficio_id:=b.id; nombre:=b.nombre; tipo:=b.tipo;
  cumple:=(not b.exigir_socio_activo or v_estado='activo')
   and pagadas>=b.cuotas_minimas
   and (not b.exigir_sin_deuda or deuda=0)
   and usados<b.usos_maximos_anuales;
  motivo:=case
   when b.exigir_socio_activo and coalesce(v_estado,'')<>'activo' then 'El socio no se encuentra vigente.'
   when pagadas<b.cuotas_minimas then 'Tiene '||pagadas||' de '||b.cuotas_minimas||' cuotas requeridas dentro de los últimos 12 meses.'
   when b.exigir_sin_deuda and deuda>0 then 'Mantiene '||deuda||' cuota(s) vencida(s).'
   when usados>=b.usos_maximos_anuales then 'Ya alcanzó el máximo de '||b.usos_maximos_anuales||' uso(s) para '||a||'.'
   else 'Cumple los requisitos.' end;
  detalle:=pagadas||' cuota(s) pagada(s) en los últimos 12 meses'
   ||case when b.tipo='gratis' then ' · gratuidad'
           when b.tipo='porcentaje' then ' · '||b.valor||'% de descuento'
           else ' · descuento de $'||b.valor end
   ||case when b.usos_maximos_anuales<999 then ' · '||usados||' de '||b.usos_maximos_anuales||' uso(s) utilizados en '||a else '' end;
  valor_final:=case when not cumple then p_valor_original when b.tipo='gratis' then 0
   when b.tipo='porcentaje' then greatest(0,round(p_valor_original*(1-b.valor/100)))
   else greatest(0,p_valor_original-b.valor) end;
  return next;
 end loop;
end $$;
revoke all on function public.evaluar_beneficios_socio(uuid,date,numeric) from public;
revoke all on function public.evaluar_beneficios_socio(uuid,date,numeric) from anon;
grant execute on function public.evaluar_beneficios_socio(uuid,date,numeric) to authenticated;
commit;
notify pgrst, 'reload schema';
select p.proname as funcion,
 case when has_function_privilege('anon',p.oid,'EXECUTE') then 'SI' else 'NO' end as anon,
 case when has_function_privilege('authenticated',p.oid,'EXECUTE') then 'SI' else 'NO' end as authenticated
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='evaluar_beneficios_socio';
