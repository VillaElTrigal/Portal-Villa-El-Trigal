-- PORTAL VILLA EL TRIGAL v8.0
-- Integración: Portal público -> Supabase -> Gestión de la Sede
-- Ejecutar UNA VEZ en Supabase > SQL Editor antes de publicar los archivos web.

begin;

-- Actividades y bloqueos no necesitan teléfono. Las solicitudes públicas sí lo validan en la función.
alter table public.reservas_sede alter column telefono drop not null;
create unique index if not exists reserva_fecha_unica_activa on public.reservas_sede(fecha_evento) where estado not in ('cancelado','archivado');
update public.reservas_sede set telefono=null where telefono='+56900000000' and tipo in ('zumba','actividad','bloqueo');

-- La función pública crea solicitudes sin permitir que el navegador decida valores o estados.
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
  valor_configurado numeric(12,0);
begin
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
    select 1 from public.reservas_sede
    where fecha_evento=p_fecha and estado not in ('cancelado','archivado')
  ) then
    raise exception 'La fecha ya no está disponible.';
  end if;
  select valor_arriendo into valor_configurado from public.configuracion_gestion where id=1;
  insert into public.reservas_sede(
    nombre_arrendatario,rut,telefono,fecha_evento,hora_inicio,hora_termino,
    tipo,descripcion,valor_total,estado,whatsapp_enviado
  ) values(
    left(btrim(p_nombre),120),nullif(btrim(p_rut),''),p_telefono,p_fecha,'08:00','22:00',
    'arriendo',nullif(left(btrim(p_observaciones),500),''),coalesce(valor_configurado,40000),'pendiente',true
  ) returning id into nuevo_id;
  return nuevo_id;
exception when unique_violation then
  raise exception 'La fecha ya no está disponible.';
end;
$$;
revoke all on function public.crear_solicitud_reserva(text,text,date,text,text) from public;
grant execute on function public.crear_solicitud_reserva(text,text,date,text,text) to anon,authenticated;

-- Vista pública sin datos personales.
drop view if exists public.reservas_publicas;
create view public.reservas_publicas as
select fecha_evento,tipo,
 case when tipo='actividad' then coalesce(descripcion,'Actividad comunitaria')
      when tipo='zumba' then 'Clase de Zumba'
      when tipo='bloqueo' then coalesce(descripcion,'Fecha no disponible')
      else 'Reservado' end as descripcion_publica
from public.reservas_sede
where estado not in ('cancelado','archivado');
grant select on public.reservas_publicas to anon,authenticated;

-- Migración idempotente de las ocho fechas del Excel entregado.
-- Como la planilla no incluye nombres ni teléfonos, se dejan marcadas para completar desde el panel.
insert into public.reservas_sede(nombre_arrendatario,telefono,fecha_evento,tipo,descripcion,valor_total,estado)
select 'Reserva migrada (completar datos)',null,v.fecha,'arriendo','Migración desde Excel · Actividad',
       coalesce((select valor_arriendo from public.configuracion_gestion where id=1),40000),'pendiente'
from (values
 ('2026-07-25'::date),('2026-07-26'::date),('2026-08-01'::date),('2026-08-15'::date),
 ('2026-08-19'::date),('2026-09-13'::date),('2026-10-17'::date),('2026-11-14'::date)
) as v(fecha)
where not exists(select 1 from public.reservas_sede r where r.fecha_evento=v.fecha and r.estado not in ('cancelado','archivado'));

-- Bloqueo recurrente de Zumba: martes y jueves, desde hoy hasta el 31-12-2026.
insert into public.reservas_sede(nombre_arrendatario,telefono,fecha_evento,hora_inicio,hora_termino,tipo,descripcion,valor_total,estado)
select 'Zumba',null,d::date,'18:00','22:00','zumba','Clase permanente de Zumba',0,'confirmado'
from generate_series(greatest(current_date,'2026-01-01'::date),'2026-12-31'::date,interval '1 day') d
where extract(isodow from d) in (2,4)
  and not exists(select 1 from public.reservas_sede r where r.fecha_evento=d::date and r.estado not in ('cancelado','archivado'));

commit;
notify pgrst,'reload schema';

-- Resumen de verificación.
select tipo,estado,count(*) as registros
from public.reservas_sede
group by tipo,estado
order by tipo,estado;
