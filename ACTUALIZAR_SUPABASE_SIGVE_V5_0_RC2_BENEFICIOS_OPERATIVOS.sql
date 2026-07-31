-- SIGVE v5.0 RC2 · Beneficios operativos en reservas del Portal Socio
-- Ejecutar completo en Supabase SQL Editor después de los scripts v5.0 y v5.0.1.

begin;

-- Evalúa los beneficios del socio para la fecha seleccionada y entrega el precio base.
create or replace function public.portal_socio_beneficios_arriendo(
  p_token text,
  p_fecha date
) returns table(
  beneficio_id uuid,
  nombre text,
  tipo text,
  valor numeric,
  cumple boolean,
  motivo text,
  detalle text,
  valor_original numeric,
  valor_final numeric
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_socio uuid;
  v_valor numeric := 0;
begin
  v_socio := public.portal_socio_validar_sesion(p_token);
  if v_socio is null then
    raise exception 'Sesión inválida o expirada';
  end if;
  if p_fecha is null or p_fecha < current_date then
    raise exception 'La fecha seleccionada no es válida';
  end if;

  select coalesce(c.valor_arriendo,40000)
    into v_valor
  from public.configuracion_gestion c
  where c.id=1;

  return query
  select e.beneficio_id,
         e.nombre,
         e.tipo,
         b.valor,
         e.cumple,
         e.motivo,
         e.detalle,
         v_valor,
         e.valor_final
  from public.evaluar_beneficios_socio(v_socio,p_fecha,v_valor) e
  join public.beneficios_config b on b.id=e.beneficio_id
  order by b.prioridad asc;
end;
$$;

grant execute on function public.portal_socio_beneficios_arriendo(text,date) to anon,authenticated;

-- Crea la solicitud desde una sesión válida del Portal Socio y aplica un solo beneficio.
-- Los descuentos porcentuales/fijos se aplican automáticamente desde la interfaz.
-- El arriendo gratuito solo se aplica cuando el socio lo selecciona.
create or replace function public.crear_solicitud_reserva_portal(
  p_token text,
  p_nombre text,
  p_telefono text,
  p_fecha date,
  p_rut text default null,
  p_observaciones text default null,
  p_beneficio_id uuid default null
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_socio uuid;
  v_reserva uuid;
  v_valor_original numeric(12,2) := 0;
  v_valor_final numeric(12,2) := 0;
  v_beneficio record;
begin
  v_socio := public.portal_socio_validar_sesion(p_token);
  if v_socio is null then
    raise exception 'Sesión inválida o expirada';
  end if;
  if p_fecha < current_date then
    raise exception 'La fecha seleccionada ya pasó.';
  end if;
  if length(btrim(coalesce(p_nombre,''))) < 3 then
    raise exception 'Ingresa un nombre válido.';
  end if;
  if p_telefono !~ '^\+569[0-9]{8}$' then
    raise exception 'El celular no tiene un formato válido.';
  end if;
  if exists(
    select 1 from public.reservas_sede r
    where r.fecha_evento=p_fecha and r.estado not in ('cancelado','archivado')
  ) then
    raise exception 'La fecha ya no está disponible.';
  end if;

  select coalesce(c.valor_arriendo,40000)
    into v_valor_original
  from public.configuracion_gestion c
  where c.id=1;
  v_valor_final := v_valor_original;

  if p_beneficio_id is not null then
    select e.beneficio_id,e.nombre,e.tipo,e.cumple,e.motivo,e.valor_final
      into v_beneficio
    from public.evaluar_beneficios_socio(v_socio,p_fecha,v_valor_original) e
    where e.beneficio_id=p_beneficio_id;

    if not found then
      raise exception 'El beneficio seleccionado no está disponible.';
    end if;
    if not v_beneficio.cumple then
      raise exception 'El beneficio ya no está disponible: %',v_beneficio.motivo;
    end if;
    v_valor_final := v_beneficio.valor_final;
  end if;

  insert into public.reservas_sede(
    nombre_arrendatario,rut,telefono,fecha_evento,hora_inicio,hora_termino,
    tipo,descripcion,valor_total,estado,whatsapp_enviado,socio_id,
    beneficio_id,beneficio_nombre,valor_original,descuento_aplicado
  ) values(
    left(btrim(p_nombre),120),nullif(btrim(p_rut),''),p_telefono,p_fecha,'08:00','22:00',
    'arriendo',nullif(left(btrim(p_observaciones),500),''),v_valor_final,'pendiente',true,v_socio,
    case when p_beneficio_id is null then null else v_beneficio.beneficio_id end,
    case when p_beneficio_id is null then null else v_beneficio.nombre end,
    v_valor_original,greatest(0,v_valor_original-v_valor_final)
  ) returning id into v_reserva;

  if p_beneficio_id is not null then
    insert into public.beneficios_usos(
      beneficio_id,beneficio_nombre,socio_id,reserva_id,anio,
      valor_original,valor_final,descuento
    ) values(
      v_beneficio.beneficio_id,v_beneficio.nombre,v_socio,v_reserva,
      extract(year from p_fecha)::integer,v_valor_original,v_valor_final,
      greatest(0,v_valor_original-v_valor_final)
    );
  end if;

  return v_reserva;
exception
  when unique_violation then
    raise exception 'La fecha ya no está disponible.';
end;
$$;

revoke all on function public.crear_solicitud_reserva_portal(text,text,text,date,text,text,uuid) from public;
grant execute on function public.crear_solicitud_reserva_portal(text,text,text,date,text,text,uuid) to anon,authenticated;

commit;
notify pgrst,'reload schema';
