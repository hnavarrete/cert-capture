-- Reversa de 20261025000000_cert_qms_auditoria_interna.sql: deja la base como estaba (lo comprueba la ida y vuelta).
-- 🔴 Borra los informes de auditoría interna: en producción, solo antes de que un grupo tenga informes reales.
drop function if exists public.cert_qms_cronograma(text);
drop function if exists public.cert_qms_planificar(text, uuid, date, text);
drop function if exists public.cert_qms_cancelar_inspeccion(uuid, text);
drop function if exists public.cert_qms_mis_inspecciones();
drop function if exists public.cert_qms_enviar_inspeccion(jsonb);
drop function if exists public.cert_qms_informe(uuid);
drop function if exists public.cert_qms_decidir(uuid, text, text, text);
drop table if exists compliance.qms_inspecciones;
drop table if exists compliance.qms_checklist_puntos;
drop function if exists compliance.fn_qms_cumplimiento(text, jsonb);
drop function if exists compliance._qms_insp_guardia();
