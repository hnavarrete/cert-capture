-- Reversa de 20261023000000_cert_qms_registro_miembros_y_auditor.sql: deja la base como estaba (se prueba con la huella).
drop function if exists public.cert_qms_mis_grupos();
drop function if exists public.cert_qms_miembros(text);
drop function if exists public.cert_qms_historial(uuid);
drop function if exists public.cert_qms_guardar_miembro(jsonb);
drop function if exists public.cert_qms_cambiar_estado(uuid, text, text);
drop function if exists public.cert_qms_autorizar_auditor(text, text, text, date);
drop function if exists public.cert_qms_revocar_auditor(uuid);
drop function if exists public.cert_qms_auditores(text);
drop table if exists compliance.qms_miembros_historial;
drop table if exists compliance.qms_auditores;
drop table if exists compliance.qms_miembros;
drop function if exists compliance._qms_miembros_guardia();
drop function if exists compliance._qms_miembros_historial_alta();
drop function if exists compliance._qms_historial_inmutable();
drop function if exists compliance.fn_qms_nivel(text);
