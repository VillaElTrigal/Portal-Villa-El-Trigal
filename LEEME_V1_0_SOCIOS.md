# Portal Villa El Trigal v1.0 — actualización de Socios

## Qué cambia

- “Grupo familiar” se reemplaza por **Niños y niñas del hogar**.
- El socio registra personalmente a los niños/as mediante un enlace personal enviado al aprobar su solicitud.
- La dirección no se solicita para cada niño/a: se obtiene siempre del domicilio del socio titular.
- El número de socio se asigna únicamente cuando el registro queda **Activo**.
- Los números no se reutilizan y, si no existen socios, la secuencia vuelve a comenzar en 1.
- Se elimina el borrado físico: un socio se cambia a **Baja, Suspendido o Fallecido**.
- Los socios dados de baja permanecen visibles, tachados y con historial.
- Al cambiar el estado se prepara un mensaje para WhatsApp.
- Se incorpora consentimiento de WhatsApp y preparación para el futuro grupo oficial.
- Se incorpora una tabla de auditoría.

## Instalación

1. Reemplazar en GitHub todos los archivos de esta carpeta.
2. En Supabase abrir **SQL Editor**.
3. Ejecutar completo `ACTUALIZAR_SUPABASE_V1_0_SOCIOS.sql`.
4. Volver a cargar el portal usando `Ctrl + F5`.

## Pruebas recomendadas

1. Enviar una solicitud desde “Hazte socio”.
2. Aprobarla desde el panel.
3. Confirmar que recibe el N.º 0001 si no hay socios previos.
4. Abrir el enlace de WhatsApp y registrar un niño/a.
5. Confirmar que aparece en “Niños y niñas” y hereda la dirección del socio.
6. Dar de baja al socio y comprobar que queda tachado, no desaparece y aparece en Historial.
7. Verificar que el botón de WhatsApp prepara el aviso de baja.

## Nota

El script conserva los registros existentes. La antigua tabla `grupo_familiar` no se elimina para evitar pérdida de datos; sus registros se migran a `ninos_hogar`.
