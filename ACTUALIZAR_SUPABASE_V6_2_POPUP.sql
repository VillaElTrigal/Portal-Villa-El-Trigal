-- Portal Villa El Trigal v6.2 - Aviso emergente administrable
create table if not exists public.avisos_popup (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  mensaje text not null,
  tipo text not null default 'informativo' check (tipo in ('informativo','actividad','importante','emergencia')),
  imagen_url text,
  fecha_inicio date not null default current_date,
  fecha_termino date not null default (current_date + 7),
  boton_texto text,
  boton_url text,
  mostrar_una_vez boolean not null default true,
  activo boolean not null default true,
  creado_por uuid references auth.users(id),
  actualizado_por uuid references auth.users(id),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint avisos_popup_fechas_validas check (fecha_termino >= fecha_inicio)
);

alter table public.avisos_popup enable row level security;

drop policy if exists "Avisos popup públicos vigentes" on public.avisos_popup;
create policy "Avisos popup públicos vigentes" on public.avisos_popup
for select to anon, authenticated
using (activo = true and fecha_inicio <= current_date and fecha_termino >= current_date);

drop policy if exists "Administradores gestionan avisos popup" on public.avisos_popup;
create policy "Administradores gestionan avisos popup" on public.avisos_popup
for all to authenticated
using (exists(select 1 from public.administradores a where a.user_id=auth.uid() and a.activo=true))
with check (exists(select 1 from public.administradores a where a.user_id=auth.uid() and a.activo=true));

create or replace function public.solo_un_popup_activo()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.activo then
    update public.avisos_popup set activo=false, actualizado_en=now() where id<>new.id and activo=true;
  end if;
  new.actualizado_en=now();
  return new;
end;$$;

drop trigger if exists trg_solo_un_popup_activo on public.avisos_popup;
create trigger trg_solo_un_popup_activo
before insert or update on public.avisos_popup
for each row execute function public.solo_un_popup_activo();
