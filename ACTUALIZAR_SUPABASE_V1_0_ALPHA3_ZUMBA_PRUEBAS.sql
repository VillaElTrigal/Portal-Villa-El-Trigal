-- SIGVE v1.0.0-alpha.3
-- Zumba independiente + cierre mensual + eliminación definitiva de socios de prueba.
-- Ejecutar UNA SOLA VEZ en Supabase > SQL Editor.

begin;

create table if not exists public.zumba_cierres (
  id uuid primary key default gen_random_uuid(),
  mes date not null unique,
  total numeric(12,0) not null check(total > 0),
  cantidad_pagos integer not null default 0 check(cantidad_pagos >= 0),
  fondo text not null check(fondo in ('caja','banco')),
  movimiento_id uuid references public.movimientos_financieros(id) on delete restrict,
  creado_por uuid references auth.users(id),
  creado_en timestamptz not null default now()
);

create table if not exists public.zumba_pagos (
  id uuid primary key default gen_random_uuid(),
  fecha date not null default current_date,
  nombre_referencia text,
  monto numeric(12,0) not null check(monto > 0),
  medio text not null default 'efectivo' check(medio in ('efectivo','transferencia')),
  observaciones text,
  cierre_id uuid references public.zumba_cierres(id) on delete restrict,
  creado_por uuid references auth.users(id),
  creado_en timestamptz not null default now()
);

create index if not exists zumba_pagos_fecha_idx on public.zumba_pagos(fecha desc);
create index if not exists zumba_pagos_cierre_idx on public.zumba_pagos(cierre_id);

alter table public.zumba_pagos enable row level security;
alter table public.zumba_cierres enable row level security;

drop policy if exists "Admin gestiona zumba_pagos" on public.zumba_pagos;
create policy "Admin gestiona zumba_pagos" on public.zumba_pagos
for all to authenticated using(public.es_admin()) with check(public.es_admin());

drop policy if exists "Admin gestiona zumba_cierres" on public.zumba_cierres;
create policy "Admin gestiona zumba_cierres" on public.zumba_cierres
for all to authenticated using(public.es_admin()) with check(public.es_admin());

-- Permite eliminar únicamente registros de prueba desde el panel.
-- La confirmación exige escribir ELIMINAR en la interfaz.
create or replace function public.eliminar_socio_prueba(p_socio_id uuid)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
begin
  if auth.uid() is null or not public.es_admin() then
    raise exception 'Acceso no autorizado';
  end if;

  if not exists(select 1 from public.socios where id=p_socio_id) then
    raise exception 'El socio no existe';
  end if;

  -- Tablas relacionadas conocidas. Se conserva la integridad y solo se usa para pruebas.
  delete from public.ninos_hogar where socio_id=p_socio_id;
  if to_regclass('public.grupo_familiar') is not null then
    execute 'delete from public.grupo_familiar where socio_id=$1' using p_socio_id;
  end if;
  if to_regclass('public.cuotas_socios') is not null then
    execute 'delete from public.cuotas_socios where socio_id=$1' using p_socio_id;
  end if;
  if to_regclass('public.certificados_emitidos') is not null then
    update public.certificados_emitidos set socio_id=null where socio_id=p_socio_id;
  end if;
  if to_regclass('public.movimientos_financieros') is not null then
    update public.movimientos_financieros set socio_id=null where socio_id=p_socio_id;
  end if;
  if to_regclass('public.auditoria') is not null then
    delete from public.auditoria where registro_id=p_socio_id and modulo='socios';
  end if;

  -- Desactiva temporalmente la protección de borrado solo dentro de esta función.
  alter table public.socios disable trigger trg_impedir_borrado_socio;
  delete from public.socios where id=p_socio_id;
  alter table public.socios enable trigger trg_impedir_borrado_socio;

  return true;
exception when others then
  begin
    alter table public.socios enable trigger trg_impedir_borrado_socio;
  exception when others then null;
  end;
  raise;
end;
$$;

revoke all on function public.eliminar_socio_prueba(uuid) from public;
grant execute on function public.eliminar_socio_prueba(uuid) to authenticated;

commit;
notify pgrst,'reload schema';

select
  to_regclass('public.zumba_pagos') is not null as tabla_zumba_pagos,
  to_regclass('public.zumba_cierres') is not null as tabla_zumba_cierres,
  to_regprocedure('public.eliminar_socio_prueba(uuid)') is not null as funcion_eliminar_prueba;
