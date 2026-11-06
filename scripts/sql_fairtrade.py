# Arma los bloques de DATOS de la migración Fairtrade a partir del bundle (una sola fuente, dos salidas):
#   · las filas de attest.precio_referencia  ← bundle.referencias.fairtrade_precios (precios_minimos_primas.json)
#   · las filas de compliance.cert_form_defs ← los 8 formularios FAIRTRADE del bundle
# Reemplaza, DENTRO de la migración, el bloque entre las marcas «>>> DATOS GENERADOS» y «<<< FIN DE LOS DATOS GENERADOS».
#   python scripts/sql_fairtrade.py
import json, pathlib

RAIZ = pathlib.Path(__file__).resolve().parent.parent
b = json.loads((RAIZ / 'src' / 'schemas.bundle.json').read_text(encoding='utf-8'))


def q(v):
    if v is None:
        return 'null'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return repr(v)
    return "'" + str(v).replace("'", "''") + "'"


COLS = ['id', 'programa', 'producto', 'forma', 'calidad', 'origen', 'pais', 'alcance', 'base', 'punto', 'unidad', 'moneda',
        'precio_minimo', 'precio_minimo_texto', 'prima', 'prima_porcentaje', 'prima_base', 'diferencial_organico',
        'vigente_desde', 'vigente_hasta', 'fuente_documento', 'fuente_url', 'consultado_el', 'certeza', 'notas']
filas = b['referencias']['fairtrade_precios']['filas']
out = ['-- >>> DATOS GENERADOS por scripts/sql_fairtrade.py desde src/schemas.bundle.json (no editar a mano)',
       f'insert into attest.precio_referencia ({", ".join(COLS)})', 'values']
out.append(',\n'.join('  (' + ', '.join(q(f.get(c)) for c in COLS) + ')' for f in filas))
out.append('on conflict (id) do nothing;')
out.append('')
ft = [s for s in b['schemas'] if s['certificacion'] == 'FAIRTRADE']
out.append('insert into compliance.cert_form_defs (form_key, certificacion, cultivo, titulo, schema_version, es_compartido, es_custom,')
out.append('                                       programa_owner, legacy, validation_status, fuente_normativa, n_campos, n_control_points)')
out.append('values')
out.append(',\n'.join('  (' + ', '.join(q(x) for x in [s['form_key'], s['certificacion'], s['cultivo'], s['titulo'], s.get('schema_version', 1),
                                                       bool(s.get('es_compartido')), bool(s.get('es_custom')), s.get('programa_owner'), bool(s.get('legacy')),
                                                       s.get('validation_status'), s.get('fuente_normativa'), s.get('n_campos'), s.get('n_control_points')]) + ')'
                      for s in sorted(ft, key=lambda s: s['form_key'])))
out.append('on conflict (form_key) do nothing;')
out.append('-- <<< FIN DE LOS DATOS GENERADOS')
MIG = RAIZ / 'supabase' / 'migrations' / '20261106000000_cert_fairtrade_formularios_y_precios.sql'
texto = MIG.read_text(encoding='utf-8')
i, j = texto.index('-- >>> DATOS GENERADOS'), texto.index('-- <<< FIN DE LOS DATOS GENERADOS')
j = texto.index('\n', j) + 1
MIG.write_text(texto[:i] + '\n'.join(out) + '\n' + texto[j:], encoding='utf-8', newline='\n')
print(len(filas), 'precios y', len(ft), 'formularios escritos en', MIG.name)
