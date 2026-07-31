# SIGVE v5.0 RC5

## Corrección principal
- Se separaron los dos flujos de reserva.
- El Portal de Inicio mantiene la reserva pública a precio normal y sin beneficios.
- El Portal del Socio habilita beneficios únicamente mediante una sesión válida y un contexto de un solo uso.

## Administración
- Cada arriendo muestra su origen: Portal público, Portal Socio o Administración.
- Se muestra el beneficio aplicado o “Sin beneficio aplicado”.

## Archivos modificados
- `portal-v7.js`
- `portal-v7.css`
- `portal-socio.js`
- `portal-socio.html`
- `index.html`
- `admin-v7.js`

## Base de datos
- Nuevo campo `reservas_sede.origen_reserva`.
- Función pública forzada a precio normal.
- Función de socio con validación de sesión y beneficio en el servidor.
