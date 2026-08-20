-- SIGVE v7.6.0 · Vías exclusivas para certificado
begin;
create table if not exists public.vias_certificado(
 id uuid primary key default gen_random_uuid(),tipo text not null default 'Calle',nombre text not null,
 activa boolean not null default true,creado_en timestamptz not null default now(),actualizado_en timestamptz not null default now(),
 constraint vias_certificado_nombre_unique unique(tipo,nombre));
alter table public.vias_certificado enable row level security;
drop policy if exists "Publico lee vias certificado activas" on public.vias_certificado;
create policy "Publico lee vias certificado activas" on public.vias_certificado for select to anon,authenticated using(activa=true or public.es_admin());
drop policy if exists "Admin gestiona vias certificado" on public.vias_certificado;
create policy "Admin gestiona vias certificado" on public.vias_certificado for all to authenticated using(public.es_admin()) with check(public.es_admin());
grant select on public.vias_certificado to anon,authenticated;
grant insert,update,delete on public.vias_certificado to authenticated;
commit;