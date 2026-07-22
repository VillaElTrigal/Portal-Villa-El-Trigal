# SIGVE v1.0.0-alpha.1

Primera entrega real del rediseño del panel administrativo de Villa El Trigal.

## Cambios incluidos

- Nueva identidad visual **SIGVE — Sistema Integral de Gestión Vecinal**.
- Menú lateral reorganizado en Centro de gestión, Comunidad y Organización.
- Dashboard convertido en centro de gestión con:
  - socios activos;
  - solicitudes pendientes;
  - próximas reservas;
  - total disponible en caja y banco;
  - tareas pendientes;
  - agenda de los próximos 14 días;
  - actividad financiera reciente;
  - accesos rápidos;
  - resumen del contenido público.
- Diseño adaptable para computador, tablet y teléfono.
- Se conservaron los módulos y conexiones existentes.
- No se modificó la base de datos ni se agregó una migración SQL.

## Archivos modificados

- `admin.html`
- `admin-v7.css`
- `admin-v7.js`

## Importante

Esta versión no requiere ejecutar SQL en Supabase. Reemplaza los archivos del repositorio por los contenidos de este paquete y publica normalmente en GitHub Pages.
