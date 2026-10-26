-- Reversa de 20261026020000_cert_qms_auditor_evidencias_ifa.sql (lo comprueba la ida y vuelta).
drop function if exists public.cert_qms_evidencias_ifa(text);
drop policy if exists cert_evidencias_select_auditor_qms on storage.objects;
drop function if exists public.fn_qms_auditor_ve_evidencia(text);
