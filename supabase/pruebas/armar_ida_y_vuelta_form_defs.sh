#!/usr/bin/env bash
# Arma pruebas/ida_y_vuelta_form_defs.sql: huella (esquema + conteo del catálogo) → migración → prueba → reversa → huella.
# La migración solo agrega datos: la huella del esquema no cambia, por eso se le suma el conteo de cert_form_defs.
set -euo pipefail
H="($(cat pruebas/_huella_cert.sql)) || ':' || (select count(*)::text from compliance.cert_form_defs)"
{
  echo "-- IDA Y VUELTA del catálogo al día con la app (generado por armar_ida_y_vuelta_form_defs.sh). El RAISE final deshace TODO."
  echo "create temp table _res (t text); create temp table _h (cuando text, h text); grant insert, select on _res to authenticated;"
  echo "insert into _h select 'antes', ($H);"
  cat migrations/20261026019000_cert_form_defs_al_dia_con_la_app.sql
  echo "insert into _h select 'con_migracion', ($H);"
  cat pruebas/prueba_form_defs_al_dia.sql
  echo "delete from compliance.cert_responses where client_slug = 'prueba-form-defs';"
  cat reversas/20261026019000_cert_form_defs_al_dia_con_la_app_reversa.sql
  echo "insert into _h select 'despues', ($H);"
  cat <<'FIN'
do $f$ declare a text; c text; d text; r text; begin
  select h into a from _h where cuando = 'antes'; select h into c from _h where cuando = 'con_migracion'; select h into d from _h where cuando = 'despues';
  select count(*) filter (where t !~ 'FALLA') || ' de ' || count(*) || ' OK'
         || coalesce(' · FALLAS: ' || string_agg(t, ' || ' order by t) filter (where t ~ 'FALLA'), '')
    into r from _res;
  raise exception 'RESULTADO % ### REVERSA: antes=% con_migracion=% despues=% → %', r, right(a, 12), right(c, 12), right(d, 12),
    case when a = d and a <> c then 'IGUAL (OK)' else 'DISTINTA (FALLA)' end;
end $f$;
FIN
} > pruebas/ida_y_vuelta_form_defs.sql
echo "armado: $(wc -c < pruebas/ida_y_vuelta_form_defs.sql) bytes"
