# Activar el administrador público y seguro

La versión incluida permite probar el pizarrón en el mismo navegador mediante almacenamiento local. Para publicar anuncios visibles para todos y proteger el acceso se necesita crear un proyecto gratuito en Supabase.

## Datos que se deben obtener

1. URL del proyecto.
2. Clave pública `anon`.
3. Correo del administrador.

Estos valores se incorporan en `portal-config.js`. No se debe colocar la clave `service_role` en el sitio.

## Próxima integración

La base está preparada para conectar:

- inicio de sesión con correo y contraseña;
- tabla `announcements`;
- permisos RLS para que todos lean anuncios publicados y solo administradores creen, editen o eliminen;
- almacenamiento de fotografías para noticias y galería.

El archivo `supabase-schema.sql` contiene la estructura inicial de la tabla y sus políticas.
