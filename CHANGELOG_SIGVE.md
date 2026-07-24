# Historial de versiones de SIGVE

## v1.1.0 — Gestión Financiera Integrada

### Nuevos módulos
- Calendario mensual de cuotas para socios activos.
- Regla automática: ingreso del día 1 al 10 paga el mes actual; desde el día 11 queda exento por incorporación.
- Pago de cuotas en efectivo o transferencia, con integración automática a Finanzas.
- Historial de cuotas por socio y anulación trazable de pagos.
- Certificados de residencia con folio automático desde 00209.
- Libro de Caja con saldo acumulado.
- Informe financiero mensual institucional imprimible en PDF.
- Auditoría financiera y cierre mensual preparados en base de datos.

### Seguridad y trazabilidad
- Los movimientos automáticos identifican su módulo e ID de origen.
- Los pagos anulados no se borran: quedan marcados como anulados.
- Las tablas nuevas usan RLS y solo pueden ser administradas por usuarios autorizados.

### Base para SIGVE 2.0
- La estructura de cuotas, certificados y solicitudes queda preparada para ser consultada posteriormente desde el Portal del Socio.
