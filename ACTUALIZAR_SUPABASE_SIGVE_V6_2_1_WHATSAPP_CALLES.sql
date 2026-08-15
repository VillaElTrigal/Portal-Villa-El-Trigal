-- SIGVE v6.2.1 - Grupos WhatsApp por calle
-- Ejecutar completo en Supabase > SQL Editor.
begin;
create table if not exists public.vias_whatsapp (
 via_id uuid primary key references public.vias(id) on delete cascade,
 nombre_grupo text, enlace_invitacion text, activo boolean not null default true,
 actualizado_en timestamptz not null default now(), actualizado_por uuid
);
alter table public.vias_whatsapp enable row level security;
drop policy if exists "Administradores gestionan WhatsApp calles" on public.vias_whatsapp;
create policy "Administradores gestionan WhatsApp calles" on public.vias_whatsapp
for all to authenticated using (public.es_admin()) with check (public.es_admin());
revoke all on public.vias_whatsapp from anon;
grant select,insert,update,delete on public.vias_whatsapp to authenticated;

create or replace function public.portal_socio_grupo_whatsapp(p_token text)
returns table(via_id uuid,via_nombre text,nombre_grupo text,enlace_invitacion text)
language plpgsql security definer set search_path=public as $$
declare v_socio uuid;
begin
 v_socio:=public.portal_socio_validar_sesion(p_token);
 if v_socio is null then return; end if;
 return query select v.id,concat_ws(' ',nullif(v.tipo,''),v.nombre)::text,
 coalesce(nullif(w.nombre_grupo,''),concat('Vecinos - ',v.nombre))::text,w.enlace_invitacion::text
 from public.socios s join public.vias v on v.id=s.via_id
 join public.vias_whatsapp w on w.via_id=v.id
 where s.id=v_socio and s.estado='activo' and v.activa=true and w.activo=true
 and nullif(trim(w.enlace_invitacion),'') is not null limit 1;
end; $$;
revoke all on function public.portal_socio_grupo_whatsapp(text) from public;
grant execute on function public.portal_socio_grupo_whatsapp(text) to anon,authenticated;
commit;
