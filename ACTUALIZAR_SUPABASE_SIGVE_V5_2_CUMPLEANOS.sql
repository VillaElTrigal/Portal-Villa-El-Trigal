-- SIGVE v5.2 · Registro de saludos de cumpleaños
create table if not exists public.cumpleanos_saludos (
  id uuid primary key default gen_random_uuid(),
  socio_id uuid not null references public.socios(id) on delete cascade,
  anio integer not null check (anio >= 2020 and anio <= 2200),
  preparado_en timestamptz not null default now(),
  preparado_por uuid null references auth.users(id) on delete set null,
  unique (socio_id, anio)
);

create index if not exists cumpleanos_saludos_anio_idx on public.cumpleanos_saludos(anio);
create index if not exists cumpleanos_saludos_socio_idx on public.cumpleanos_saludos(socio_id);

alter table public.cumpleanos_saludos enable row level security;
drop policy if exists "Admin gestiona saludos cumpleaños" on public.cumpleanos_saludos;
create policy "Admin gestiona saludos cumpleaños"
on public.cumpleanos_saludos for all to authenticated
using (public.es_admin())
with check (public.es_admin());

grant select, insert, update, delete on public.cumpleanos_saludos to authenticated;
