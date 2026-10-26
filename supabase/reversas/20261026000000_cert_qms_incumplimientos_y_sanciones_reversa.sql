-- Reversa de 20261026000000_cert_qms_incumplimientos_y_sanciones.sql (lo comprueba la ida y vuelta).
-- 🔴 Borra incumplimientos y sanciones: en producción, solo antes de que un grupo tenga registros reales.
drop function if exists public.cert_qms_nc_lista(text);
drop function if exists public.cert_qms_nc_guardar(jsonb);
drop function if exists public.cert_qms_nc_cerrar(uuid, text, text);
drop function if exists public.cert_qms_sanciones(text);
drop function if exists public.cert_qms_sancionar(text, uuid, text, text, text, uuid, text);
drop function if exists public.cert_qms_sancion_aviso_cb(uuid, date);
drop function if exists public.cert_qms_sancion_levantar(uuid, text, text);
drop trigger if exists trg_qms_nc_desde_informe on compliance.qms_inspecciones;
drop table if exists compliance.qms_sanciones;
drop table if exists compliance.qms_nc;
drop function if exists compliance._qms_nc_guardia();
drop function if exists compliance._qms_nc_desde_informe();
drop function if exists compliance._qms_sancion_guardia();
drop function if exists compliance._qms_gestiona(text);
