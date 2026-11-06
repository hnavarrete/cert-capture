// Fairtrade en la app (6-nov-2026): el bundle trae los 8 formularios y la tabla de Precios Mínimos y Primas, y la
// lógica de vigencias elige la fila correcta y nunca usa lo no verificado.
//   node pruebas/test_fairtrade.mjs

import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { precioVigente, vigentes, proximos, primaDeVenta, usableEnCalculo, textoPrecio, textoPrima, hoyEcuador } from '../src/fairtrade-precios.js'

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..')
const bundle = JSON.parse(readFileSync(join(RAIZ, 'src', 'schemas.bundle.json'), 'utf8'))
let fallos = 0, n = 0
const ok = (c, s, d) => { n++; if (c) console.log('  OK    ' + s); else { fallos++; console.log('  FALLA ' + s + (d !== undefined ? '  ->  ' + d : '')) } }

console.log('\n== el bundle ==')
const ft = bundle.schemas.filter(s => s.certificacion === 'FAIRTRADE')
ok(ft.length === 8, '8 formularios Fairtrade en el bundle', ft.length)
ok(bundle.certificaciones.some(c => c.key === 'FAIRTRADE'), 'FAIRTRADE en certificaciones')
ok(bundle.manifiestos.FAIRTRADE?.propios.length === 8, 'manifiesto FAIRTRADE')
ok(!!bundle.rutas.FAIRTRADE && bundle.rutas.FAIRTRADE.pilares.length === 4, 'hoja de ruta de FAIRTRADE con 4 pilares')
const cp = k => bundle.schemas.find(s => s.form_key === k)?.n_control_points
ok(cp('fairtrade_spo_organizacion') === 151 && cp('fairtrade_hl_empresa') === 189, 'SPO 151 y HL 189 puntos de control', cp('fairtrade_spo_organizacion') + '/' + cp('fairtrade_hl_empresa'))
const ref = bundle.referencias?.fairtrade_precios
ok(ref && ref.filas.length === 64, 'la tabla de precios viaja en bundle.referencias (64 filas)', ref?.filas.length)
ok(!ft.some(s => JSON.stringify(s).includes('precio_minimo')), 'ningún formulario lleva Precios Mínimos')
ok(!/cargill|barry|callebaut|promise verified/i.test(JSON.stringify(ft)), 'sin nombres de clientes (#02)')

console.log('\n== la fila vigente según la fecha ==')
const F = ref.filas
const banEc = (base, calidad = 'convencional') => ({ producto: 'banano', forma: 'fresco', calidad, pais: 'Ecuador', base, punto: null })
ok(precioVigente(F, banEc('EXW'), '2026-11-06')?.precio_minimo === 7.85, 'banano Ecuador EXW el 6-nov-2026: 7,85 USD/caja')
ok(precioVigente(F, banEc('EXW'), '2026-12-31')?.precio_minimo === 7.85, '… el 31-dic-2026 todavía 7,85 (vigente_hasta inclusivo)')
ok(precioVigente(F, banEc('EXW'), '2027-01-01')?.precio_minimo === 8.30, '… el 1-ene-2027: 8,30')
ok(precioVigente(F, banEc('EXW', 'organico'), '2026-11-06')?.precio_minimo === 10.65, 'banano orgánico EXW 2026: 10,65')
ok(precioVigente(F, banEc('EXW'), '2026-11-06')?.prima === 1, 'Prima del banano: 1 USD por caja')
ok(precioVigente(F, { producto: 'banano', calidad: 'convencional', pais: 'Ecuador', base: 'FOB', punto: 'Posorja, desde El Oro' }, '2027-03-01')?.precio_minimo === 12.90,
  'banano FOB 2027 desde El Oro a Posorja: 12,90')
const cacao = { producto: 'cacao', forma: 'grano', calidad: 'convencional', base: 'FOB' }
ok(precioVigente(F, cacao, '2026-06-10')?.prima === 240, 'cacao el 10-jun-2026: Prima 240 USD/t')
ok(precioVigente(F, cacao, '2026-06-11')?.prima === 275 && precioVigente(F, cacao, '2026-06-11')?.precio_minimo === 3500, 'cacao desde el 11-jun-2026: 3.500 y Prima 275')
ok(precioVigente(F, cacao, '2025-06-01') === null, 'cacao antes del 1-oct-2025: la fila de 2.400 es «parcial», no se usa (null)')
ok(precioVigente(F, { ...cacao, calidad: 'organico' }, '2026-11-06')?.diferencial_organico === 450, 'cacao orgánico: diferencial +450')
const cafe = { producto: 'cafe', forma: 'arabica_lavado', calidad: 'convencional' }
ok(precioVigente(F, cafe, '2026-11-30')?.precio_minimo === 1.8, 'arábica lavado el 30-nov-2026: 1,80 USD/lb')
ok(precioVigente(F, cafe, '2026-12-01')?.precio_minimo === 2, '… desde el 1-dic-2026: 2,00')
ok(precioVigente(F, { producto: 'flores', forma: 'tallos', base: 'FOB' }, '2026-11-06')?.prima_porcentaje === 10, 'flores FOB: Prima 10 %')
ok(precioVigente(F, { producto: 'flores', forma: 'tallos', base: 'subasta' }, '2026-11-06')?.prima_porcentaje === 6, 'flores en subasta: Prima 6 %')

console.log('\n== lo no verificado nunca entra en cálculos ==')
const lwrp = F.find(f => f.certeza === 'por_verificar')
ok(lwrp && !usableEnCalculo(lwrp) && primaDeVenta(lwrp, 100) === null, 'la fila «por_verificar» no calcula prima')
ok(precioVigente(F, { producto: 'banano', forma: 'salario_digno_referencia' }, '2027-06-01') === null, 'precioVigente no devuelve la fila por verificar')
ok(primaDeVenta(precioVigente(F, banEc('EXW'), '2026-11-06'), 1000) === 1000, 'prima de 1.000 cajas: 1.000 USD')
ok(primaDeVenta(precioVigente(F, { producto: 'flores', forma: 'tallos', base: 'FOB' }, '2026-11-06'), 1000, 0.30) === 30, 'prima de 1.000 tallos a 0,30: 30 (10 %)')
let lanzo = false
try { precioVigente(F, { producto: 'banano', pais: 'Ecuador', base: 'FOB' }, '2026-11-06') } catch { lanzo = true }
ok(lanzo, 'un criterio ambiguo (varios puertos) avisa en vez de elegir uno a ciegas')

console.log('\n== listas de la pantalla ==')
ok(vigentes(F, '2026-11-06', 'cafe').length === 8, 'café vigente el 6-nov-2026: 8 filas (4 tipos × convencional y orgánico)')
ok(proximos(F, '2026-11-06', 'cafe').every(f => f.vigente_desde === '2026-12-01'), 'cambios anunciados del café: 1-dic-2026')
ok(textoPrecio(precioVigente(F, cacao, '2026-11-06')) === 'USD 3.500 por t', 'texto del precio del cacao', textoPrecio(precioVigente(F, cacao, '2026-11-06')))
ok(textoPrima(precioVigente(F, banEc('EXW'), '2026-11-06')) === 'USD 1 por caja 18,14 kg', 'texto de la prima del banano', textoPrima(precioVigente(F, banEc('EXW'), '2026-11-06')))
ok(/^\d{4}-\d{2}-\d{2}$/.test(hoyEcuador()), 'hoyEcuador da AAAA-MM-DD')

console.log('\n' + '='.repeat(60))
console.log(fallos === 0 ? `FAIRTRADE EN LA APP OK — ${n} comprobaciones` : `${fallos} FALLAS de ${n}`)
console.log('='.repeat(60) + '\n')
process.exit(fallos === 0 ? 0 : 1)
