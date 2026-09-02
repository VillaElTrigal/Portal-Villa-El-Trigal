-- SIGVE18 V6 · Timbre oficial para certificados digitales
-- Ejecutar UNA VEZ en Supabase SQL Editor.
-- No modifica certificados, socios, pagos ni autoridades existentes.

alter table public.configuracion_documentos
  add column if not exists timbre_data_url text;

comment on column public.configuracion_documentos.timbre_data_url
  is 'Imagen PNG/JPG del timbre oficial utilizada en certificados digitales';
