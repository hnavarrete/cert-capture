// Corre la IDA Y VUELTA de la migración Fairtrade en una base Postgres LOCAL (PGlite, en memoria), no en producción.
// Es el MISMO archivo que se correría en producción (pruebas/ida_y_vuelta_fairtrade.sql, termina con un RAISE que deshace
// todo), sobre el esqueleto de pruebas/local/esqueleto_supabase.sql.
//
// PGlite no es dependencia del repo: se instala aparte y se pasa su carpeta.
//   npm install --prefix <carpeta> @electric-sql/pglite@0.5.9
//   PGLITE_DIR=<carpeta>/node_modules/@electric-sql/pglite node supabase/pruebas/local/ida_y_vuelta_local.mjs
// (antes: cd supabase && bash pruebas/armar_ida_y_vuelta_fairtrade.sh)

import { readFileSync } from 'node:fs'
import { join, dirname, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const AQUI = dirname(fileURLToPath(import.meta.url))
if (!process.env.PGLITE_DIR) { console.error('Falta PGLITE_DIR (ver la cabecera)'); process.exit(2) }
const { PGlite } = await import(pathToFileURL(join(resolve(process.env.PGLITE_DIR), 'dist', 'index.js')).href)

const db = new PGlite()
const v = await db.query('select version()')
console.log('base local:', v.rows[0].version.split(' on ')[0])
await db.exec(readFileSync(join(AQUI, 'esqueleto_supabase.sql'), 'utf8'))
console.log('esqueleto cargado')

const ida = readFileSync(join(AQUI, '..', 'ida_y_vuelta_fairtrade.sql'), 'utf8')
let resultado = ''
try {
  await db.exec(ida)
  resultado = 'FALLA: la ida y vuelta terminó sin el RAISE final'
} catch (e) {
  resultado = String(e.message)
}
console.log('\n' + resultado.replace(' ### ', '\n').replace(/ \|\| /g, '\n   ') + '\n')

// Después del RAISE la base local quedó como antes: lo comprobamos de verdad.
const t = await db.query("select to_regclass('attest.precio_referencia') as tabla, (select count(*) from compliance.cert_form_defs) as n, (select version from attest.certifications where code = 'fairtrade') as version")
console.log('después del RAISE:', JSON.stringify(t.rows[0]))
const limpio = t.rows[0].tabla === null && Number(t.rows[0].n) === 2 && t.rows[0].version.startsWith('SPO v2.x')
const todoOk = /RESULTADO (\d+) de \1 OK/.test(resultado) && /IGUAL \(OK\)/.test(resultado) && limpio
console.log(todoOk ? 'IDA Y VUELTA LOCAL: OK' : 'IDA Y VUELTA LOCAL: FALLA')
process.exit(todoOk ? 0 : 1)
