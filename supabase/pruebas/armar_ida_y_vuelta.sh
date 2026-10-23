#!/usr/bin/env bash
# Arma pruebas/ida_y_vuelta_qms_registro_miembros.sql: huella → migración → prueba → reversa → huella.
# El RAISE final deshace TODO; su mensaje trae los resultados. Uso: bash pruebas/armar_ida_y_vuelta.sh (desde supabase/)
set -euo pipefail
H="$(cat pruebas/_huella_cert.sql)"
{
  echo "-- IDA Y VUELTA del registro de miembros del QMS (generado por armar_ida_y_vuelta.sh). El RAISE final deshace TODO."
  echo "create temp table _res (t text); create temp table _h (cuando text, h text); grant insert, select on _res to authenticated;"
  echo "insert into _h select 'antes', ($H);"
  cat migrations/20261023000000_cert_qms_registro_miembros_y_auditor.sql
  echo "insert into _h select 'con_migracion', ($H);"
  cat pruebas/prueba_qms_registro_miembros.sql
  cat reversas/20261023000000_cert_qms_registro_miembros_y_auditor_reversa.sql
  echo "insert into _h select 'despues', ($H);"
  cat <<'FIN'
do $f$ declare a text; c text; d text; r text; begin
  select h into a from _h where cuando = 'antes'; select h into c from _h where cuando = 'con_migracion'; select h into d from _h where cuando = 'despues';
  select string_agg(t, ' || ' order by t) into r from _res;
  raise exception 'RESULTADO % ### REVERSA: antes=% con_migracion=% despues=% → %', r, left(a, 8), left(c, 8), left(d, 8),
    case when a = d and a <> c then 'IGUAL (OK)' else 'DISTINTA (FALLA)' end;
end $f$;
FIN
} > pruebas/ida_y_vuelta_qms_registro_miembros.sql
echo "armado: $(wc -c < pruebas/ida_y_vuelta_qms_registro_miembros.sql) bytes"
