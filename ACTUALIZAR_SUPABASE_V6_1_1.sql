-- Portal Villa El Trigal v6.1.1
-- Ejecutar una sola vez en Supabase > SQL Editor > New query.

-- Corrige y completa la estructura necesaria para publicar noticias.
alter table public.noticias add column if not exists fecha_publicacion date default current_date;
alter table public.noticias add column if not exists imagenes jsonb not null default '[]'::jsonb;

-- Permite registrar el teléfono de cada integrante de la directiva.
alter table public.directiva add column if not exists telefono text;

-- Completa datos antiguos para evitar campos vacíos heredados.
update public.noticias
set fecha_publicacion = coalesce(fecha_publicacion, creado_en::date, current_date)
where fecha_publicacion is null;

select 'Actualización v6.1.1 completada' as resultado;
