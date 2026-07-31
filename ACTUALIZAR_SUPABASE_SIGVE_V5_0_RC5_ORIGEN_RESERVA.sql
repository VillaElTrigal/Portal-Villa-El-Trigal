-- SIGVE v5.0 RC5 · Reserva pública sin beneficios / Portal Socio con beneficios
-- Ejecutar completo en Supabase > SQL Editor antes de publicar esta versión.

begin;

alter table public.reservas_sede
  add column if not exists origen_reserva text not null default 'administracion';

alter table public.reservas_sede
  drop constraint if exists reservas_sede_origen_reserva_check;

alter table public.reservas_sede
  add constraint reservas_sede_origen_reserva_check
  check (origen_reserva in ('publico','portal_socio','administracion'));

-- Las reservas históricas creadas por la función pública quedan identificadas cuando no tienen socio.
update public.reservas_sede
set origen_reserva = case
  when socio_id is not null then 'portal_socio'
  when tipo='arriendo' and creado_por is null then 'publico'
  else 'administracion'
end
where origen_reserva is null or origen_reserva='administracion';

-- Flujo público: siempre usa precio normal y nunca consulta beneficios.
create or replace function public.crear_solicitud_reserva(
  p_nombre text,
  p_telefono text,
  p_fecha date,
  p_rut text default null,
  p_observaciones text default null
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  nuevo_id uuid;
  valor_configurado numeric(12,2);
begin
  if p_fecha < current_date then raise exception 'La fecha seleccionada ya pasó.'; end if;
  if length(btrim(coalesce(p_nombre,''))) < 3 then raise exception 'Ingresa un nombre válido.'; end if;
  if p_telefono !~ '^\+569[0-9]{8}$' then raise exception 'El celular no tiene un formato válido.'; end if;
  if exists(select 1 from public.reservas_sede where fecha_evento=p_fecha and estado not in ('cancelado','archivado')) then
    raise exception 'La fecha ya no está disponible.';
  end if;

  select coalesce(valor_arriendo,40000) into valor_configurado
  from public.configuracion_gestion where id=1;
  valor_configurado := coalesce(valor_configurado,40000);

  insert into public.reservas_sede(
    nombre_arrendatario,rut,telefono,fecha_evento,hora_inicio,hora_termino,
    tipo,descripcion,valor_total,estado,whatsapp_enviado,origen_reserva,
    socio_id,beneficio_id,beneficio_nombre,valor_original,descuento_aplicado
  ) values(
    left(btrim(p_nombre),120),nullif(btrim(p_rut),''),p_telefono,p_fecha,'08:00','22:00',
    'arriendo',nullif(left(btrim(p_observaciones),500),''),valor_configurado,'pendiente',true,'publico',
    null,null,null,valor_configurado,0
  ) returning id into nuevo_id;
  return nuevo_id;
exception when unique_violation then
  raise exception 'La fecha ya no está disponible.';
end;
$$;

revoke all on function public.crear_solicitud_reserva(text,text,date,text,text) from public;
grant execute on function public.crear_solicitud_reserva(text,text,date,text,text) to anon,authenticated;

-- Flujo Portal Socio: valida la sesión y vuelve a calcular el beneficio en el servidor.
create or replace function public.crear_solicitud_reserva_con_beneficio(
  p_nombre text,
  p_telefono text,
  p_fecha date,
  p_rut text default null,
  p_observaciones text default null,
  p_token text default null,
  p_usar_gratis boolean default false
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_reserva_id uuid;
  v_socio_id uuid;
  v_valor_original numeric(12,2);
  v_valor_final numeric(12,2);
  v_beneficio_id uuid := null;
  v_beneficio_nombre text := null;
  v_beneficio_valor_final numeric(12,2) := null;
begin
  if p_fecha < current_date then raise exception 'La fecha seleccionada ya pasó.'; end if;
  if length(btrim(coalesce(p_nombre,''))) < 3 then raise exception 'Ingresa un nombre válido.'; end if;
  if p_telefono !~ '^\+569[0-9]{8}$' then raise exception 'El celular no tiene un formato válido.'; end if;

  v_socio_id := public.portal_socio_validar_sesion(p_token);
  if v_socio_id is null then
    raise exception 'La sesión del Portal Socio venció. Ingresa nuevamente para utilizar el beneficio.';
  end if;

  if exists(select 1 from public.reservas_sede where fecha_evento=p_fecha and estado not in ('cancelado','archivado')) then
    raise exception 'La fecha ya no está disponible.';
  end if;

  select coalesce(valor_arriendo,40000) into v_valor_original
  from public.configuracion_gestion where id=1;
  v_valor_original := coalesce(v_valor_original,40000);
  v_valor_final := v_valor_original;

  if p_usar_gratis then
    select eb.beneficio_id,eb.nombre,eb.valor_final
      into v_beneficio_id,v_beneficio_nombre,v_beneficio_valor_final
    from public.evaluar_beneficios_socio(v_socio_id,p_fecha,v_valor_original) eb
    join public.beneficios_config bc on bc.id=eb.beneficio_id
    where eb.cumple=true and eb.tipo='gratis'
    order by bc.prioridad asc limit 1;
    if not found then raise exception 'El arriendo gratuito ya no está disponible.'; end if;
  else
    select eb.beneficio_id,eb.nombre,eb.valor_final
      into v_beneficio_id,v_beneficio_nombre,v_beneficio_valor_final
    from public.evaluar_beneficios_socio(v_socio_id,p_fecha,v_valor_original) eb
    join public.beneficios_config bc on bc.id=eb.beneficio_id
    where eb.cumple=true and eb.tipo<>'gratis'
    order by eb.valor_final asc,bc.prioridad asc limit 1;
  end if;

  if found then v_valor_final := v_beneficio_valor_final; end if;

  insert into public.reservas_sede(
    nombre_arrendatario,rut,telefono,fecha_evento,hora_inicio,hora_termino,
    tipo,descripcion,valor_total,estado,whatsapp_enviado,origen_reserva,socio_id,
    beneficio_id,beneficio_nombre,valor_original,descuento_aplicado
  ) values(
    left(btrim(p_nombre),120),nullif(btrim(p_rut),''),p_telefono,p_fecha,'08:00','22:00',
    'arriendo',nullif(left(btrim(p_observaciones),500),''),v_valor_final,'pendiente',true,'portal_socio',v_socio_id,
    v_beneficio_id,v_beneficio_nombre,v_valor_original,greatest(0,v_valor_original-v_valor_final)
  ) returning id into v_reserva_id;

  if v_beneficio_id is not null then
    insert into public.beneficios_usos(
      beneficio_id,beneficio_nombre,socio_id,reserva_id,anio,
      valor_original,valor_final,descuento
    ) values(
      v_beneficio_id,v_beneficio_nombre,v_socio_id,v_reserva_id,
      extract(year from p_fecha)::integer,v_valor_original,v_valor_final,
      greatest(0,v_valor_original-v_valor_final)
    );
  end if;

  return v_reserva_id;
exception when unique_violation then
  raise exception 'La fecha ya no está disponible.';
end;
$$;

revoke all on function public.crear_solicitud_reserva_con_beneficio(text,text,date,text,text,text,boolean) from public;
grant execute on function public.crear_solicitud_reserva_con_beneficio(text,text,date,text,text,text,boolean) to anon,authenticated;

commit;
notify pgrst,'reload schema';
