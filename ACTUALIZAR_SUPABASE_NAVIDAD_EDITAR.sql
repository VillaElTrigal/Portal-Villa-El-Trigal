-- SIGVE · Navidad · Edición de inscripciones desde Administración
-- Ejecutar una vez en Supabase > SQL Editor.

begin;

create or replace function public.editar_navidad_admin(
  p_origen text, p_id uuid, p_nombre text, p_rut text, p_fecha_nacimiento date, p_sexo text,
  p_direccion text default null, p_telefono text default null
) returns boolean
language plpgsql security definer set search_path=public as $$
declare v_origen text:=upper(btrim(coalesce(p_origen,''))); v_rut text;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión.'; end if;
  if btrim(coalesce(p_nombre,''))='' or p_fecha_nacimiento is null or p_sexo not in ('M','F') then
    raise exception 'Completa los datos obligatorios.';
  end if;
  v_rut:=public.normalizar_rut_chileno(p_rut);
  if v_rut is null or v_rut='' then raise exception 'RUT inválido.'; end if;

  if v_origen='EXTERNO' then
    if btrim(coalesce(p_direccion,''))='' or btrim(coalesce(p_telefono,''))='' then raise exception 'Dirección y teléfono son obligatorios.'; end if;
    update public.navidad_registros_externos set
      nombre_completo=btrim(p_nombre), rut=v_rut, fecha_nacimiento=p_fecha_nacimiento, sexo=p_sexo,
      direccion=btrim(p_direccion), telefono=btrim(p_telefono)
    where id=p_id and activo=true;
  elsif v_origen='SIGVE' then
    update public.ninos_hogar set nombre_completo=btrim(p_nombre), rut=v_rut, fecha_nacimiento=p_fecha_nacimiento, sexo=p_sexo, actualizado_en=now()
    where id=p_id and activo=true;
  else
    raise exception 'Origen de inscripción no válido.';
  end if;
  if not found then raise exception 'No se encontró la inscripción.'; end if;
  return true;
end;$$;

revoke all on function public.editar_navidad_admin(text,uuid,text,text,date,text,text,text) from public;
grant execute on function public.editar_navidad_admin(text,uuid,text,text,date,text,text,text) to authenticated;

commit;
notify pgrst,'reload schema';
