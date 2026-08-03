-- SIGVE v5.4 · Certificados integrados (portal público, Portal Socio y administración)
-- Ejecutar completo en Supabase > SQL Editor.
begin;

alter table public.certificados_emitidos
  add column if not exists solicitante_nombre text,
  add column if not exists solicitante_numero_socio bigint,
  add column if not exists para_otra_persona boolean not null default false;

-- Elimina firmas anteriores para evitar ambigüedad en PostgREST.
drop function if exists public.solicitar_certificado_residencia(text,text,text,text,text,text,text,text,text,text);
drop function if exists public.solicitar_certificado_residencia(text,text,text,text,text,text,text,text,text,text,boolean);

create function public.solicitar_certificado_residencia(
  p_nombre text,
  p_rut text,
  p_nacionalidad text,
  p_direccion text,
  p_finalidad text,
  p_finalidad_otro text default null,
  p_telefono text default null,
  p_correo text default null,
  p_origen text default 'publico',
  p_token text default null,
  p_para_otro boolean default false
) returns table(certificado_id uuid, folio bigint, rut_formateado text, valor numeric)
language plpgsql security definer set search_path=public as $$
declare
  v_socio uuid:=null;
  v_folio bigint;
  v_valor numeric:=1000;
  v_id uuid;
  v_rut text;
  v_solicitante_nombre text:=null;
  v_numero_socio bigint:=null;
  v_direccion_socio text:=null;
  v_telefono_socio text:=null;
  v_correo_socio text:=null;
begin
  if p_origen not in ('publico','portal_socio') then raise exception 'Origen inválido'; end if;
  if length(btrim(coalesce(p_nombre,'')))<3 then raise exception 'Ingresa un nombre válido'; end if;
  v_rut:=public.sigve_formatear_rut(p_rut);
  if not public.sigve_rut_valido(v_rut) then raise exception 'El RUT ingresado no es válido'; end if;
  if length(btrim(coalesce(p_nacionalidad,'')))<3 then raise exception 'Ingresa una nacionalidad válida'; end if;
  if length(btrim(coalesce(p_direccion,'')))<4 then raise exception 'Ingresa una dirección válida'; end if;
  if p_finalidad not in ('laboral','estudiantil','transporte','otro') then raise exception 'Selecciona una finalidad válida'; end if;
  if p_finalidad='otro' and length(btrim(coalesce(p_finalidad_otro,'')))<3 then raise exception 'Especifica la otra finalidad'; end if;

  if p_origen='portal_socio' then
    v_socio:=public.portal_socio_validar_sesion(p_token);
    if v_socio is null then raise exception 'La sesión del Portal Socio venció'; end if;

    select s.nombre_completo,s.numero_socio,s.direccion,s.telefono,s.correo
      into v_solicitante_nombre,v_numero_socio,v_direccion_socio,v_telefono_socio,v_correo_socio
    from public.socios s where s.id=v_socio;

    -- El domicilio y los datos de contacto siempre corresponden al socio titular.
    p_direccion:=coalesce(nullif(btrim(v_direccion_socio),''),p_direccion);
    p_telefono:=coalesce(nullif(btrim(v_telefono_socio),''),p_telefono);
    p_correo:=coalesce(nullif(btrim(v_correo_socio),''),p_correo);
  else
    p_para_otro:=false;
  end if;

  select coalesce(valor_certificado,1000) into v_valor from public.configuracion_gestion where id=1;
  perform pg_advisory_xact_lock(73472026);
  select coalesce(max(coalesce(ce.folio,ce.numero)),0)+1 into v_folio from public.certificados_emitidos ce;

  insert into public.certificados_emitidos(
    folio,socio_id,nombre,rut,nacionalidad,direccion,finalidad,finalidad_otro,destino,
    tipo,fecha,valor,es_socio,estado_documento,estado_pago,telefono,correo,
    origen_solicitud,solicitado_en,observaciones,referencia_transferencia,
    solicitante_nombre,solicitante_numero_socio,para_otra_persona
  ) values(
    v_folio,v_socio,btrim(p_nombre),v_rut,btrim(p_nacionalidad),btrim(p_direccion),p_finalidad,
    case when p_finalidad='otro' then nullif(btrim(coalesce(p_finalidad_otro,'')),'') else null end,
    null,'Residencia',current_date,v_valor,v_socio is not null,'pendiente_emision','pendiente',
    nullif(btrim(coalesce(p_telefono,'')),''),nullif(lower(btrim(coalesce(p_correo,''))),'') ,
    p_origen,now(),null,null,
    case when p_origen='portal_socio' then v_solicitante_nombre else btrim(p_nombre) end,
    v_numero_socio,coalesce(p_para_otro,false)
  ) returning id into v_id;

  return query select v_id,v_folio,v_rut,v_valor;
end $$;

revoke all on function public.solicitar_certificado_residencia(text,text,text,text,text,text,text,text,text,text,boolean) from public;
grant execute on function public.solicitar_certificado_residencia(text,text,text,text,text,text,text,text,text,text,boolean) to anon,authenticated;

commit;
notify pgrst,'reload schema';
