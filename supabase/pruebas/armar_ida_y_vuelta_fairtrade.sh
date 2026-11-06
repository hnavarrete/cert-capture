#!/usr/bin/env bash
# Arma pruebas/ida_y_vuelta_fairtrade.sql: huella → migración → prueba → reversa → huella. El RAISE final deshace TODO.
# La huella cubre funciones, tablas y políticas de public (cert_*), compliance y attest, el conteo del catálogo y la
# fila «fairtrade» de attest.certifications: si la reversa deja algo distinto, sale «DISTINTA (FALLA)».
# Se corre desde supabase/:  bash pruebas/armar_ida_y_vuelta_fairtrade.sh
set -euo pipefail
H="($(cat pruebas/_huella_fairtrade.sql))"
{
  echo "-- IDA Y VUELTA de Fairtrade (generado por armar_ida_y_vuelta_fairtrade.sh). El RAISE final deshace TODO."
  echo "create temp table _res (t text); create temp table _h (cuando text, h text); grant insert, select on _res to authenticated;"
  echo "insert into _h select 'antes', ($H);"
  cat migrations/20261106000000_cert_fairtrade_formularios_y_precios.sql
  echo "insert into _h select 'con_migracion', ($H);"
  cat pruebas/prueba_fairtrade.sql
  echo "delete from compliance.cert_responses where client_slug = 'prueba-fairtrade';"
  cat reversas/20261106000000_cert_fairtrade_formularios_y_precios_reversa.sql
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
} > pruebas/ida_y_vuelta_fairtrade.sql
echo "armado: $(wc -c < pruebas/ida_y_vuelta_fairtrade.sql) bytes"
