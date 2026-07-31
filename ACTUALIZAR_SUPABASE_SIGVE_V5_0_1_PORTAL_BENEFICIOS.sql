-- SIGVE v5.0.1 · Beneficios y arriendo desde Portal Socio
-- Ejecutar completo después del SQL de SIGVE v5.0.0.

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
language plpgsql security definer set search_path=public as $$
declare
  v_socio uuid;
  v_valor numeric:=0;
begin
  v_socio:=public.portal_socio_validar_sesion(p_token);
  if v_socio is null then raise exception 'Sesión inválida o expirada'; end if;

  select coalesce(valor_arriendo,0) into v_valor from public.configuracion_gestion where id=1;

  return query
  select e.beneficio_id,e.nombre,e.tipo,b.valor,b.cuotas_minimas,e.cumple,e.motivo,e.detalle,e.valor_final
  from public.evaluar_beneficios_socio(v_socio,current_date,v_valor) e
  join public.beneficios_config b on b.id=e.beneficio_id
  order by b.prioridad asc;
end $$;

grant execute on function public.portal_socio_mis_beneficios(text) to anon,authenticated;
