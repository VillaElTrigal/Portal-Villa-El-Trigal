-- SIGVE v5.0 RC7 · Certificados públicos/socio + estabilización beneficios/reservas
-- Ejecutar completo en Supabase > SQL Editor.
begin;

-- 1) Certificados: origen, contacto y trazabilidad de solicitud.
alter table public.certificados_emitidos
  add column if not exists folio bigint,
  add column if not exists nacionalidad text,
  add column if not exists finalidad text,
  add column if not exists finalidad_otro text,
  add column if not exists estado_documento text not null default 'pendiente_emision',
  add column if not exists estado_pago text not null default 'pendiente',
  add column if not exists telefono text,
  add column if not exists correo text,
  add column if not exists medio_pago text,
  add column if not exists fondo text,
  add column if not exists referencia_transferencia text,
  add column if not exists origen_solicitud text not null default 'administracion',
  add column if not exists solicitado_en timestamptz not null default now(),
  add column if not exists actualizado_en timestamptz not null default now(),
  add column if not exists actualizado_por uuid;

-- Conserva numeración histórica: folio toma numero si aún está vacío.
update public.certificados_emitidos set folio=numero where folio is null and numero is not null;
create unique index if not exists certificados_folio_unique on public.certificados_emitidos(folio) where folio is not null;

alter table public.certificados_emitidos drop constraint if exists certificados_origen_solicitud_check;
alter table public.certificados_emitidos add constraint certificados_origen_solicitud_check
  check (origen_solicitud in ('publico','portal_socio','administracion'));

-- Formato y validación de RUT chileno.
create or replace function public.sigve_formatear_rut(p_rut text) returns text
language plpgsql immutable as $$
declare c text; cuerpo text; dv text; salida text:='';
begin
  c:=upper(regexp_replace(coalesce(p_rut,''),'[^0-9K]','','g'));
  if length(c)<2 then return c; end if;
  cuerpo:=left(c,length(c)-1); dv:=right(c,1);
  while length(cuerpo)>3 loop
    salida:='.'||right(cuerpo,3)||salida;
    cuerpo:=left(cuerpo,length(cuerpo)-3);
  end loop;
  return cuerpo||salida||'-'||dv;
end $$;

create or replace function public.sigve_rut_valido(p_rut text) returns boolean
language plpgsql immutable as $$
declare c text; cuerpo text; dv text; suma integer:=0; factor integer:=2; i integer; resto integer; esperado text;
begin
  c:=upper(regexp_replace(coalesce(p_rut,''),'[^0-9K]','','g'));
  if length(c)<7 then return false; end if;
  cuerpo:=left(c,length(c)-1); dv:=right(c,1);
  for i in reverse length(cuerpo)..1 loop
    suma:=suma+(substr(cuerpo,i,1)::integer)*factor;
    factor:=case when factor=7 then 2 else factor+1 end;
  end loop;
  resto:=11-(suma%11);
  esperado:=case when resto=11 then '0' when resto=10 then 'K' else resto::text end;
  return dv=esperado;
exception when others then return false;
end $$;

-- Crea la solicitud, asigna correlativo único y la deja pendiente de pago/emisión.
create or replace function public.solicitar_certificado_residencia(
  p_nombre text,
  p_rut text,
  p_nacionalidad text,
  p_direccion text,
  p_finalidad text,
  p_telefono text default null,
  p_correo text default null,
  p_origen text default 'publico',
  p_token text default null
) returns table(certificado_id uuid, folio bigint, rut_formateado text, valor numeric)
language plpgsql security definer set search_path=public as $$
declare v_socio uuid:=null; v_folio bigint; v_valor numeric:=1000; v_id uuid; v_rut text;
begin
  if p_origen not in ('publico','portal_socio') then raise exception 'Origen inválido'; end if;
  if length(btrim(coalesce(p_nombre,'')))<3 then raise exception 'Ingresa un nombre válido'; end if;
  v_rut:=public.sigve_formatear_rut(p_rut);
  if not public.sigve_rut_valido(v_rut) then raise exception 'El RUT ingresado no es válido'; end if;
  if length(btrim(coalesce(p_direccion,'')))<4 then raise exception 'Ingresa una dirección válida'; end if;
  if length(btrim(coalesce(p_finalidad,'')))<3 then raise exception 'Indica la finalidad del certificado'; end if;

  if p_origen='portal_socio' then
    v_socio:=public.portal_socio_validar_sesion(p_token);
    if v_socio is null then raise exception 'La sesión del Portal Socio venció'; end if;
  end if;

  select coalesce(valor_certificado,1000) into v_valor from public.configuracion_gestion where id=1;
  perform pg_advisory_xact_lock(73472026);
  select coalesce(max(coalesce(ce.folio,ce.numero)),0)+1 into v_folio from public.certificados_emitidos ce;

  insert into public.certificados_emitidos(
    folio,socio_id,nombre,rut,nacionalidad,direccion,finalidad,finalidad_otro,destino,
    tipo,fecha,valor,es_socio,estado_documento,estado_pago,telefono,correo,
    origen_solicitud,solicitado_en,observaciones
  ) values(
    v_folio,v_socio,btrim(p_nombre),v_rut,nullif(btrim(coalesce(p_nacionalidad,'')),''),btrim(p_direccion),
    'otro',btrim(p_finalidad),btrim(p_finalidad),'Residencia',current_date,v_valor,v_socio is not null,
    'pendiente_emision','pendiente',nullif(btrim(coalesce(p_telefono,'')),''),nullif(lower(btrim(coalesce(p_correo,''))),''),
    p_origen,now(),'Solicitud recibida desde '||case when p_origen='portal_socio' then 'Portal Socio' else 'Portal público' end
  ) returning id into v_id;

  return query select v_id,v_folio,v_rut,v_valor;
end $$;
revoke all on function public.solicitar_certificado_residencia(text,text,text,text,text,text,text,text,text) from public;
grant execute on function public.solicitar_certificado_residencia(text,text,text,text,text,text,text,text,text) to anon,authenticated;

-- 2) Beneficios: versión sin referencias ambiguas y sin contar usos revertidos.
create or replace function public.evaluar_beneficios_socio(p_socio_id uuid,p_fecha date,p_valor_original numeric)
returns table(beneficio_id uuid,nombre text,tipo text,cumple boolean,motivo text,detalle text,valor_final numeric)
language plpgsql security definer set search_path=public as $$
declare b public.beneficios_config%rowtype; v_pagadas integer; v_deuda integer; v_usados integer; v_anio integer:=extract(year from p_fecha);
begin
  select count(*) into v_pagadas from public.cuotas_socios cs where cs.socio_id=p_socio_id and cs.estado='pagado' and extract(year from cs.periodo)=v_anio;
  select count(*) into v_deuda from public.cuotas_socios cs where cs.socio_id=p_socio_id and cs.estado='pendiente' and cs.periodo<date_trunc('month',p_fecha)::date;
  for b in select bc.* from public.beneficios_config bc where bc.activo and (bc.vigencia_desde is null or bc.vigencia_desde<=p_fecha) and (bc.vigencia_hasta is null or bc.vigencia_hasta>=p_fecha) order by bc.prioridad loop
    select count(*) into v_usados from public.beneficios_usos bu where bu.socio_id=p_socio_id and bu.beneficio_id=b.id and bu.anio=v_anio and coalesce(bu.estado,'aplicado')='aplicado';
    beneficio_id:=b.id; nombre:=b.nombre; tipo:=b.tipo;
    cumple:=v_pagadas>=b.cuotas_minimas and (not b.exigir_sin_deuda or v_deuda=0) and v_usados<b.usos_maximos_anuales;
    motivo:=case when v_pagadas<b.cuotas_minimas then 'Tiene '||v_pagadas||' de '||b.cuotas_minimas||' cuotas requeridas.' when b.exigir_sin_deuda and v_deuda>0 then 'Mantiene '||v_deuda||' cuota(s) vencida(s).' when v_usados>=b.usos_maximos_anuales then 'Ya utilizó este beneficio durante el año.' else 'Cumple los requisitos.' end;
    detalle:=v_pagadas||' cuotas pagadas en '||v_anio||case when b.tipo='gratis' then ' · arriendo gratuito disponible' when b.tipo='porcentaje' then ' · '||b.valor||'% de descuento' else ' · descuento de $'||b.valor end;
    valor_final:=case when not cumple then p_valor_original when b.tipo='gratis' then 0 when b.tipo='porcentaje' then greatest(0,round(p_valor_original*(1-b.valor/100))) else greatest(0,p_valor_original-b.valor) end;
    return next;
  end loop;
end $$;
grant execute on function public.evaluar_beneficios_socio(uuid,date,numeric) to authenticated;

commit;
notify pgrst,'reload schema';
