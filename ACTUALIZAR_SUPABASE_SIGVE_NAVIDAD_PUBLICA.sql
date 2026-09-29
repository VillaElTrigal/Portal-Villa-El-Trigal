-- SIGVE · Registro público Navidad
-- Ejecutar una sola vez en Supabase > SQL Editor.
begin;

create table if not exists public.configuracion_navidad (
  id integer primary key default 1 check (id=1),
  anio integer not null default extract(year from current_date)::integer,
  titulo text not null default 'Registro de niños y niñas – Navidad',
  inicio timestamptz,
  cierre timestamptz,
  modo text not null default 'auto' check (modo in ('auto','abierto','cerrado')),
  actualizado_en timestamptz not null default now(),
  actualizado_por uuid references auth.users(id)
);
insert into public.configuracion_navidad(id) values(1) on conflict(id) do nothing;

create table if not exists public.navidad_registros_externos (
  id uuid primary key default gen_random_uuid(),
  anio integer not null,
  nombre_completo text not null,
  rut text not null,
  fecha_nacimiento date not null,
  direccion text not null,
  telefono text not null,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
create unique index if not exists navidad_externo_rut_anio_unique
  on public.navidad_registros_externos(anio, public.normalizar_rut_chileno(rut)) where activo=true;

alter table public.configuracion_navidad enable row level security;
alter table public.navidad_registros_externos enable row level security;

drop policy if exists "Admin gestiona configuracion navidad" on public.configuracion_navidad;
create policy "Admin gestiona configuracion navidad" on public.configuracion_navidad
for all to authenticated using(public.es_admin()) with check(public.es_admin());
drop policy if exists "Admin gestiona registros navidad" on public.navidad_registros_externos;
create policy "Admin gestiona registros navidad" on public.navidad_registros_externos
for all to authenticated using(public.es_admin()) with check(public.es_admin());

grant select,insert,update,delete on public.configuracion_navidad to authenticated;
grant select,insert,update,delete on public.navidad_registros_externos to authenticated;

create or replace function public.estado_navidad_publica()
returns table(anio integer,titulo text,inicio timestamptz,cierre timestamptz,abierto boolean)
language sql security definer stable set search_path=public as $$
  select c.anio,c.titulo,c.inicio,c.cierre,
    case c.modo when 'abierto' then true when 'cerrado' then false
      else (c.inicio is not null and c.cierre is not null and now() between c.inicio and c.cierre) end
  from public.configuracion_navidad c where c.id=1;
$$;

create or replace function public.registrar_navidad_publica(
 p_nombre text,p_rut text,p_fecha_nacimiento date,p_direccion text,p_telefono text
) returns text
language plpgsql security definer set search_path=public as $$
declare c public.configuracion_navidad%rowtype; v_rut text; v_abierto boolean;
begin
 select * into c from public.configuracion_navidad where id=1;
 v_abierto := case c.modo when 'abierto' then true when 'cerrado' then false else (c.inicio is not null and c.cierre is not null and now() between c.inicio and c.cierre) end;
 if not coalesce(v_abierto,false) then raise exception 'Las inscripciones de Navidad no están abiertas.'; end if;
 if length(btrim(coalesce(p_nombre,'')))<3 then raise exception 'Ingresa el nombre completo.'; end if;
 if p_fecha_nacimiento is null or p_fecha_nacimiento>current_date then raise exception 'La fecha de nacimiento no es válida.'; end if;
 if length(btrim(coalesce(p_direccion,'')))<5 then raise exception 'Ingresa la dirección.'; end if;
 if length(regexp_replace(coalesce(p_telefono,''),'[^0-9]','','g'))<7 then raise exception 'Ingresa un teléfono de contacto válido.'; end if;
 if not public.validar_rut_chileno(p_rut) then raise exception 'El RUT ingresado no es válido.'; end if;
 v_rut:=public.normalizar_rut_chileno(p_rut);
 if exists(select 1 from public.ninos_hogar n where n.activo=true and public.normalizar_rut_chileno(n.rut)=v_rut) then
   return 'YA_SIGVE';
 end if;
 if exists(select 1 from public.navidad_registros_externos e where e.anio=c.anio and e.activo=true and public.normalizar_rut_chileno(e.rut)=v_rut) then
   return 'YA_EXTERNO';
 end if;
 insert into public.navidad_registros_externos(anio,nombre_completo,rut,fecha_nacimiento,direccion,telefono)
 values(c.anio,btrim(p_nombre),v_rut,p_fecha_nacimiento,btrim(p_direccion),btrim(p_telefono));
 return 'REGISTRADO';
end;
$$;

create or replace function public.listar_navidad_admin()
returns table(origen text,id uuid,anio integer,nombre_completo text,rut text,fecha_nacimiento date,direccion text,telefono text,creado_en timestamptz)
language sql security definer stable set search_path=public as $$
  select 'SIGVE'::text,n.id,c.anio,n.nombre_completo,n.rut,n.fecha_nacimiento,s.direccion,s.telefono,n.creado_en
  from public.configuracion_navidad c join public.ninos_hogar n on n.activo=true join public.socios s on s.id=n.socio_id
  where c.id=1 and s.estado='activo'
  union all
  select 'EXTERNO',e.id,e.anio,e.nombre_completo,e.rut,e.fecha_nacimiento,e.direccion,e.telefono,e.creado_en
  from public.navidad_registros_externos e join public.configuracion_navidad c on c.id=1 and c.anio=e.anio
  where e.activo=true
  order by nombre_completo;
$$;

revoke all on function public.estado_navidad_publica() from public;
revoke all on function public.registrar_navidad_publica(text,text,date,text,text) from public;
revoke all on function public.listar_navidad_admin() from public;
grant execute on function public.estado_navidad_publica() to anon,authenticated;
grant execute on function public.registrar_navidad_publica(text,text,date,text,text) to anon,authenticated;
grant execute on function public.listar_navidad_admin() to authenticated;

commit;
notify pgrst,'reload schema';
