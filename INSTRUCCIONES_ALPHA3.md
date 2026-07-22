# SIGVE v1.0.0-alpha.3

## Cambios reales incluidos

- En **Sexo** ahora aparece `M - Niño` y `F - Niña`.
- **Zumba** queda como módulo independiente de Sede y arriendos.
- Permite generar y bloquear clases recurrentes para 2026, 2027 y años posteriores.
- Permite suspender una clase para liberar esa fecha.
- Permite registrar aportes de Zumba durante el mes.
- El cierre mensual suma los aportes y crea **un solo ingreso consolidado** en Finanzas.
- Se reactiva **Eliminar prueba** para socios. Exige escribir `ELIMINAR` y borra definitivamente el registro.

## Instalación

1. En Supabase, abre **SQL Editor**.
2. Ejecuta una sola vez `ACTUALIZAR_SUPABASE_V1_0_ALPHA3_ZUMBA_PRUEBAS.sql`.
3. Comprueba que los tres resultados finales sean `true`.
4. Sube al repositorio todos los archivos del ZIP, reemplazando los anteriores.
5. Espera la publicación de GitHub Pages y pulsa `Ctrl + F5`.

## Advertencia

El botón **Eliminar prueba** borra de manera definitiva. Se incluye solo para limpiar registros mientras el sistema está en desarrollo. Para el uso oficial se recomienda retirarlo y mantener únicamente los estados Baja, Suspendido y Fallecido.
