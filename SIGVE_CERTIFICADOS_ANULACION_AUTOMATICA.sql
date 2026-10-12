-- SIGVE: liberación automática y auditada del ÚLTIMO folio anulado.
-- Ejecutar en SQL Editor tras respaldo. No modifica folios intermedios.
-- Incluye la función segura del paquete anterior.
BEGIN;
CREATE OR REPLACE FUNCTION public.reorganizar_correlativos_certificados(p_certificado_id uuid)
RETURNS TABLE(folio_eliminado bigint, registros_desplazados integer, siguiente_folio bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_cert public.certificados_emitidos%rowtype; v_max bigint;
BEGIN
 IF NOT public.es_admin() THEN RAISE EXCEPTION 'Acceso denegado'; END IF;
 PERFORM pg_advisory_xact_lock(73472026);
 SELECT * INTO v_cert FROM public.certificados_emitidos WHERE id=p_certificado_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Certificado no encontrado'; END IF;
 IF v_cert.estado_documento IS DISTINCT FROM 'anulado' THEN RAISE EXCEPTION 'El certificado debe estar anulado'; END IF;
 IF v_cert.estado_pago='pagado' OR v_cert.movimiento_id IS NOT NULL THEN
   RAISE EXCEPTION 'Folio con pago o movimiento asociado';
 END IF;
 IF EXISTS(SELECT 1 FROM public.movimientos_financieros m WHERE m.origen_modulo='certificado' AND m.origen_id=v_cert.id) THEN
   RAISE EXCEPTION 'Existen movimientos financieros históricos asociados';
 END IF;
 SELECT max(folio) INTO v_max FROM public.certificados_emitidos;
 IF v_cert.folio IS DISTINCT FROM v_max THEN RAISE EXCEPTION 'Solo puede recuperarse el último folio'; END IF;
 INSERT INTO public.auditoria_financiera(entidad,entidad_id,accion,detalle,usuario_id)
 VALUES('certificado',v_cert.id,'folio_anulado_recuperado',
 jsonb_build_object('folio',v_cert.folio,'certificado_original',to_jsonb(v_cert),'fecha_recuperacion',now()),auth.uid());
 DELETE FROM public.certificados_emitidos WHERE id=v_cert.id;
 SELECT coalesce(max(folio),0) INTO v_max FROM public.certificados_emitidos;
 IF to_regclass('public.certificados_folio_seq') IS NOT NULL THEN
   PERFORM setval('public.certificados_folio_seq',greatest(v_max,1),true);
 END IF;
 RETURN QUERY SELECT v_cert.folio,0,v_max+1;
END; $$;
REVOKE ALL ON FUNCTION public.reorganizar_correlativos_certificados(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reorganizar_correlativos_certificados(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.sigve_certificado_liberar_ultimo_anulado()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF NEW.estado_documento='anulado' AND OLD.estado_documento IS DISTINCT FROM 'anulado'
    AND NEW.estado_pago IS DISTINCT FROM 'pagado' AND NEW.movimiento_id IS NULL
    AND public.es_admin()
    AND NOT EXISTS(SELECT 1 FROM public.movimientos_financieros m
                   WHERE m.origen_modulo='certificado' AND m.origen_id=NEW.id)
    AND NEW.folio=(SELECT max(folio) FROM public.certificados_emitidos) THEN
   PERFORM public.reorganizar_correlativos_certificados(NEW.id);
 END IF;
 RETURN NULL;
END; $$;
DROP TRIGGER IF EXISTS sigve_certificado_anulado_folio_auto ON public.certificados_emitidos;
CREATE TRIGGER sigve_certificado_anulado_folio_auto
AFTER UPDATE OF estado_documento ON public.certificados_emitidos
FOR EACH ROW EXECUTE FUNCTION public.sigve_certificado_liberar_ultimo_anulado();
COMMIT;
NOTIFY pgrst,'reload schema';

-- Caso antiguo 00230: ya estaba anulado ANTES de instalar este trigger.
-- Solo si sigue siendo el último, no fue entregado y no tiene pagos:
-- SELECT * FROM public.reorganizar_correlativos_certificados('UUID-REAL-DEL-CERTIFICADO'::uuid);
