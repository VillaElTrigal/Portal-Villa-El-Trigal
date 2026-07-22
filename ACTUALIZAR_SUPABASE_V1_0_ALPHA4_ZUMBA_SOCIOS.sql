-- SIGVE v1.0.0 alpha.4
-- Pago mensual de la profesora de Zumba, cierre financiero y eliminación de socios habilitada en desarrollo.

begin;

-- Datos adicionales para identificar el pago único de la profesora.
alter table if exists public.zumba_pagos
  add column if not exists comprobante text;

alter table if exists public.zumba_cierres
  add column if not exists profesora text,
  add column if not exists fecha_pago date,
  add column if not exists medio_pago text,
  add column if not exists comprobante text,
  add column if not exists estado text not null default 'cerrado';

-- Evita más de un cierre para el mismo mes.
create unique index if not exists zumba_cierres_mes_unico_idx
  on public.zumba_cierres (mes);

-- Función de eliminación definitiva habilitada durante la etapa de desarrollo.
-- Conserva una huella mínima en auditoría antes de borrar el socio.
create or replace function public.eliminar_socio_prueba(p_socio_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usuario uuid := auth.uid();
  v_socio jsonb;
begin
  if v_usuario is null or not public.es_admin() then
    raise exception 'Acceso no autorizado';
  end if;

  select to_jsonb(s) into v_socio from public.socios s where s.id = p_socio_id;
  if v_socio is null then raise exception 'El socio no existe'; end if;

  delete from public.ninos_hogar where socio_id = p_socio_id;
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

  delete from public.auditoria where registro_id=p_socio_id and modulo='socios';

  alter table public.socios disable trigger trg_impedir_borrado_socio;
  delete from public.socios where id=p_socio_id;
  alter table public.socios enable trigger trg_impedir_borrado_socio;

  insert into public.auditoria(modulo, registro_id, accion, detalle, usuario_id)
  values ('socios', null, 'eliminación definitiva de desarrollo',
          jsonb_build_object(
            'socio_eliminado_id', p_socio_id,
            'nombre_completo', v_socio->>'nombre_completo',
            'rut', v_socio->>'rut',
            'numero_socio', v_socio->>'numero_socio'
          ), v_usuario);

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

notify pgrst, 'reload schema';

commit;

select
  to_regclass('public.zumba_pagos') is not null as tabla_zumba_pagos,
  to_regclass('public.zumba_cierres') is not null as tabla_zumba_cierres,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='zumba_pagos' and column_name='comprobante') as pago_comprobante,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='zumba_cierres' and column_name='profesora') as cierre_profesora,
  to_regprocedure('public.eliminar_socio_prueba(uuid)') is not null as eliminar_socio_habilitado;
