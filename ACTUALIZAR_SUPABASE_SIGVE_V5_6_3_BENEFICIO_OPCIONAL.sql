-- SIGVE v5.6.3 · Beneficio opcional en arriendo Portal Socio
-- Ejecutar completo en Supabase > SQL Editor.
-- Objetivo: la solicitud puede indicar un beneficio, pero el uso se consume solo al confirmar la reserva.

begin;

alter table public.reservas_sede
  add column if not exists beneficio_solicitado_id uuid references public.beneficios_config(id),
  add column if not exists beneficio_confirmado_id uuid references public.beneficios_config(id);

-- Función auxiliar: confirmar el uso de un beneficio solo cuando Administración confirma la reserva.
create or replace function public.confirmar_beneficio_reserva(p_reserva_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  r record;
  v_anio integer;
begin
  select rs.id,rs.socio_id,rs.fecha_evento,rs.beneficio_solicitado_id,rs.beneficio_confirmado_id
    into r
  from public.reservas_sede rs
  where rs.id=p_reserva_id
  for update;

  if r.id is null or r.socio_id is null or r.beneficio_solicitado_id is null then
    return;
  end if;

  if r.beneficio_confirmado_id is not null then
    return;
  end if;

  v_anio:=extract(year from r.fecha_evento);

  insert into public.beneficios_usos(
    socio_id,beneficio_id,anio,fecha_uso,estado,reserva_id
  )
  values(
    r.socio_id,r.beneficio_solicitado_id,v_anio,r.fecha_evento,'aplicado',r.id
  )
  on conflict do nothing;

  update public.reservas_sede
  set beneficio_confirmado_id=r.beneficio_solicitado_id
  where id=r.id;
end
$$;

grant execute on function public.confirmar_beneficio_reserva(uuid) to authenticated;

commit;
