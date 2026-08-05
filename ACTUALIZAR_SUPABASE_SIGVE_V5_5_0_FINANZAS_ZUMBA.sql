-- SIGVE v5.5.0 · Fecha real de pago de certificados
-- Ejecutar completo una sola vez en Supabase > SQL Editor.

begin;

create or replace function public.registrar_certificado_v111(
  p_folio bigint,
  p_socio_id uuid,
  p_nombre text,
  p_rut text,
  p_nacionalidad text,
  p_direccion text,
  p_finalidad text,
  p_finalidad_otro text,
  p_fecha date,
  p_valor numeric,
  p_estado_documento text,
  p_estado_pago text,
  p_medio text,
  p_fondo text,
  p_referencia text,
  p_observaciones text
) returns uuid
language plpgsql security definer set search_path=public
as $$
declare v_id uuid; v_mov uuid; v_fecha_pago date;
begin
  if not public.es_admin() then raise exception 'Acceso denegado'; end if;
  if p_folio is null or p_folio <= 0 then raise exception 'Debes ingresar un folio válido'; end if;
  if exists(select 1 from public.certificados_emitidos where folio=p_folio) then raise exception 'El folio % ya está registrado',p_folio; end if;
  if p_estado_documento not in ('pendiente_emision','emitido','anulado') then raise exception 'Estado documental inválido'; end if;
  if p_estado_pago not in ('pagado','pendiente','exento','anulado') then raise exception 'Estado de pago inválido'; end if;
  if p_estado_pago='pagado' and (p_medio not in ('efectivo','transferencia') or p_fondo not in ('caja','banco')) then raise exception 'Indica medio de pago y fondo'; end if;

  insert into public.certificados_emitidos(folio,socio_id,nombre,rut,nacionalidad,direccion,finalidad,finalidad_otro,destino,tipo,fecha,valor,es_socio,estado_documento,estado_pago,medio_pago,fondo,referencia_transferencia,observaciones,creado_por,actualizado_por)
  values(p_folio,p_socio_id,btrim(p_nombre),btrim(p_rut),nullif(btrim(coalesce(p_nacionalidad,'')),''),btrim(p_direccion),p_finalidad,nullif(btrim(coalesce(p_finalidad_otro,'')),''),case when p_finalidad='otro' then nullif(btrim(coalesce(p_finalidad_otro,'')),'') else p_finalidad end,'Residencia',p_fecha,p_valor,p_socio_id is not null,p_estado_documento,p_estado_pago,case when p_estado_pago='pagado' then p_medio end,case when p_estado_pago='pagado' then p_fondo end,nullif(btrim(coalesce(p_referencia,'')),''),nullif(btrim(coalesce(p_observaciones,'')),''),auth.uid(),auth.uid()) returning id into v_id;

  if p_estado_pago='pagado' then
    v_fecha_pago := (now() at time zone 'America/Santiago')::date;
    insert into public.movimientos_financieros(fecha,tipo,concepto,categoria,monto,fondo,socio_id,sin_respaldo,observaciones,creado_por,origen_modulo,origen_id)
    values(v_fecha_pago,'ingreso','Pago certificado de residencia - Folio N° '||lpad(p_folio::text,5,'0'),'Certificados de residencia',p_valor,p_fondo,p_socio_id,true,p_observaciones,auth.uid(),'certificado',v_id)
    returning id into v_mov;
    update public.certificados_emitidos set movimiento_id=v_mov where id=v_id;
  end if;

  insert into public.auditoria_financiera(entidad,entidad_id,accion,detalle,usuario_id)
  values('certificado',v_id,'registrado_manual',jsonb_build_object('folio',p_folio,'estado_pago',p_estado_pago),auth.uid());
  return v_id;
end;
$$;

create or replace function public.actualizar_certificado_v111(
  p_id uuid,
  p_folio bigint,
  p_nombre text,
  p_rut text,
  p_nacionalidad text,
  p_direccion text,
  p_finalidad text,
  p_finalidad_otro text,
  p_fecha date,
  p_valor numeric,
  p_estado_documento text,
  p_estado_pago text,
  p_medio text,
  p_fondo text,
  p_referencia text,
  p_observaciones text
) returns boolean
language plpgsql security definer set search_path=public
as $$
declare c public.certificados_emitidos%rowtype; v_mov uuid; v_fecha_pago date;
begin
  if not public.es_admin() then raise exception 'Acceso denegado'; end if;
  select * into c from public.certificados_emitidos where id=p_id for update;
  if not found then raise exception 'Certificado no encontrado'; end if;
  if exists(select 1 from public.certificados_emitidos where folio=p_folio and id<>p_id) then raise exception 'El folio % ya está registrado',p_folio; end if;
  if p_estado_documento not in ('pendiente_emision','emitido','anulado') then raise exception 'Estado documental inválido'; end if;
  if p_estado_pago not in ('pagado','pendiente','exento','anulado') then raise exception 'Estado de pago inválido'; end if;

  if p_estado_pago='pagado' and c.movimiento_id is null then
    if p_medio not in ('efectivo','transferencia') or p_fondo not in ('caja','banco') then raise exception 'Indica medio de pago y fondo'; end if;
    v_fecha_pago := (now() at time zone 'America/Santiago')::date;
    insert into public.movimientos_financieros(fecha,tipo,concepto,categoria,monto,fondo,socio_id,sin_respaldo,observaciones,creado_por,origen_modulo,origen_id)
    values(v_fecha_pago,'ingreso','Pago certificado de residencia - Folio N° '||lpad(p_folio::text,5,'0'),'Certificados de residencia',p_valor,p_fondo,c.socio_id,true,p_observaciones,auth.uid(),'certificado',p_id)
    returning id into v_mov;
  elsif p_estado_pago='pagado' and c.movimiento_id is not null then
    v_mov:=c.movimiento_id;
    -- Se conserva la fecha financiera original: corresponde al día en que fue marcado pagado.
    update public.movimientos_financieros set concepto='Pago certificado de residencia - Folio N° '||lpad(p_folio::text,5,'0'),monto=p_valor,fondo=p_fondo,observaciones=p_observaciones,anulado=false,anulado_en=null,anulado_por=null where id=v_mov;
  elsif p_estado_pago<>'pagado' and c.movimiento_id is not null then
    update public.movimientos_financieros set anulado=true,anulado_en=now(),anulado_por=auth.uid(),observaciones=concat_ws(' · ',observaciones,'ANULADO POR CAMBIO DE ESTADO DEL CERTIFICADO') where id=c.movimiento_id;
    v_mov:=null;
  end if;

  update public.certificados_emitidos set folio=p_folio,nombre=btrim(p_nombre),rut=btrim(p_rut),nacionalidad=nullif(btrim(coalesce(p_nacionalidad,'')),''),direccion=btrim(p_direccion),finalidad=p_finalidad,finalidad_otro=nullif(btrim(coalesce(p_finalidad_otro,'')),''),destino=case when p_finalidad='otro' then nullif(btrim(coalesce(p_finalidad_otro,'')),'') else p_finalidad end,fecha=p_fecha,valor=p_valor,estado_documento=p_estado_documento,estado_pago=p_estado_pago,medio_pago=case when p_estado_pago='pagado' then p_medio end,fondo=case when p_estado_pago='pagado' then p_fondo end,referencia_transferencia=nullif(btrim(coalesce(p_referencia,'')),''),observaciones=nullif(btrim(coalesce(p_observaciones,'')),''),movimiento_id=v_mov,actualizado_en=now(),actualizado_por=auth.uid() where id=p_id;

  insert into public.auditoria_financiera(entidad,entidad_id,accion,detalle,usuario_id)
  values('certificado',p_id,'actualizado',jsonb_build_object('folio',p_folio,'estado_pago',p_estado_pago),auth.uid());
  return true;
end;
$$;

commit;
