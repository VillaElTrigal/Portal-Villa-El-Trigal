-- ============================================================
-- SIGVE v1.1.0 · Gestión Financiera Integrada
-- Junta de Vecinos Villa El Trigal
-- Ejecutar una vez en Supabase > SQL Editor.
-- No elimina información existente.
-- ============================================================

begin;
create extension if not exists pgcrypto;

-- Parámetros nuevos
alter table public.configuracion_gestion
  add column if not exists dia_limite_cobro_mes integer not null default 10,
  add column if not exists folio_inicial_certificado bigint not null default 209,
  add column if not exists nombre_organizacion text not null default 'Junta de Vecinos Villa El Trigal';

alter table public.configuracion_gestion drop constraint if exists configuracion_dia_limite_check;
alter table public.configuracion_gestion add constraint configuracion_dia_limite_check
  check (dia_limite_cobro_mes between 1 and 28);

-- Extensión segura de movimientos para trazabilidad automática
alter table public.movimientos_financieros
  add column if not exists origen_modulo text,
  add column if not exists origen_id uuid,
  add column if not exists anulado boolean not null default false,
  add column if not exists anulado_en timestamptz,
  add column if not exists anulado_por uuid references auth.users(id);

create unique index if not exists movimientos_origen_unico
  on public.movimientos_financieros(origen_modulo,origen_id)
  where origen_modulo is not null and origen_id is not null and anulado=false;

-- Cuotas mensuales
create table if not exists public.cuotas_socios (
  id uuid primary key default gen_random_uuid(),
  socio_id uuid not null references public.socios(id) on delete restrict,
  periodo date not null,
  estado text not null default 'pendiente'
    check (estado in ('pendiente','pagado','exento_incorporacion','anulado')),
  monto numeric(12,0) not null default 0 check (monto >= 0),
  fecha_pago date,
  medio_pago text check (medio_pago in ('efectivo','transferencia')),
  referencia_transferencia text,
  fondo text check (fondo in ('caja','banco')),
  movimiento_id uuid references public.movimientos_financieros(id) on delete set null,
  observaciones text,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  creado_por uuid references auth.users(id),
  actualizado_por uuid references auth.users(id),
  unique(socio_id,periodo),
  check (date_trunc('month',periodo)::date = periodo),
  check (
    (estado='pagado' and fecha_pago is not null and medio_pago is not null and fondo is not null and monto>0)
    or estado<>'pagado'
  )
);
create index if not exists cuotas_periodo_idx on public.cuotas_socios(periodo,estado);
create index if not exists cuotas_socio_idx on public.cuotas_socios(socio_id,periodo desc);

-- Certificados v1.1
alter table public.certificados_emitidos
  add column if not exists folio bigint,
  add column if not exists telefono text,
  add column if not exists correo text,
  add column if not exists destino text,
  add column if not exists es_socio boolean not null default false,
  add column if not exists estado_pago text not null default 'pendiente',
  add column if not exists medio_pago text,
  add column if not exists fondo text,
  add column if not exists referencia_transferencia text,
  add column if not exists anulado boolean not null default false,
  add column if not exists actualizado_en timestamptz not null default now(),
  add column if not exists actualizado_por uuid references auth.users(id);

update public.certificados_emitidos set folio=numero where folio is null and numero is not null;

alter table public.certificados_emitidos drop constraint if exists certificados_estado_pago_check;
alter table public.certificados_emitidos add constraint certificados_estado_pago_check
  check (estado_pago in ('pagado','pendiente','exento','anulado'));
alter table public.certificados_emitidos drop constraint if exists certificados_medio_pago_check;
alter table public.certificados_emitidos add constraint certificados_medio_pago_check
  check (medio_pago is null or medio_pago in ('efectivo','transferencia'));
alter table public.certificados_emitidos drop constraint if exists certificados_fondo_check;
alter table public.certificados_emitidos add constraint certificados_fondo_check
  check (fondo is null or fondo in ('caja','banco'));
create unique index if not exists certificados_folio_unique on public.certificados_emitidos(folio) where folio is not null;

-- Cierre financiero mensual
create table if not exists public.cierres_financieros (
  id uuid primary key default gen_random_uuid(),
  periodo date not null unique,
  cerrado_en timestamptz not null default now(),
  cerrado_por uuid references auth.users(id),
  reabierto_en timestamptz,
  reabierto_por uuid references auth.users(id),
  motivo_reapertura text,
  activo boolean not null default true,
  check (date_trunc('month',periodo)::date=periodo)
);

-- Auditoría financiera simple
create table if not exists public.auditoria_financiera (
  id bigint generated always as identity primary key,
  entidad text not null,
  entidad_id uuid,
  accion text not null,
  detalle jsonb not null default '{}'::jsonb,
  usuario_id uuid references auth.users(id),
  creado_en timestamptz not null default now()
);

-- Folio certificado: comienza como mínimo en 209 y respeta datos históricos.
create sequence if not exists public.certificados_folio_seq;
select setval(
  'public.certificados_folio_seq',
  greatest(208,coalesce((select max(folio) from public.certificados_emitidos),0)),
  true
);
alter table public.certificados_emitidos alter column folio set default nextval('public.certificados_folio_seq');

-- Genera el calendario de cuotas del mes para todos los socios activos.
create or replace function public.generar_cuotas_mes(p_periodo date)
returns integer
language plpgsql security definer set search_path=public
as $$
declare
  v_periodo date := date_trunc('month',p_periodo)::date;
  v_valor numeric(12,0);
  v_limite integer;
  v_count integer;
begin
  if not public.es_admin() then raise exception 'Acceso denegado'; end if;
  select valor_cuota,dia_limite_cobro_mes into v_valor,v_limite
  from public.configuracion_gestion where id=1;

  insert into public.cuotas_socios(socio_id,periodo,estado,monto,creado_por)
  select s.id,v_periodo,
    case
      when date_trunc('month',s.fecha_ingreso)::date=v_periodo
       and extract(day from s.fecha_ingreso)::integer>v_limite
      then 'exento_incorporacion' else 'pendiente' end,
    case
      when date_trunc('month',s.fecha_ingreso)::date=v_periodo
       and extract(day from s.fecha_ingreso)::integer>v_limite
      then 0 else v_valor end,
    auth.uid()
  from public.socios s
  where s.estado='activo'
    and s.fecha_ingreso <= (v_periodo + interval '1 month - 1 day')::date
  on conflict(socio_id,periodo) do nothing;
  get diagnostics v_count=row_count;
  return v_count;
end;
$$;

-- Paga una cuota y crea el ingreso financiero en una sola transacción.
create or replace function public.registrar_pago_cuota(
  p_cuota_id uuid,p_fecha date,p_medio text,p_fondo text,
  p_referencia text default null,p_observaciones text default null
) returns uuid
language plpgsql security definer set search_path=public
as $$
declare c public.cuotas_socios%rowtype; s public.socios%rowtype; v_mov uuid;
begin
  if not public.es_admin() then raise exception 'Acceso denegado'; end if;
  select * into c from public.cuotas_socios where id=p_cuota_id for update;
  if not found then raise exception 'Cuota no encontrada'; end if;
  if c.estado='pagado' then raise exception 'La cuota ya está pagada'; end if;
  if c.estado='exento_incorporacion' then raise exception 'La cuota está exenta por incorporación'; end if;
  if exists(select 1 from public.cierres_financieros where periodo=c.periodo and activo=true) then
    raise exception 'El mes financiero está cerrado';
  end if;
  if p_medio not in ('efectivo','transferencia') then raise exception 'Medio de pago inválido'; end if;
  if p_fondo not in ('caja','banco') then raise exception 'Fondo inválido'; end if;
  select * into s from public.socios where id=c.socio_id;
  insert into public.movimientos_financieros(
    fecha,tipo,concepto,categoria,monto,fondo,socio_id,sin_respaldo,
    observaciones,creado_por,origen_modulo,origen_id
  ) values(
    p_fecha,'ingreso','Cuota socio N° '||coalesce(s.numero_socio::text,'—')||' · '||s.nombre_completo,
    'Cuotas de socios',c.monto,p_fondo,c.socio_id,true,p_observaciones,auth.uid(),'cuota',c.id
  ) returning id into v_mov;
  update public.cuotas_socios set estado='pagado',fecha_pago=p_fecha,medio_pago=p_medio,
    fondo=p_fondo,referencia_transferencia=nullif(btrim(coalesce(p_referencia,'')),''),
    observaciones=nullif(btrim(coalesce(p_observaciones,'')),''),movimiento_id=v_mov,
    actualizado_en=now(),actualizado_por=auth.uid() where id=c.id;
  insert into public.auditoria_financiera(entidad,entidad_id,accion,detalle,usuario_id)
    values('cuota',c.id,'pago_registrado',jsonb_build_object('movimiento_id',v_mov,'monto',c.monto),auth.uid());
  return v_mov;
end;
$$;

create or replace function public.anular_pago_cuota(p_cuota_id uuid,p_motivo text)
returns boolean language plpgsql security definer set search_path=public
as $$
declare c public.cuotas_socios%rowtype;
begin
  if not public.es_admin() then raise exception 'Acceso denegado'; end if;
  select * into c from public.cuotas_socios where id=p_cuota_id for update;
  if not found or c.estado<>'pagado' then raise exception 'La cuota no tiene un pago activo'; end if;
  if exists(select 1 from public.cierres_financieros where periodo=c.periodo and activo=true) then
    raise exception 'El mes financiero está cerrado';
  end if;
  update public.movimientos_financieros set anulado=true,anulado_en=now(),anulado_por=auth.uid(),
    observaciones=concat_ws(' · ',observaciones,'ANULADO: '||coalesce(p_motivo,'Sin motivo'))
    where id=c.movimiento_id;
  update public.cuotas_socios set estado='pendiente',fecha_pago=null,medio_pago=null,fondo=null,
    referencia_transferencia=null,movimiento_id=null,actualizado_en=now(),actualizado_por=auth.uid()
    where id=c.id;
  insert into public.auditoria_financiera(entidad,entidad_id,accion,detalle,usuario_id)
    values('cuota',c.id,'pago_anulado',jsonb_build_object('motivo',p_motivo),auth.uid());
  return true;
end;
$$;

-- Certificado + ingreso automático cuando corresponde.
create or replace function public.registrar_certificado_v110(
  p_socio_id uuid,p_nombre text,p_rut text,p_direccion text,p_telefono text,p_correo text,
  p_destino text,p_fecha date,p_estado_pago text,p_medio text,p_fondo text,
  p_referencia text,p_observaciones text
) returns bigint
language plpgsql security definer set search_path=public
as $$
declare v_id uuid; v_folio bigint; v_valor numeric(12,0); v_mov uuid;
begin
  if not public.es_admin() then raise exception 'Acceso denegado'; end if;
  select valor_certificado into v_valor from public.configuracion_gestion where id=1;
  if p_estado_pago not in ('pagado','pendiente','exento') then raise exception 'Estado de pago inválido'; end if;
  if p_estado_pago='pagado' and (p_medio not in('efectivo','transferencia') or p_fondo not in('caja','banco')) then
    raise exception 'Indica medio de pago y fondo';
  end if;
  insert into public.certificados_emitidos(
    socio_id,nombre,rut,direccion,telefono,correo,destino,tipo,fecha,valor,
    es_socio,estado_pago,medio_pago,fondo,referencia_transferencia,observaciones,creado_por
  ) values(
    p_socio_id,btrim(p_nombre),btrim(p_rut),btrim(p_direccion),nullif(btrim(coalesce(p_telefono,'')),''),
    nullif(btrim(coalesce(p_correo,'')),''),nullif(btrim(coalesce(p_destino,'')),''),'Residencia',p_fecha,v_valor,
    p_socio_id is not null,p_estado_pago,case when p_estado_pago='pagado' then p_medio end,
    case when p_estado_pago='pagado' then p_fondo end,nullif(btrim(coalesce(p_referencia,'')),''),
    nullif(btrim(coalesce(p_observaciones,'')),''),auth.uid()
  ) returning id,folio into v_id,v_folio;
  if p_estado_pago='pagado' then
    insert into public.movimientos_financieros(fecha,tipo,concepto,categoria,monto,fondo,socio_id,
      sin_respaldo,observaciones,creado_por,origen_modulo,origen_id)
    values(p_fecha,'ingreso','Certificado de residencia folio '||lpad(v_folio::text,5,'0'),
      'Certificados de residencia',v_valor,p_fondo,p_socio_id,true,p_observaciones,auth.uid(),'certificado',v_id)
    returning id into v_mov;
    update public.certificados_emitidos set movimiento_id=v_mov where id=v_id;
  end if;
  insert into public.auditoria_financiera(entidad,entidad_id,accion,detalle,usuario_id)
    values('certificado',v_id,'emitido',jsonb_build_object('folio',v_folio,'estado_pago',p_estado_pago),auth.uid());
  return v_folio;
end;
$$;

-- Vista Libro de Caja: excluye movimientos anulados y calcula saldo corrido global.
create or replace view public.libro_caja as
select m.*,
  sum(case when m.tipo='ingreso' then m.monto when m.tipo='gasto' then -m.monto else 0 end)
    over(order by m.fecha,m.creado_en,m.id rows unbounded preceding) as saldo_acumulado
from public.movimientos_financieros m
where coalesce(m.anulado,false)=false and m.tipo in ('ingreso','gasto');

-- RLS
alter table public.cuotas_socios enable row level security;
alter table public.cierres_financieros enable row level security;
alter table public.auditoria_financiera enable row level security;

do $$ declare t text; begin
 foreach t in array array['cuotas_socios','cierres_financieros','auditoria_financiera'] loop
  execute format('drop policy if exists "Admin gestiona %s" on public.%I',t,t);
  execute format('create policy "Admin gestiona %s" on public.%I for all to authenticated using (public.es_admin()) with check (public.es_admin())',t,t);
 end loop;
end $$;

grant select on public.libro_caja to authenticated;
grant execute on function public.generar_cuotas_mes(date) to authenticated;
grant execute on function public.registrar_pago_cuota(uuid,date,text,text,text,text) to authenticated;
grant execute on function public.anular_pago_cuota(uuid,text) to authenticated;
grant execute on function public.registrar_certificado_v110(uuid,text,text,text,text,text,text,date,text,text,text,text,text) to authenticated;

commit;
