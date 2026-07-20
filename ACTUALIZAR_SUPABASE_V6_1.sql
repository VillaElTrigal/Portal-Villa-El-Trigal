-- Portal Villa El Trigal v6.1
-- Ejecutar una sola vez en Supabase > SQL Editor > New query.

create table if not exists public.documentos (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  descripcion text,
  categoria text not null default 'Otros',
  fecha_documento date,
  nombre_archivo text not null,
  mime_type text,
  bucket_nombre text not null,
  archivo_path text not null,
  archivo_url text,
  es_publico boolean not null default true,
  publicado boolean not null default true,
  creado_en timestamptz not null default now(),
  creado_por uuid references auth.users(id),
  actualizado_en timestamptz not null default now(),
  actualizado_por uuid references auth.users(id)
);

alter table public.documentos enable row level security;

drop policy if exists "Documentos públicos visibles" on public.documentos;
create policy "Documentos públicos visibles" on public.documentos for select to anon, authenticated
using ((es_publico=true and publicado=true) or exists(select 1 from public.administradores a where a.user_id=auth.uid() and a.activo=true));

drop policy if exists "Administradores gestionan documentos" on public.documentos;
create policy "Administradores gestionan documentos" on public.documentos for all to authenticated
using (exists(select 1 from public.administradores a where a.user_id=auth.uid() and a.activo=true))
with check (exists(select 1 from public.administradores a where a.user_id=auth.uid() and a.activo=true));

insert into storage.buckets(id,name,public) values('documentos-publicos','documentos-publicos',true) on conflict(id) do update set public=true;
insert into storage.buckets(id,name,public) values('documentos-privados','documentos-privados',false) on conflict(id) do update set public=false;

drop policy if exists "Lectura pública documentos públicos" on storage.objects;
create policy "Lectura pública documentos públicos" on storage.objects for select to anon, authenticated using (bucket_id='documentos-publicos');

drop policy if exists "Administradores suben documentos públicos" on storage.objects;
create policy "Administradores suben documentos públicos" on storage.objects for insert to authenticated with check (bucket_id='documentos-publicos' and exists(select 1 from public.administradores a where a.user_id=auth.uid() and a.activo=true));
drop policy if exists "Administradores gestionan documentos públicos" on storage.objects;
create policy "Administradores gestionan documentos públicos" on storage.objects for all to authenticated using (bucket_id='documentos-publicos' and exists(select 1 from public.administradores a where a.user_id=auth.uid() and a.activo=true)) with check (bucket_id='documentos-publicos' and exists(select 1 from public.administradores a where a.user_id=auth.uid() and a.activo=true));

drop policy if exists "Administradores gestionan documentos privados" on storage.objects;
create policy "Administradores gestionan documentos privados" on storage.objects for all to authenticated using (bucket_id='documentos-privados' and exists(select 1 from public.administradores a where a.user_id=auth.uid() and a.activo=true)) with check (bucket_id='documentos-privados' and exists(select 1 from public.administradores a where a.user_id=auth.uid() and a.activo=true));

select 'Actualización v6.1 completada' as resultado;
