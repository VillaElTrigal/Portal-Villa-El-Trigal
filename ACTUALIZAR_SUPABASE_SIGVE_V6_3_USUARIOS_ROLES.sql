-- SIGVE v6.3 · Usuarios y roles
-- Ejecutar una sola vez en Supabase > SQL Editor.
-- Objetivo: preparar Administrador / Tesorero / Secretario sin crear cuentas genéricas.

begin;

-- Normaliza roles existentes y mantiene al administrador actual operativo.
update public.administradores
set rol = lower(coalesce(nullif(trim(rol),''),'administrador'));

-- Función de rol actual. SECURITY DEFINER evita depender de RLS para consultar el propio rol.
create or replace function public.sigve_rol_actual()
returns text
language sql
stable
security definer
set search_path=public
as $$
  select lower(a.rol)
  from public.administradores a
  where a.user_id=auth.uid() and a.activo=true
  limit 1
$$;

-- IMPORTANTE: es_admin vuelve a significar administrador real.
-- Así las políticas/RPC históricas que usan es_admin() quedan reservadas al administrador principal.
create or replace function public.es_admin()
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select coalesce(public.sigve_rol_actual()='administrador',false)
$$;

create or replace function public.es_usuario_sigve()
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select public.sigve_rol_actual() in ('administrador','tesorero','secretario')
$$;

-- Cada usuario activo puede leer exclusivamente su propia ficha de acceso.
alter table public.administradores enable row level security;
drop policy if exists sigve_administradores_self_select on public.administradores;
create policy sigve_administradores_self_select
on public.administradores for select to authenticated
using (user_id=auth.uid());

-- El administrador principal puede gestionar las fichas de acceso.
drop policy if exists sigve_administradores_admin_all on public.administradores;
create policy sigve_administradores_admin_all
on public.administradores for all to authenticated
using (public.es_admin()) with check (public.es_admin());

-- Lista segura para el módulo Usuarios y permisos.
create or replace function public.sigve_listar_usuarios()
returns table(user_id uuid, nombre text, rol text, activo boolean, email text)
language plpgsql
security definer
set search_path=public,auth
as $$
begin
  if not public.es_admin() then raise exception 'Acceso denegado'; end if;
  return query
  select a.user_id, a.nombre, lower(a.rol), a.activo, u.email::text
  from public.administradores a
  left join auth.users u on u.id=a.user_id
  order by case lower(a.rol) when 'administrador' then 1 when 'tesorero' then 2 when 'secretario' then 3 else 9 end, a.nombre;
end;
$$;
revoke all on function public.sigve_listar_usuarios() from public, anon;
grant execute on function public.sigve_listar_usuarios() to authenticated;

-- Asigna una cuenta YA existente en Supabase Authentication a un cargo.
-- No crea contraseñas ni cuentas genéricas.
create or replace function public.sigve_asignar_usuario(p_email text, p_nombre text, p_rol text, p_activo boolean default false)
returns uuid
language plpgsql
security definer
set search_path=public,auth
as $$
declare v_uid uuid; v_rol text := lower(trim(p_rol));
begin
  if not public.es_admin() then raise exception 'Acceso denegado'; end if;
  if v_rol not in ('tesorero','secretario') then raise exception 'Rol no permitido'; end if;
  select id into v_uid from auth.users where lower(email)=lower(trim(p_email)) limit 1;
  if v_uid is null then raise exception 'El correo aún no existe en Authentication > Users'; end if;
  if exists(select 1 from public.administradores where lower(rol)=v_rol and activo=true and user_id<>v_uid) and p_activo then
    raise exception 'Ya existe un usuario activo para este cargo';
  end if;
  insert into public.administradores(user_id,nombre,rol,activo)
  values(v_uid,coalesce(nullif(trim(p_nombre),''),trim(p_email)),v_rol,coalesce(p_activo,false))
  on conflict(user_id) do update set nombre=excluded.nombre, rol=excluded.rol, activo=excluded.activo;
  return v_uid;
end;
$$;
revoke all on function public.sigve_asignar_usuario(text,text,text,boolean) from public, anon;
grant execute on function public.sigve_asignar_usuario(text,text,text,boolean) to authenticated;

create or replace function public.sigve_cambiar_estado_usuario(p_user_id uuid, p_activo boolean)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_rol text;
begin
  if not public.es_admin() then raise exception 'Acceso denegado'; end if;
  select lower(rol) into v_rol from public.administradores where user_id=p_user_id;
  if v_rol='administrador' then raise exception 'El administrador principal no puede desactivarse desde este módulo'; end if;
  if v_rol is null then raise exception 'Usuario no encontrado'; end if;
  if p_activo and exists(select 1 from public.administradores where lower(rol)=v_rol and activo=true and user_id<>p_user_id) then
    raise exception 'Ya existe un usuario activo para este cargo';
  end if;
  update public.administradores set activo=p_activo where user_id=p_user_id;
end;
$$;
revoke all on function public.sigve_cambiar_estado_usuario(uuid,boolean) from public, anon;
grant execute on function public.sigve_cambiar_estado_usuario(uuid,boolean) to authenticated;

create or replace function public.sigve_desasignar_usuario(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_rol text;
begin
  if not public.es_admin() then raise exception 'Acceso denegado'; end if;
  select lower(rol) into v_rol from public.administradores where user_id=p_user_id;
  if v_rol='administrador' then raise exception 'El administrador principal no puede eliminarse desde este módulo'; end if;
  delete from public.administradores where user_id=p_user_id;
end;
$$;
revoke all on function public.sigve_desasignar_usuario(uuid) from public, anon;
grant execute on function public.sigve_desasignar_usuario(uuid) to authenticated;

commit;

-- NOTA DE SEGURIDAD:
-- Los roles Tesorero/Secretario quedan inicialmente sin acceso a operaciones históricas que exigen es_admin().
-- Esto es intencional: primero se crean/asignan y luego se habilitan permisos específicos por módulo.
-- No afecta al administrador actual con rol='administrador'.
