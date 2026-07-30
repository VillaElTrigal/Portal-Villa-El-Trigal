-- SIGVE v4.1 · Caja de Cuotas y pago desde Portal Socio
-- Ejecutar completo una sola vez en Supabase > SQL Editor.

-- El Portal Socio puede consultar únicamente sus propias cuotas pendientes.
create or replace function public.portal_socio_mis_cuotas(p_token text)
returns table(id uuid, periodo date, monto numeric, estado text)
language plpgsql security definer set search_path=public
as $$
declare v_socio uuid;
begin
  v_socio:=public.portal_socio_validar_sesion(p_token);
  if v_socio is null then raise exception 'Sesión inválida o vencida'; end if;
  return query
  select c.id,c.periodo,c.monto,c.estado
  from public.cuotas_socios c
  where c.socio_id=v_socio and c.estado='pendiente'
  order by c.periodo;
end;
$$;
grant execute on function public.portal_socio_mis_cuotas(text) to anon,authenticated;

-- Registra varias cuotas del mismo socio en una única transacción.
-- Cada cuota crea su movimiento financiero y queda vinculada al socio.
create or replace function public.registrar_pago_cuotas_caja(
  p_cuota_ids uuid[], p_fecha date, p_medio text, p_fondo text,
  p_referencia text default null, p_observaciones text default null
) returns integer
language plpgsql security definer set search_path=public
as $$
declare
  v_id uuid; v_count integer:=0; v_socio uuid; v_actual uuid;
begin
  if not public.es_admin() then raise exception 'Acceso denegado'; end if;
  if coalesce(array_length(p_cuota_ids,1),0)=0 then raise exception 'Selecciona al menos una cuota'; end if;
  if p_medio not in ('efectivo','transferencia') then raise exception 'Medio de pago inválido'; end if;
  if p_fondo not in ('caja','banco') then raise exception 'Fondo inválido'; end if;
  if p_medio='efectivo' and p_fondo<>'caja' then raise exception 'El efectivo debe ingresar a Caja chica'; end if;
  if p_medio='transferencia' and p_fondo<>'banco' then raise exception 'La transferencia debe ingresar a Cuenta bancaria'; end if;

  foreach v_id in array p_cuota_ids loop
    select socio_id into v_actual from public.cuotas_socios where id=v_id for update;
    if v_actual is null then raise exception 'Cuota no encontrada'; end if;
    if v_socio is null then v_socio:=v_actual;
    elsif v_socio<>v_actual then raise exception 'Todas las cuotas deben pertenecer al mismo socio'; end if;
    perform public.registrar_pago_cuota(v_id,p_fecha,p_medio,p_fondo,p_referencia,p_observaciones);
    v_count:=v_count+1;
  end loop;
  return v_count;
end;
$$;
grant execute on function public.registrar_pago_cuotas_caja(uuid[],date,text,text,text,text) to authenticated;
