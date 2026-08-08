-- SIGVE v5.6.3 · Extensión de solicitud de arriendo con beneficio elegido
-- Ejecutar después del archivo BENEFICIO_OPCIONAL.
-- IMPORTANTE: esta migración presupone que ya existe crear_solicitud_reserva_con_beneficio.
-- Se agrega una sobrecarga con p_beneficio_id para registrar la elección sin consumirla.

create or replace function public.crear_solicitud_reserva_con_beneficio(
  p_nombre text,
  p_telefono text,
  p_fecha date,
  p_rut text,
  p_observaciones text,
  p_token text,
  p_usar_gratis boolean,
  p_beneficio_id uuid default null
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_socio uuid;
  v_reserva uuid;
begin
  v_socio:=public.portal_socio_validar_sesion(p_token);
  if v_socio is null then raise exception 'Sesión inválida o expirada'; end if;

  -- Evita tomar una fecha que ya está ocupada.
  if exists(
    select 1 from public.reservas_sede r
    where r.fecha_evento=p_fecha
      and coalesce(r.estado,'') not in ('cancelado','archivado','rechazado')
  ) then
    raise exception 'La fecha seleccionada ya no está disponible.';
  end if;

  insert into public.reservas_sede(
    fecha_evento,tipo,estado,nombre_contacto,telefono_contacto,rut_contacto,
    observaciones,socio_id,beneficio_solicitado_id
  )
  values(
    p_fecha,'arriendo','pendiente',p_nombre,p_telefono,p_rut,
    p_observaciones,v_socio,p_beneficio_id
  )
  returning id into v_reserva;

  -- No se registra ningún uso aquí. Se consumirá al confirmar la reserva en Administración.
end
$$;

grant execute on function public.crear_solicitud_reserva_con_beneficio(
  text,text,date,text,text,text,boolean,uuid
) to anon,authenticated;
