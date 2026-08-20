-- SIGVE v7.5.0 · Pago de cuotas en efectivo
begin;
create table if not exists public.solicitudes_pago_efectivo(
 id uuid primary key default gen_random_uuid(), socio_id uuid not null references public.socios(id) on delete cascade,
 cuota_ids uuid[] not null, monto_total numeric(12,0) not null,
 estado text not null default 'pendiente' check(estado in('pendiente','completada','cancelada')),
 creada_en timestamptz not null default now(), completada_en timestamptz, completada_por uuid);
alter table public.solicitudes_pago_efectivo enable row level security;
drop policy if exists "Admin gestiona solicitudes efectivo" on public.solicitudes_pago_efectivo;
create policy "Admin gestiona solicitudes efectivo" on public.solicitudes_pago_efectivo for all to authenticated
using(public.es_admin()) with check(public.es_admin());
revoke all on public.solicitudes_pago_efectivo from anon;
grant select,update on public.solicitudes_pago_efectivo to authenticated;

create or replace function public.portal_socio_solicitar_pago_efectivo(p_token text,p_cuota_ids uuid[])
returns table(solicitud_id uuid,monto_total numeric,cuotas integer)
language plpgsql security definer set search_path=public as $$
declare v_socio uuid;v_total numeric;v_count integer;v_id uuid;
begin
 v_socio:=public.portal_socio_validar_sesion(p_token);
 if v_socio is null then raise exception 'Sesión inválida o vencida';end if;
 if coalesce(array_length(p_cuota_ids,1),0)=0 then raise exception 'Selecciona al menos una cuota';end if;
 select count(*),coalesce(sum(monto),0) into v_count,v_total from public.cuotas_socios
 where id=any(p_cuota_ids) and socio_id=v_socio and estado='pendiente';
 if v_count<>array_length(p_cuota_ids,1) then raise exception 'Una o más cuotas no están disponibles';end if;
 select id into v_id from public.solicitudes_pago_efectivo where socio_id=v_socio and estado='pendiente'
 and cuota_ids @> p_cuota_ids and p_cuota_ids @> cuota_ids order by creada_en desc limit 1;
 if v_id is null then insert into public.solicitudes_pago_efectivo(socio_id,cuota_ids,monto_total)
 values(v_socio,p_cuota_ids,v_total) returning id into v_id;end if;
 return query select v_id,v_total,v_count;
end;$$;
revoke all on function public.portal_socio_solicitar_pago_efectivo(text,uuid[]) from public;
grant execute on function public.portal_socio_solicitar_pago_efectivo(text,uuid[]) to anon,authenticated;

create or replace function public.registrar_pago_cuotas_caja(
 p_cuota_ids uuid[],p_fecha date,p_medio text,p_fondo text,p_referencia text default null,p_observaciones text default null)
returns integer language plpgsql security definer set search_path=public as $$
declare v_id uuid;v_count integer:=0;v_socio uuid;v_actual uuid;
begin
 if not public.es_admin() then raise exception 'Acceso denegado';end if;
 if coalesce(array_length(p_cuota_ids,1),0)=0 then raise exception 'Selecciona al menos una cuota';end if;
 if p_medio not in('efectivo','transferencia') then raise exception 'Medio de pago inválido';end if;
 if p_fondo not in('caja','banco') then raise exception 'Fondo inválido';end if;
 if p_medio='efectivo' and p_fondo<>'caja' then raise exception 'El efectivo debe ingresar a Caja chica';end if;
 if p_medio='transferencia' and p_fondo<>'banco' then raise exception 'La transferencia debe ingresar a Cuenta bancaria';end if;
 foreach v_id in array p_cuota_ids loop
  select socio_id into v_actual from public.cuotas_socios where id=v_id for update;
  if v_actual is null then raise exception 'Cuota no encontrada';end if;
  if v_socio is null then v_socio:=v_actual;elsif v_socio<>v_actual then raise exception 'Todas las cuotas deben pertenecer al mismo socio';end if;
  perform public.registrar_pago_cuota(v_id,p_fecha,p_medio,p_fondo,p_referencia,p_observaciones);v_count:=v_count+1;
 end loop;
 if p_medio='efectivo' then update public.solicitudes_pago_efectivo s
 set estado='completada',completada_en=now(),completada_por=auth.uid()
 where s.socio_id=v_socio and s.estado='pendiente'
 and not exists(select 1 from public.cuotas_socios c where c.id=any(s.cuota_ids) and c.estado='pendiente');end if;
 return v_count;
end;$$;
grant execute on function public.registrar_pago_cuotas_caja(uuid[],date,text,text,text,text) to authenticated;
commit;