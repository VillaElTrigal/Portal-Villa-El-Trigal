-- Ejecutar en Supabase > SQL Editor > New query
-- Vincula el usuario ACTUAL con el rol administrador.
insert into public.administradores (user_id, nombre, rol, activo)
select id, 'Claudio González', 'administrador', true
from auth.users
where email = 'claudiog.16@hotmail.com'
on conflict (user_id) do update
set nombre = excluded.nombre, rol = excluded.rol, activo = true;

select a.nombre, a.rol, a.activo, u.email, u.id as user_id
from public.administradores a
join auth.users u on u.id = a.user_id
where u.email = 'claudiog.16@hotmail.com';
