-- Portal Villa El Trigal v6.0
-- Ejecutar una sola vez en Supabase > SQL Editor.

alter table public.noticias add column if not exists imagenes jsonb not null default '[]'::jsonb;
alter table public.galeria add column if not exists imagenes jsonb not null default '[]'::jsonb;

-- Conserva las imágenes antiguas como primera foto.
update public.noticias set imagenes=jsonb_build_array(imagen_url)
where imagen_url is not null and jsonb_array_length(imagenes)=0;
update public.galeria set imagenes=jsonb_build_array(imagen_url)
where imagen_url is not null and jsonb_array_length(imagenes)=0;

create table if not exists public.configuracion_portal (
  id integer primary key default 1 check (id=1),
  titulo_portada text not null default 'Villa El Trigal',
  texto_portada text not null default 'Información, trámites y servicios comunitarios en un solo lugar, de manera simple y cercana.',
  portada_url text,
  whatsapp text not null default '56974596793',
  telefono text not null default '+56 9 7459 6793',
  correo text default 'JJVVELTRIGAL123@HOTMAIL.COM',
  direccion text default 'Armando Sabaj 1278, San Antonio',
  periodo_directiva text default '2024–2027',
  actualizado_en timestamptz not null default now(),
  actualizado_por uuid references auth.users(id)
);

insert into public.configuracion_portal(id) values(1) on conflict(id) do nothing;

create table if not exists public.directiva (
  id uuid primary key default gen_random_uuid(),
  cargo text not null,
  nombre text not null,
  descripcion text,
  orden integer not null default 1,
  activo boolean not null default true,
  actualizado_en timestamptz not null default now(),
  actualizado_por uuid references auth.users(id)
);

insert into public.directiva(cargo,nombre,descripcion,orden)
select * from (values
 ('Presidente','Fabián Campos Duval','Representa a la Junta de Vecinos y coordina el trabajo de la directiva.',1),
 ('Secretaria','Dyanira Núñez Véliz','Responsable del registro de acuerdos, actas y comunicaciones institucionales.',2),
 ('Tesorero','Claudio González Martínez','Administra los recursos y mantiene el control de ingresos, gastos y rendiciones.',3),
 ('Directora Suplente','Daniela Marimán Contreras','Apoya las actividades y funciones de la organización vecinal.',4),
 ('Directora Suplente','Graciela Carvacho Moraga','Apoya las actividades y funciones de la organización vecinal.',5),
 ('Directora Suplente','Nayarette Canales González','Apoya las actividades y funciones de la organización vecinal.',6)
) as v(cargo,nombre,descripcion,orden)
where not exists (select 1 from public.directiva);

alter table public.configuracion_portal enable row level security;
alter table public.directiva enable row level security;

drop policy if exists "Configuración pública" on public.configuracion_portal;
create policy "Configuración pública" on public.configuracion_portal for select to anon, authenticated using (true);
drop policy if exists "Administradores gestionan configuración" on public.configuracion_portal;
create policy "Administradores gestionan configuración" on public.configuracion_portal for all to authenticated
using (exists(select 1 from public.administradores a where a.user_id=auth.uid() and a.activo=true))
with check (exists(select 1 from public.administradores a where a.user_id=auth.uid() and a.activo=true));

drop policy if exists "Directiva pública" on public.directiva;
create policy "Directiva pública" on public.directiva for select to anon, authenticated using (activo=true or auth.role()='authenticated');
drop policy if exists "Administradores gestionan directiva" on public.directiva;
create policy "Administradores gestionan directiva" on public.directiva for all to authenticated
using (exists(select 1 from public.administradores a where a.user_id=auth.uid() and a.activo=true))
with check (exists(select 1 from public.administradores a where a.user_id=auth.uid() and a.activo=true));

-- Asegura que las tablas existentes permitan administrar imágenes múltiples.
-- Estas políticas solo se crean si no existen; si tus políticas actuales funcionan, no las reemplaza.
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='noticias' and policyname='Administradores gestionan noticias v6') then
    create policy "Administradores gestionan noticias v6" on public.noticias for all to authenticated
    using (exists(select 1 from public.administradores a where a.user_id=auth.uid() and a.activo=true))
    with check (exists(select 1 from public.administradores a where a.user_id=auth.uid() and a.activo=true));
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='galeria' and policyname='Administradores gestionan galeria v6') then
    create policy "Administradores gestionan galeria v6" on public.galeria for all to authenticated
    using (exists(select 1 from public.administradores a where a.user_id=auth.uid() and a.activo=true))
    with check (exists(select 1 from public.administradores a where a.user_id=auth.uid() and a.activo=true));
  end if;
end $$;

select 'Actualización v6.0 completada' as resultado;
