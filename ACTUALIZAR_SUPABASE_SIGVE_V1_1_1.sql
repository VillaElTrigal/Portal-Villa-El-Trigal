-- SIGVE v1.1.1 · Certificados manuales, autoridades y firmas institucionales
-- Ejecutar una sola vez en Supabase SQL Editor.

begin;

-- Datos adicionales del certificado físico.
alter table public.certificados_emitidos
  add column if not exists nacionalidad text,
  add column if not exists finalidad text,
  add column if not exists finalidad_otro text,
  add column if not exists estado_documento text not null default 'emitido',
  add column if not exists actualizado_en timestamptz not null default now(),
  add column if not exists actualizado_por uuid references auth.users(id);

alter table public.certificados_emitidos drop constraint if exists certificados_estado_documento_check;
alter table public.certificados_emitidos add constraint certificados_estado_documento_check
  check (estado_documento in ('pendiente_emision','emitido','anulado'));

-- El folio sigue siendo único, pero ahora puede ingresarse manualmente.
create unique index if not exists certificados_folio_unique
  on public.certificados_emitidos(folio) where folio is not null;

-- Autoridades y firmas. La imagen se guarda como Data URL para no depender de un bucket.
create table if not exists public.autoridades_junta (
  id uuid primary key default gen_random_uuid(),
  cargo text not null,
  nombre_completo text not null,
  periodo_desde date,
  periodo_hasta date,
  firma_data_url text,
  telefono text,
  correo text,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  creado_por uuid references auth.users(id),
  actualizado_en timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  check (cargo in ('presidente','secretario','tesorero','otro'))
);

create unique index if not exists autoridades_cargo_activo_unique
  on public.autoridades_junta(cargo) where activo=true and cargo in ('presidente','secretario','tesorero');

alter table public.autoridades_junta enable row level security;
drop policy if exists autoridades_admin_select on public.autoridades_junta;
drop policy if exists autoridades_admin_all on public.autoridades_junta;
create policy autoridades_admin_select on public.autoridades_junta for select to authenticated
  using (public.es_admin());
create policy autoridades_admin_all on public.autoridades_junta for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

create table if not exists public.configuracion_documentos (
  id integer primary key default 1 check (id=1),
  certificado_digital_habilitado boolean not null default false,
  firma_presidente boolean not null default true,
  firma_secretario boolean not null default true,
  firma_tesorero boolean not null default false,
  actualizado_en timestamptz not null default now(),
  actualizado_por uuid references auth.users(id)
);
insert into public.configuracion_documentos(id) values(1) on conflict(id) do nothing;
alter table public.configuracion_documentos enable row level security;
drop policy if exists config_documentos_admin_select on public.configuracion_documentos;
drop policy if exists config_documentos_admin_all on public.configuracion_documentos;
create policy config_documentos_admin_select on public.configuracion_documentos for select to authenticated
  using (public.es_admin());
create policy config_documentos_admin_all on public.configuracion_documentos for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

-- Registra un certificado con folio manual. Crea el movimiento solo si se paga.
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
declare v_id uuid; v_mov uuid;
begin
  if not public.es_admin() then raise exception 'Acceso denegado'; end if;
  if p_folio is null or p_folio <= 0 then raise exception 'Debes ingresar un folio válido'; end if;
  if exists(select 1 from public.certificados_emitidos where folio=p_folio) then
    raise exception 'El folio % ya está registrado', p_folio;
  end if;
  if p_estado_documento not in ('pendiente_emision','emitido','anulado') then raise exception 'Estado documental inválido'; end if;
  if p_estado_pago not in ('pagado','pendiente','exento','anulado') then raise exception 'Estado de pago inválido'; end if;
  if p_estado_pago='pagado' and (p_medio not in ('efectivo','transferencia') or p_fondo not in ('caja','banco')) then
    raise exception 'Indica medio de pago y fondo';
  end if;

  insert into public.certificados_emitidos(
    folio,socio_id,nombre,rut,nacionalidad,direccion,finalidad,finalidad_otro,
    destino,tipo,fecha,valor,es_socio,estado_documento,estado_pago,medio_pago,
    fondo,referencia_transferencia,observaciones,creado_por,actualizado_por
  ) values(
    p_folio,p_socio_id,btrim(p_nombre),btrim(p_rut),nullif(btrim(coalesce(p_nacionalidad,'')),''),
    btrim(p_direccion),p_finalidad,nullif(btrim(coalesce(p_finalidad_otro,'')),''),
    case when p_finalidad='otro' then nullif(btrim(coalesce(p_finalidad_otro,'')),'') else p_finalidad end,
    'Residencia',p_fecha,p_valor,p_socio_id is not null,p_estado_documento,p_estado_pago,
    case when p_estado_pago='pagado' then p_medio end,
    case when p_estado_pago='pagado' then p_fondo end,
    nullif(btrim(coalesce(p_referencia,'')),''),nullif(btrim(coalesce(p_observaciones,'')),''),
    auth.uid(),auth.uid()
  ) returning id into v_id;

  if p_estado_pago='pagado' then
    insert into public.movimientos_financieros(
      fecha,tipo,concepto,categoria,monto,fondo,socio_id,sin_respaldo,
      observaciones,creado_por,origen_modulo,origen_id
    ) values(
      p_fecha,'ingreso','Pago certificado de residencia - Folio N° '||lpad(p_folio::text,5,'0'),
      'Certificados de residencia',p_valor,p_fondo,p_socio_id,true,p_observaciones,
      auth.uid(),'certificado',v_id
    ) returning id into v_mov;
    update public.certificados_emitidos set movimiento_id=v_mov where id=v_id;
  end if;

  insert into public.auditoria_financiera(entidad,entidad_id,accion,detalle,usuario_id)
  values('certificado',v_id,'registrado_manual',jsonb_build_object('folio',p_folio,'estado_pago',p_estado_pago),auth.uid());
  return v_id;
end;
$$;

-- Edita el certificado y sincroniza el movimiento sin duplicarlo.
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
declare c public.certificados_emitidos%rowtype; v_mov uuid;
begin
  if not public.es_admin() then raise exception 'Acceso denegado'; end if;
  select * into c from public.certificados_emitidos where id=p_id for update;
  if not found then raise exception 'Certificado no encontrado'; end if;
  if exists(select 1 from public.certificados_emitidos where folio=p_folio and id<>p_id) then
    raise exception 'El folio % ya está registrado', p_folio;
  end if;
  if p_estado_documento not in ('pendiente_emision','emitido','anulado') then raise exception 'Estado documental inválido'; end if;
  if p_estado_pago not in ('pagado','pendiente','exento','anulado') then raise exception 'Estado de pago inválido'; end if;

  -- Si pasa a pagado y aún no tiene movimiento, se crea una sola vez.
  if p_estado_pago='pagado' and c.movimiento_id is null then
    if p_medio not in ('efectivo','transferencia') or p_fondo not in ('caja','banco') then raise exception 'Indica medio de pago y fondo'; end if;
    insert into public.movimientos_financieros(
      fecha,tipo,concepto,categoria,monto,fondo,socio_id,sin_respaldo,
      observaciones,creado_por,origen_modulo,origen_id
    ) values(
      p_fecha,'ingreso','Pago certificado de residencia - Folio N° '||lpad(p_folio::text,5,'0'),
      'Certificados de residencia',p_valor,p_fondo,c.socio_id,true,p_observaciones,
      auth.uid(),'certificado',p_id
    ) returning id into v_mov;
  elsif p_estado_pago='pagado' and c.movimiento_id is not null then
    v_mov:=c.movimiento_id;
    update public.movimientos_financieros set
      fecha=p_fecha,
      concepto='Pago certificado de residencia - Folio N° '||lpad(p_folio::text,5,'0'),
      monto=p_valor,
      fondo=p_fondo,
      observaciones=p_observaciones,
      anulado=false,
      anulado_en=null,
      anulado_por=null
    where id=v_mov;
  elsif p_estado_pago<>'pagado' and c.movimiento_id is not null then
    update public.movimientos_financieros set anulado=true,anulado_en=now(),anulado_por=auth.uid(),
      observaciones=concat_ws(' · ',observaciones,'ANULADO POR CAMBIO DE ESTADO DEL CERTIFICADO')
    where id=c.movimiento_id;
    v_mov:=null;
  end if;

  update public.certificados_emitidos set
    folio=p_folio,nombre=btrim(p_nombre),rut=btrim(p_rut),nacionalidad=nullif(btrim(coalesce(p_nacionalidad,'')),''),
    direccion=btrim(p_direccion),finalidad=p_finalidad,finalidad_otro=nullif(btrim(coalesce(p_finalidad_otro,'')),''),
    destino=case when p_finalidad='otro' then nullif(btrim(coalesce(p_finalidad_otro,'')),'') else p_finalidad end,
    fecha=p_fecha,valor=p_valor,estado_documento=p_estado_documento,estado_pago=p_estado_pago,
    medio_pago=case when p_estado_pago='pagado' then p_medio end,
    fondo=case when p_estado_pago='pagado' then p_fondo end,
    referencia_transferencia=nullif(btrim(coalesce(p_referencia,'')),''),
    observaciones=nullif(btrim(coalesce(p_observaciones,'')),''),movimiento_id=v_mov,
    actualizado_en=now(),actualizado_por=auth.uid()
  where id=p_id;

  insert into public.auditoria_financiera(entidad,entidad_id,accion,detalle,usuario_id)
  values('certificado',p_id,'actualizado',jsonb_build_object('folio',p_folio,'estado_pago',p_estado_pago),auth.uid());
  return true;
end;
$$;

commit;
