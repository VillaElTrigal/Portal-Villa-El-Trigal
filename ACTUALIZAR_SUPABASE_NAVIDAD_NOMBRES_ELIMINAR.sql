-- SIGVE Navidad: nombres separados, edición y exclusión sin borrar socios.
-- Ejecutar en Supabase SQL Editor antes de subir los archivos web.
begin;
alter table public.navidad_registros_externos add column if not exists nombres text;
alter table public.navidad_registros_externos add column if not exists apellido_paterno text;
alter table public.navidad_registros_externos add column if not exists apellido_materno text;

create table if not exists public.navidad_exclusiones (
  origen text not null check(origen in ('EXTERNO','SIGVE')),
  registro_id uuid not null,
  anio integer not null,
  creado_en timestamptz not null default now(),
  creado_por uuid default auth.uid(),
  primary key(origen,registro_id,anio)
);
alter table public.navidad_exclusiones enable row level security;
drop policy if exists navidad_exclusiones_admin on public.navidad_exclusiones;
create policy navidad_exclusiones_admin on public.navidad_exclusiones for all to authenticated using(public.es_admin()) with check(public.es_admin());
grant select on public.navidad_exclusiones to authenticated;

create or replace function public.registrar_navidad_publica_v4(
 p_nombres text,p_apellido_paterno text,p_apellido_materno text,p_rut text,p_fecha_nacimiento date,p_sexo text,p_via_id uuid,p_numero_domicilio text,p_telefono text
) returns text language plpgsql security definer set search_path=public as $$
declare v_result text;v_nombre text;v_rut text;v_anio integer;
begin
 if length(btrim(coalesce(p_nombres,'')))<2 or length(btrim(coalesce(p_apellido_paterno,'')))<2 or length(btrim(coalesce(p_apellido_materno,'')))<2 then
   raise exception 'Completa nombres, apellido paterno y apellido materno.';
 end if;
 v_nombre:=concat_ws(' ',btrim(p_nombres),btrim(p_apellido_paterno),btrim(p_apellido_materno));
 v_result:=public.registrar_navidad_publica_v3(v_nombre,p_rut,p_fecha_nacimiento,p_sexo,p_via_id,p_numero_domicilio,p_telefono);
 if v_result='REGISTRADO' then
   select anio into v_anio from public.configuracion_navidad where id=1;
   v_rut:=public.normalizar_rut_chileno(p_rut);
   update public.navidad_registros_externos set nombres=btrim(p_nombres),apellido_paterno=btrim(p_apellido_paterno),apellido_materno=btrim(p_apellido_materno)
   where anio=v_anio and activo=true and public.normalizar_rut_chileno(rut)=v_rut;
 end if;
 return v_result;
end;$$;
revoke all on function public.registrar_navidad_publica_v4(text,text,text,text,date,text,uuid,text,text) from public;
grant execute on function public.registrar_navidad_publica_v4(text,text,text,text,date,text,uuid,text,text) to anon,authenticated;

create or replace function public.editar_navidad_admin_v2(
 p_origen text,p_id uuid,p_nombres text,p_apellido_paterno text,p_apellido_materno text,p_rut text,p_fecha_nacimiento date,p_sexo text,p_direccion text default null,p_telefono text default null
) returns boolean language plpgsql security definer set search_path=public as $$
declare v_nombre text;
begin
 if auth.uid() is null or not public.es_admin() then raise exception 'No autorizado.'; end if;
 if length(btrim(coalesce(p_nombres,'')))<2 or length(btrim(coalesce(p_apellido_paterno,'')))<2 or length(btrim(coalesce(p_apellido_materno,'')))<2 then raise exception 'Completa los tres campos de nombres y apellidos.'; end if;
 v_nombre:=concat_ws(' ',btrim(p_nombres),btrim(p_apellido_paterno),btrim(p_apellido_materno));
 perform public.editar_navidad_admin(p_origen,p_id,v_nombre,p_rut,p_fecha_nacimiento,p_sexo,p_direccion,p_telefono);
 if upper(p_origen)='EXTERNO' then
   update public.navidad_registros_externos set nombres=btrim(p_nombres),apellido_paterno=btrim(p_apellido_paterno),apellido_materno=btrim(p_apellido_materno),actualizado_en=now() where id=p_id and activo=true;
 end if;
 return true;
end;$$;
revoke all on function public.editar_navidad_admin_v2(text,uuid,text,text,text,text,date,text,text,text) from public;
grant execute on function public.editar_navidad_admin_v2(text,uuid,text,text,text,text,date,text,text,text) to authenticated;

create or replace function public.eliminar_inscripcion_navidad_admin(p_origen text,p_id uuid,p_anio integer)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null or not public.es_admin() then raise exception 'No autorizado.'; end if;
 if upper(p_origen) not in ('EXTERNO','SIGVE') then raise exception 'Origen inválido.'; end if;
 if upper(p_origen)='EXTERNO' then
   update public.navidad_registros_externos set activo=false,actualizado_en=now() where id=p_id and anio=p_anio and activo=true;
   if not found then raise exception 'Inscripción no encontrada.'; end if;
 else
   if not exists(select 1 from public.ninos_hogar where id=p_id and activo=true) then raise exception 'Niño no encontrado en SIGVE.'; end if;
 end if;
 insert into public.navidad_exclusiones(origen,registro_id,anio) values(upper(p_origen),p_id,p_anio) on conflict do nothing;
 return true;
end;$$;
revoke all on function public.eliminar_inscripcion_navidad_admin(text,uuid,integer) from public;
grant execute on function public.eliminar_inscripcion_navidad_admin(text,uuid,integer) to authenticated;
commit;
notify pgrst,'reload schema';
