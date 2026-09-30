-- SIGVE · Navidad 2026 · Validación de vías del sector
-- Ejecutar una sola vez en Supabase > SQL Editor después del SQL inicial de Navidad.
begin;

create or replace function public.registrar_navidad_publica_v2(
 p_nombre text,p_rut text,p_fecha_nacimiento date,p_via_id uuid,p_numero_domicilio text,p_telefono text
) returns text
language plpgsql security definer set search_path=public as $$
declare c public.configuracion_navidad%rowtype; v_rut text; v_abierto boolean; v_via public.vias%rowtype; v_direccion text;
begin
 select * into c from public.configuracion_navidad where id=1;
 v_abierto := case c.modo when 'abierto' then true when 'cerrado' then false else (c.inicio is not null and c.cierre is not null and now() between c.inicio and c.cierre) end;
 if not coalesce(v_abierto,false) then raise exception 'Las inscripciones de Navidad no están abiertas.'; end if;
 if length(btrim(coalesce(p_nombre,'')))<3 then raise exception 'Ingresa el nombre completo.'; end if;
 if p_fecha_nacimiento is null or p_fecha_nacimiento>current_date then raise exception 'La fecha de nacimiento no es válida.'; end if;
 if p_via_id is null or length(btrim(coalesce(p_numero_domicilio,'')))<1 then raise exception 'Selecciona una vía e ingresa el número del domicilio.'; end if;
 select * into v_via from public.vias where id=p_via_id and activa=true;
 if not found then raise exception 'La vía seleccionada no está habilitada para registros.'; end if;
 if p_numero_domicilio !~ '^[0-9]+$' then raise exception 'El número del domicilio no es válido.'; end if;
 v_direccion:=btrim(concat_ws(' ',v_via.tipo,v_via.nombre,p_numero_domicilio));
 if length(regexp_replace(coalesce(p_telefono,''),'[^0-9]','','g'))<7 then raise exception 'Ingresa un teléfono de contacto válido.'; end if;
 if not public.validar_rut_chileno(p_rut) then raise exception 'El RUT ingresado no es válido.'; end if;
 v_rut:=public.normalizar_rut_chileno(p_rut);
 if exists(select 1 from public.ninos_hogar n where n.activo=true and public.normalizar_rut_chileno(n.rut)=v_rut) then return 'YA_SIGVE'; end if;
 if exists(select 1 from public.navidad_registros_externos e where e.anio=c.anio and e.activo=true and public.normalizar_rut_chileno(e.rut)=v_rut) then return 'YA_EXTERNO'; end if;
 insert into public.navidad_registros_externos(anio,nombre_completo,rut,fecha_nacimiento,direccion,telefono)
 values(c.anio,btrim(p_nombre),v_rut,p_fecha_nacimiento,v_direccion,btrim(p_telefono));
 return 'REGISTRADO';
end;
$$;

revoke all on function public.registrar_navidad_publica_v2(text,text,date,uuid,text,text) from public;
grant execute on function public.registrar_navidad_publica_v2(text,text,date,uuid,text,text) to anon,authenticated;
commit;
notify pgrst,'reload schema';
