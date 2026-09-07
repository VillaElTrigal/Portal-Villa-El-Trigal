-- SIGVE · CUOTAS MÚLTIPLES Y ANTICIPADAS V12
-- Ejecutar UNA VEZ en Supabase > SQL Editor.
--
-- Permite preparar entre 1 y 12 cuotas.
-- Si el socio ya tiene cuotas pendientes, se usan primero esas.
-- Si faltan meses, se crean los siguientes y se puede pasar al año siguiente.
-- Ejemplo: sep-oct-nov-dic 2026 + ene 2027.
--
-- IMPORTANTE:
-- Esta función SOLO prepara cuotas. NO las marca pagadas.
-- El pago continúa registrándose con las funciones actuales de Finanzas.

begin;

create or replace function public.preparar_proximas_cuotas_socio(
  p_socio_id uuid,
  p_cantidad integer
)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  s public.socios%rowtype;
  v_valor numeric(12,0);
  v_primer date;
  v_ultimo date;
  v_siguiente date;
  v_pendientes integer:=0;
  v_creadas integer:=0;
  v_insertadas integer:=0;
  v_limite date;
begin
  if p_cantidad is null or p_cantidad<1 or p_cantidad>12 then
    raise exception 'La cantidad debe estar entre 1 y 12 cuotas';
  end if;

  -- Las llamadas directas son para Administración.
  -- Portal Socio utiliza el wrapper seguro por token.
  if auth.uid() is not null and not public.es_admin() then
    raise exception 'Acceso denegado';
  end if;

  select * into s
  from public.socios
  where id=p_socio_id;

  if not found then raise exception 'Socio no encontrado'; end if;
  if s.estado<>'activo' then raise exception 'El socio debe estar activo'; end if;

  if coalesce(s.modalidad_cuota,'cotizante')<>'cotizante' then
    raise exception 'Los socios asociados no generan cuotas propias';
  end if;

  select valor_cuota into v_valor
  from public.configuracion_gestion
  where id=1;

  if v_valor is null then
    raise exception 'No está configurado el valor de la cuota';
  end if;

  v_primer:=public.primer_periodo_cobro(s.fecha_ingreso);
  if v_primer is null then
    raise exception 'No fue posible determinar el primer período de cobro';
  end if;

  select count(*) into v_pendientes
  from public.cuotas_socios
  where socio_id=p_socio_id
    and estado='pendiente';

  -- Si ya existen suficientes cuotas pendientes, no hay que crear otras.
  if v_pendientes>=p_cantidad then
    return 0;
  end if;

  select max(periodo) into v_ultimo
  from public.cuotas_socios
  where socio_id=p_socio_id;

  if v_ultimo is null then
    v_siguiente:=greatest(v_primer,date_trunc('month',current_date)::date);
  else
    v_siguiente:=(v_ultimo+interval '1 month')::date;
    if v_siguiente<v_primer then v_siguiente:=v_primer; end if;
  end if;

  -- Máximo 12 meses hacia adelante desde el mes actual.
  v_limite:=(date_trunc('month',current_date)+interval '12 months')::date;

  while v_pendientes<p_cantidad loop
    if v_siguiente>v_limite then
      raise exception 'No es posible anticipar más de 12 meses desde el mes actual';
    end if;

    insert into public.cuotas_socios(
      socio_id,periodo,estado,monto,creado_por,actualizado_por
    )
    values(
      p_socio_id,
      v_siguiente,
      'pendiente',
      v_valor,
      auth.uid(),
      auth.uid()
    )
    on conflict(socio_id,periodo) do nothing;

    get diagnostics v_insertadas=row_count;
    if v_insertadas>0 then
      v_creadas:=v_creadas+1;
    end if;

    select count(*) into v_pendientes
    from public.cuotas_socios
    where socio_id=p_socio_id
      and estado='pendiente';

    v_siguiente:=(v_siguiente+interval '1 month')::date;
  end loop;

  return v_creadas;
end;
$$;

revoke all on function public.preparar_proximas_cuotas_socio(uuid,integer)
from public,anon;

grant execute on function public.preparar_proximas_cuotas_socio(uuid,integer)
to authenticated;


-- Portal Socio: solo puede preparar cuotas de su propio registro.
create or replace function public.portal_socio_preparar_proximas_cuotas(
  p_token text,
  p_cantidad integer
)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_socio uuid;
begin
  if p_cantidad is null or p_cantidad<1 or p_cantidad>12 then
    raise exception 'La cantidad debe estar entre 1 y 12 cuotas';
  end if;

  v_socio:=public.portal_socio_validar_sesion(p_token);
  if v_socio is null then
    raise exception 'Sesión inválida o vencida';
  end if;

  if not exists(
    select 1
    from public.socios
    where id=v_socio
      and estado='activo'
      and coalesce(modalidad_cuota,'cotizante')='cotizante'
  ) then
    raise exception 'Esta opción está disponible solo para socios cotizantes activos';
  end if;

  return public.preparar_proximas_cuotas_socio(v_socio,p_cantidad);
end;
$$;

revoke all on function public.portal_socio_preparar_proximas_cuotas(text,integer)
from public;

grant execute on function public.portal_socio_preparar_proximas_cuotas(text,integer)
to anon,authenticated;

commit;
