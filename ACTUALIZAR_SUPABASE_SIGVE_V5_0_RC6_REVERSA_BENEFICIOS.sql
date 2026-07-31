-- SIGVE v5.0 RC6 · Cancelación de reservas y devolución de beneficios
-- Ejecutar completo en Supabase > SQL Editor.
begin;

alter table public.beneficios_usos
  add column if not exists estado text not null default 'aplicado',
  add column if not exists revertido_en timestamptz,
  add column if not exists motivo_reversion text,
  add column if not exists revertido_por uuid;

alter table public.beneficios_usos
  drop constraint if exists beneficios_usos_estado_check;
alter table public.beneficios_usos
  add constraint beneficios_usos_estado_check check (estado in ('aplicado','revertido'));

-- Los registros existentes corresponden a usos activos, salvo que la reserva ya esté cancelada.
update public.beneficios_usos u
set estado='revertido',
    revertido_en=coalesce(u.revertido_en,now()),
    motivo_reversion=coalesce(u.motivo_reversion,'Reserva cancelada antes de instalar SIGVE RC6')
from public.reservas_sede r
where r.id=u.reserva_id and r.estado in ('cancelado','archivado') and u.estado='aplicado';

-- Reemplaza la evaluación para que los usos revertidos no consuman el beneficio anual.
create or replace function public.evaluar_beneficios_socio(p_socio_id uuid,p_fecha date,p_valor_original numeric)
returns table(beneficio_id uuid,nombre text,tipo text,cumple boolean,motivo text,detalle text,valor_final numeric)
language plpgsql security definer set search_path=public as $$
declare b record; pagadas integer; deuda integer; usados integer; a integer:=extract(year from p_fecha);
begin
 select count(*) into pagadas from cuotas_socios where socio_id=p_socio_id and estado='pagado' and extract(year from periodo)=a;
 select count(*) into deuda from cuotas_socios where socio_id=p_socio_id and estado='pendiente' and periodo < date_trunc('month',p_fecha)::date;
 for b in select * from beneficios_config where activo and (vigencia_desde is null or vigencia_desde<=p_fecha) and (vigencia_hasta is null or vigencia_hasta>=p_fecha) order by prioridad asc loop
  select count(*) into usados from beneficios_usos where socio_id=p_socio_id and beneficio_id=b.id and anio=a and estado='aplicado';
  beneficio_id:=b.id; nombre:=b.nombre; tipo:=b.tipo;
  cumple:=pagadas>=b.cuotas_minimas and (not b.exigir_sin_deuda or deuda=0) and usados<b.usos_maximos_anuales;
  motivo:=case when pagadas<b.cuotas_minimas then 'Tiene '||pagadas||' de '||b.cuotas_minimas||' cuotas requeridas.' when b.exigir_sin_deuda and deuda>0 then 'Mantiene '||deuda||' cuota(s) vencida(s).' when usados>=b.usos_maximos_anuales then 'Ya utilizó este beneficio durante el año.' else 'Cumple los requisitos.' end;
  detalle:=pagadas||' cuotas pagadas en '||a||case when b.tipo='gratis' then ' · arriendo gratuito disponible' when b.tipo='porcentaje' then ' · '||b.valor||'% de descuento' else ' · descuento de $'||b.valor end;
  valor_final:=case when not cumple then p_valor_original when b.tipo='gratis' then 0 when b.tipo='porcentaje' then greatest(0,round(p_valor_original*(1-b.valor/100))) else greatest(0,p_valor_original-b.valor) end;
  return next;
 end loop;
end $$;

grant execute on function public.evaluar_beneficios_socio(uuid,date,numeric) to authenticated;

create or replace function public.cancelar_reserva_y_revertir_beneficio(p_reserva_id uuid,p_motivo text default 'Cancelación de reserva')
returns jsonb
language plpgsql security definer set search_path=public as $$
declare r public.reservas_sede%rowtype; v_revertidos integer:=0;
begin
  select * into r from public.reservas_sede where id=p_reserva_id for update;
  if not found then raise exception 'La reserva no existe.'; end if;
  if r.estado='finalizado' then raise exception 'Una reserva finalizada no puede cancelarse devolviendo el beneficio.'; end if;
  if r.estado='cancelado' then return jsonb_build_object('cancelada',true,'beneficios_revertidos',0,'ya_cancelada',true); end if;

  update public.reservas_sede
  set estado='cancelado',actualizado_en=now()
  where id=p_reserva_id;

  update public.beneficios_usos
  set estado='revertido',revertido_en=now(),motivo_reversion=coalesce(nullif(btrim(p_motivo),''),'Cancelación de reserva'),revertido_por=auth.uid()
  where reserva_id=p_reserva_id and estado='aplicado';
  get diagnostics v_revertidos=row_count;

  begin
    insert into public.auditoria(modulo,registro_id,accion,detalle,usuario_id)
    values('beneficios',p_reserva_id,'beneficio revertido por cancelación',jsonb_build_object('beneficios_revertidos',v_revertidos,'motivo',p_motivo),auth.uid());
  exception when undefined_table or undefined_column then null;
  end;

  return jsonb_build_object('cancelada',true,'beneficios_revertidos',v_revertidos);
end $$;

grant execute on function public.cancelar_reserva_y_revertir_beneficio(uuid,text) to authenticated;

create or replace function public.eliminar_uso_beneficio_revertido(p_uso_id uuid)
returns boolean
language plpgsql security definer set search_path=public as $$
begin
  delete from public.beneficios_usos where id=p_uso_id and estado='revertido';
  if not found then raise exception 'Solo se pueden eliminar registros que ya fueron revertidos.'; end if;
  return true;
end $$;

grant execute on function public.eliminar_uso_beneficio_revertido(uuid) to authenticated;

commit;
notify pgrst,'reload schema';
