-- SIGVE · Eliminación completa del módulo de Apariencia/Temas de temporada
-- Solo elimina objetos creados para esta función.

begin;

drop function if exists public.admin_guardar_apariencia(text, text);
drop function if exists public.admin_obtener_apariencia();
drop function if exists public.portal_obtener_apariencia();
drop table if exists public.config_apariencia_portal cascade;

commit;
