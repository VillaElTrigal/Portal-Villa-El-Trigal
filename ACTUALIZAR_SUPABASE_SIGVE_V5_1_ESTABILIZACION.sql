-- SIGVE v5.1 · Respaldos financieros privados en Supabase Storage

insert into storage.buckets (id, name, public)
values ('respaldos-finanzas', 'respaldos-finanzas', false)
on conflict (id) do update set public = false;

-- Se recrea la política para evitar duplicados de nombre.
drop policy if exists "Admin gestiona respaldos finanzas" on storage.objects;
create policy "Admin gestiona respaldos finanzas"
on storage.objects
for all
to authenticated
using (bucket_id = 'respaldos-finanzas' and public.es_admin())
with check (bucket_id = 'respaldos-finanzas' and public.es_admin());

-- La tabla ya usa comprobante_url para almacenar únicamente la ruta privada.
alter table public.movimientos_financieros
  add column if not exists comprobante_url text,
  add column if not exists sin_respaldo boolean not null default false;
