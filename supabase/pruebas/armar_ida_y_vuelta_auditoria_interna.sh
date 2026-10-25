#!/usr/bin/env bash
# Arma pruebas/ida_y_vuelta_qms_auditoria_interna.sql: huella → migración → prueba → reversa → huella.
# El RAISE final deshace TODO; su mensaje trae los resultados. Uso: bash pruebas/armar_ida_y_vuelta.sh (desde supabase/)
set -euo pipefail
H="$(cat pruebas/_huella_cert.sql)"
{
  echo "-- IDA Y VUELTA de la auditoría interna de finca (generado por armar_ida_y_vuelta.sh). El RAISE final deshace TODO."
  echo "create temp table _res (t text); create temp table _h (cuando text, h text); grant insert, select on _res to authenticated;"
  echo "insert into _h select 'antes', ($H);"
  cat migrations/20261025000000_cert_qms_auditoria_interna.sql
  echo "insert into _h select 'con_migracion', ($H);"
  cat pruebas/prueba_qms_auditoria_interna.sql
  cat reversas/20261025000000_cert_qms_auditoria_interna_reversa.sql
  echo "insert into _h select 'despues', ($H);"
  cat <<'FIN'
do $f$ declare a text; c text; d text; r text; begin
  select h into a from _h where cuando = 'antes'; select h into c from _h where cuando = 'con_migracion'; select h into d from _h where cuando = 'despues';
  -- La API de gestión corta el mensaje hacia los 500 caracteres: se cuentan los OK y se muestran enteras solo las fallas.
  select count(*) filter (where t !~ 'FALLA') || ' de ' || count(*) || ' OK'
         || coalesce(' · FALLAS: ' || string_agg(t, ' || ' order by t) filter (where t ~ 'FALLA'), '')
    into r from _res;
  raise exception 'RESULTADO % ### REVERSA: antes=% con_migracion=% despues=% → %', r, left(a, 8), left(c, 8), left(d, 8),
    case when a = d and a <> c then 'IGUAL (OK)' else 'DISTINTA (FALLA)' end;
end $f$;
FIN
} > pruebas/ida_y_vuelta_qms_auditoria_interna.sql
echo "armado: $(wc -c < pruebas/ida_y_vuelta_qms_auditoria_interna.sql) bytes"
