-- SIGVE v5.0.0 · Programa de Beneficios
-- Ejecutar completo en Supabase > SQL Editor.

create extension if not exists pgcrypto;

create table if not exists public.beneficios_config (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nombre text not null,
  descripcion text,
  activo boolean not null default true,
  cuotas_minimas integer not null default 6 check (cuotas_minimas between 0 and 12),
  exigir_sin_deuda boolean not null default true,
  tipo text not null check (tipo in ('porcentaje','fijo','gratis')),
  valor numeric(12,2) not null default 0,
  usos_maximos_anuales integer not null default 999,
  prioridad integer not null default 100,
  acuerdo_directiva text,
  vigencia_desde date,
  vigencia_hasta date,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

insert into public.beneficios_config(codigo,nombre,descripcion,cuotas_minimas,exigir_sin_deuda,tipo,valor,usos_maximos_anuales,prioridad)
values
 ('SOCIO_CUMPLIDOR','Beneficio Socio Cumplidor','Descuento en el arriendo de la sede para socios que mantienen sus cuotas al día.',6,true,'porcentaje',25,999,20),
 ('ARRIENDO_GRATIS','Arriendo Gratuito Anual','Un arriendo gratuito de la sede por año para socios que cumplen el requisito anual.',12,true,'gratis',0,1,10)
on conflict (codigo) do nothing;

alter table public.reservas_sede add column if not exists socio_id uuid references public.socios(id);
alter table public.reservas_sede add column if not exists beneficio_id uuid references public.beneficios_config(id);
alter table public.reservas_sede add column if not exists beneficio_nombre text;
alter table public.reservas_sede add column if not exists valor_original numeric(12,2);
alter table public.reservas_sede add column if not exists descuento_aplicado numeric(12,2) not null default 0;

create table if not exists public.beneficios_usos (
 id uuid primary key default gen_random_uuid(),
 beneficio_id uuid not null references public.beneficios_config(id),
 beneficio_nombre text not null,
 socio_id uuid not null references public.socios(id),
 reserva_id uuid not null references public.reservas_sede(id),
 anio integer not null,
 valor_original numeric(12,2) not null default 0,
 valor_final numeric(12,2) not null default 0,
 descuento numeric(12,2) not null default 0,
 creado_en timestamptz not null default now(),
 unique(reserva_id, beneficio_id)
);

alter table public.beneficios_config enable row level security;
alter table public.beneficios_usos enable row level security;
drop policy if exists "beneficios autenticados" on public.beneficios_config;
create policy "beneficios autenticados" on public.beneficios_config for all to authenticated using (true) with check (true);
drop policy if exists "usos autenticados" on public.beneficios_usos;
create policy "usos autenticados" on public.beneficios_usos for all to authenticated using (true) with check (true);

grant select,insert,update,delete on public.beneficios_config to authenticated;
grant select,insert,update,delete on public.beneficios_usos to authenticated;

create or replace function public.evaluar_beneficios_socio(p_socio_id uuid,p_fecha date,p_valor_original numeric)
returns table(beneficio_id uuid,nombre text,tipo text,cumple boolean,motivo text,detalle text,valor_final numeric)
language plpgsql security definer set search_path=public as $$
declare b record; pagadas integer; deuda integer; usados integer; a integer:=extract(year from p_fecha);
begin
 select count(*) into pagadas from cuotas_socios where socio_id=p_socio_id and estado='pagado' and extract(year from periodo)=a;
 select count(*) into deuda from cuotas_socios where socio_id=p_socio_id and estado='pendiente' and periodo < date_trunc('month',p_fecha)::date;
 for b in select * from beneficios_config where activo and (vigencia_desde is null or vigencia_desde<=p_fecha) and (vigencia_hasta is null or vigencia_hasta>=p_fecha) order by prioridad asc loop
  select count(*) into usados from beneficios_usos where socio_id=p_socio_id and beneficio_id=b.id and anio=a;
  beneficio_id:=b.id; nombre:=b.nombre; tipo:=b.tipo;
  cumple:=pagadas>=b.cuotas_minimas and (not b.exigir_sin_deuda or deuda=0) and usados<b.usos_maximos_anuales;
  motivo:=case when pagadas<b.cuotas_minimas then 'Tiene '||pagadas||' de '||b.cuotas_minimas||' cuotas requeridas.' when b.exigir_sin_deuda and deuda>0 then 'Mantiene '||deuda||' cuota(s) vencida(s).' when usados>=b.usos_maximos_anuales then 'Ya utilizó este beneficio durante el año.' else 'Cumple los requisitos.' end;
  detalle:=pagadas||' cuotas pagadas en '||a||case when b.tipo='gratis' then ' · arriendo gratuito disponible' when b.tipo='porcentaje' then ' · '||b.valor||'% de descuento' else ' · descuento de $'||b.valor end;
  valor_final:=case when not cumple then p_valor_original when b.tipo='gratis' then 0 when b.tipo='porcentaje' then greatest(0,round(p_valor_original*(1-b.valor/100))) else greatest(0,p_valor_original-b.valor) end;
  return next;
 end loop;
end $$;

grant execute on function public.evaluar_beneficios_socio(uuid,date,numeric) to authenticated;

create or replace function public.registrar_uso_beneficio(p_reserva_id uuid,p_socio_id uuid,p_beneficio_id uuid,p_valor_original numeric,p_valor_final numeric)
returns uuid language plpgsql security definer set search_path=public as $$
declare b beneficios_config%rowtype; rid uuid; fecha date;
begin
 select * into b from beneficios_config where id=p_beneficio_id and activo;
 if not found then raise exception 'Beneficio no disponible'; end if;
 select fecha_evento into fecha from reservas_sede where id=p_reserva_id;
 insert into beneficios_usos(beneficio_id,beneficio_nombre,socio_id,reserva_id,anio,valor_original,valor_final,descuento)
 values(b.id,b.nombre,p_socio_id,p_reserva_id,extract(year from fecha),p_valor_original,p_valor_final,greatest(0,p_valor_original-p_valor_final))
 on conflict(reserva_id,beneficio_id) do update set valor_original=excluded.valor_original,valor_final=excluded.valor_final,descuento=excluded.descuento
 returning id into rid;
 update reservas_sede set socio_id=p_socio_id,beneficio_id=b.id,beneficio_nombre=b.nombre,valor_original=p_valor_original,descuento_aplicado=greatest(0,p_valor_original-p_valor_final) where id=p_reserva_id;
 return rid;
end $$;
grant execute on function public.registrar_uso_beneficio(uuid,uuid,uuid,numeric,numeric) to authenticated;
