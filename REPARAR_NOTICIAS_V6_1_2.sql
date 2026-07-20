-- Portal Villa El Trigal v6.1.2
-- Ejecutar una vez en Supabase > SQL Editor > New query.

alter table public.noticias add column if not exists resumen text;
alter table public.noticias add column if not exists contenido text;
alter table public.noticias add column if not exists categoria text default 'Comunidad';
alter table public.noticias add column if not exists imagen_url text;
alter table public.noticias add column if not exists imagenes jsonb not null default '[]'::jsonb;
alter table public.noticias add column if not exists fecha_publicacion date default current_date;
alter table public.noticias add column if not exists destacado boolean not null default false;
alter table public.noticias add column if not exists publicado boolean not null default true;
alter table public.noticias add column if not exists creado_por uuid references auth.users(id);

alter table public.noticias alter column categoria set default 'Comunidad';
alter table public.noticias alter column fecha_publicacion set default current_date;

grant select on public.noticias to anon, authenticated;
grant insert, update, delete on public.noticias to authenticated;

alter table public.noticias enable row level security;
drop policy if exists "Noticias públicas v612" on public.noticias;
create policy "Noticias públicas v612" on public.noticias
for select to anon, authenticated
using (publicado = true or auth.role() = 'authenticated');

drop policy if exists "Administradores gestionan noticias v612" on public.noticias;
create policy "Administradores gestionan noticias v612" on public.noticias
for all to authenticated
using (exists (
  select 1 from public.administradores a
  where a.user_id = auth.uid() and a.activo = true
))
with check (exists (
  select 1 from public.administradores a
  where a.user_id = auth.uid() and a.activo = true
));

select 'Reparación de noticias v6.1.2 completada' as resultado;
