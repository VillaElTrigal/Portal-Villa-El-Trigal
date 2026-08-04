-- SIGVE v5.4.1 · Recuperar folios anulados de prueba
-- Ejecutar completo en Supabase > SQL Editor.
begin;

create or replace function public.reorganizar_correlativos_certificados(
  p_certificado_id uuid
) returns table(
  folio_eliminado bigint,
  registros_desplazados integer,
  siguiente_folio bigint
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_cert public.certificados_emitidos%rowtype;
  v_count integer:=0;
  v_max bigint:=0;
  v_offset bigint:=1000000000;
  v_has_numero boolean:=false;
begin
  if not public.es_admin() then
    raise exception 'Acceso denegado';
  end if;

  -- Evita que dos administradores generen o reorganicen folios simultáneamente.
  perform pg_advisory_xact_lock(73472026);

  select * into v_cert
  from public.certificados_emitidos
  where id=p_certificado_id
  for update;

  if not found then raise exception 'Certificado no encontrado'; end if;
  if v_cert.estado_documento is distinct from 'anulado' then
    raise exception 'Solo se puede reorganizar desde un certificado anulado';
  end if;
  if v_cert.movimiento_id is not null or v_cert.estado_pago='pagado' then
    raise exception 'El certificado tiene un pago o movimiento financiero asociado';
  end if;

  -- No renumera documentos oficiales ya emitidos.
  if exists(
    select 1 from public.certificados_emitidos c
    where c.folio>v_cert.folio
      and coalesce(c.estado_documento,'emitido') in ('emitido','entregado')
  ) then
    raise exception 'Existen certificados posteriores ya emitidos. No es seguro reorganizar la secuencia';
  end if;

  select count(*)::integer into v_count
  from public.certificados_emitidos c
  where c.folio>v_cert.folio;

  delete from public.certificados_emitidos where id=v_cert.id;

  -- Desplazamiento en dos pasos para respetar el índice único de folio.
  update public.certificados_emitidos
     set folio=folio+v_offset
   where folio>v_cert.folio;

  update public.certificados_emitidos
     set folio=folio-v_offset-1
   where folio>v_cert.folio+v_offset;

  -- Algunas instalaciones históricas conservan también la columna numero.
  select exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='certificados_emitidos' and column_name='numero'
  ) into v_has_numero;
  if v_has_numero then
    execute 'update public.certificados_emitidos set numero=folio where folio is not null';
  end if;

  -- Mantiene legible el concepto del ingreso, sin alterar el vínculo por UUID.
  update public.movimientos_financieros m
     set concepto='Pago certificado de residencia - Folio N° '||lpad(c.folio::text,5,'0')
    from public.certificados_emitidos c
   where m.id=c.movimiento_id
     and c.folio>=v_cert.folio;

  select coalesce(max(folio),0) into v_max from public.certificados_emitidos;
  if to_regclass('public.certificados_folio_seq') is not null then
    perform setval('public.certificados_folio_seq',greatest(v_max,1),true);
  end if;

  if to_regclass('public.auditoria_financiera') is not null then
    insert into public.auditoria_financiera(entidad,entidad_id,accion,detalle,usuario_id)
    values(
      'certificado',v_cert.id,'correlativos_reorganizados',
      jsonb_build_object('folio_eliminado',v_cert.folio,'registros_desplazados',v_count,'siguiente_folio',v_max+1),
      auth.uid()
    );
  end if;

  return query select v_cert.folio,v_count,v_max+1;
end;
$$;

revoke all on function public.reorganizar_correlativos_certificados(uuid) from public;
grant execute on function public.reorganizar_correlativos_certificados(uuid) to authenticated;

commit;
notify pgrst,'reload schema';
