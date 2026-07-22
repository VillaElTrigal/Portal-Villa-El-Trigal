# SIGVE v1.0.0 alpha.4

## Cambios implementados

### Socios
- La opción visible ahora se llama **Eliminar registro**.
- El botón quedó conectado a la función de eliminación definitiva de desarrollo.
- Exige escribir `ELIMINAR` para confirmar.
- Elimina niños y niñas asociados y deja una huella mínima en auditoría.

### Zumba
- Selector de días habilitado de lunes a domingo.
- Las clases se guardan como reservas de tipo `zumba`, por lo que bloquean el calendario de Sede y Arriendos en el mismo horario.
- Se registra un solo pago mensual realizado por la profesora.
- Se agregaron nombre de profesora, medio, comprobante, observaciones y fecha.
- El cierre mensual exige exactamente un pago pendiente y crea un único ingreso en Finanzas.

## Instalación
1. En Supabase, abre **SQL Editor**.
2. Ejecuta `ACTUALIZAR_SUPABASE_V1_0_ALPHA4_ZUMBA_SOCIOS.sql` completo.
3. Sube todos los archivos del proyecto actualizado a GitHub Pages.
4. Recarga el panel con `Ctrl + F5`.

## Pruebas recomendadas
1. Crear un socio de prueba y eliminarlo usando el botón **Eliminar registro**.
2. Marcar cualquier combinación de lunes a domingo y generar clases para un rango corto.
3. Confirmar que las fechas aparecen ocupadas en Sede y Arriendos.
4. Registrar un pago de la profesora para el mes seleccionado.
5. Cerrar el mes y revisar que exista un solo ingreso en Finanzas.
