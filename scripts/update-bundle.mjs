// Actualizador ADITIVO del bundle @vgsdk/cert-schemas (src/schemas.bundle.json).
//
// El generador original del bundle no quedó en el repo. Este script NO regenera
// desde cero (eso arriesgaría la anonimización #02 de los programas de contratante
// que ya está bien en el bundle): CARGA el bundle existente y le AGREGA, de forma
// idempotente:
//   1. el/los schema(s) nuevos que falten (hoy: PEFC manejo forestal), en el
//      mismo shape del bundle (_meta aplanado, secciones sin show_if, campos full);
//   2. su manifiesto + su entrada en reuso_compartidos + en certificaciones;
//   3. `rutas`: la hoja de ruta precomputada por cert (motor _roadmap.js), SOLO
//      para certs oficiales públicas (nunca contratante → evita filtrar nombres #02);
//   4. totales recomputados aditivamente.
// Verifica al final que no se filtre ningún nombre de cliente.
//
// Uso (sibling repos):  node scripts/update-bundle.mjs
// Fuente de verdad: ../../encuestador-eudr/frontend/src/form-schemas

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const BUNDLE = path.join(__dirname, '..', 'src', 'schemas.bundle.json')
const SRC = '../../encuestador-eudr/frontend/src/form-schemas'

const { SCHEMA_BY_KEY, CERTIFICACIONES, CERT_USA_CORE } = await import(`${SRC}/_index.js`)
const { roadmap } = await import(`${SRC}/_roadmap.js`)

const bundle = JSON.parse(fs.readFileSync(BUNDLE, 'utf8'))

// ── Transformar un schema fuente al shape del bundle ───────────────────────
function aShapeBundle(s) {
  const nCampos = (s.secciones || []).reduce((a, sec) => a + (sec.campos?.length || 0), 0)
  const nCP = (s.secciones || []).reduce((a, sec) => a + (sec.campos || []).filter(c => c.tipo === 'control_point').length, 0)
  return {
    form_key: s.form_key,
    certificacion: s.certificacion,
    cultivo: s.cultivo ?? null,
    titulo: s.titulo,
    descripcion: s.descripcion,
    schema_version: s.schema_version ?? 1,
    es_compartido: !!s.es_compartido,
    es_custom: !!s.es_custom,
    programa_owner: s.programa_owner ?? null,
    legacy: !!s.legacy,
    superseded_by: s.superseded_by ?? null,
    icono: s.icono ?? null,
    validation_status: s._meta?.validation_status ?? null,
    fuente_normativa: s._meta?.fuente_normativa ?? null,
    disclaimer: s._meta?.disclaimer ?? null,
    secciones: (s.secciones || []).map(sec => {
      const o = { key: sec.key, titulo: sec.titulo }
      if (sec.descripcion) o.descripcion = sec.descripcion
      o.repetible = !!sec.repetible
      o.campos = sec.campos || []
      return o
    }),
    n_campos: nCampos,
    n_control_points: nCP
  }
}

// ── 1+2. Agregar schemas nuevos (idempotente) ──────────────────────────────
const NUEVOS = ['pefc_manejo_forestal']
let agregados = 0
for (const key of NUEVOS) {
  if (bundle.schemas.some(x => x.form_key === key)) continue
  const src = SCHEMA_BY_KEY[key]
  if (!src) { console.warn('· no encontrado en fuente:', key); continue }
  bundle.schemas.push(aShapeBundle(src))
  agregados++
  // manifiesto (grupo PEFC) + reuso + certificaciones
  if (key === 'pefc_manejo_forestal') {
    const core = CERT_USA_CORE.PEFC_FM || []
    bundle.manifiestos.PEFC = {
      titulo: 'Programme for the Endorsement of Forest Certification',
      cultivos: ['FORESTAL_TECA', 'FORESTAL_GMELINA'],
      propios: ['pefc_manejo_forestal'],
      compartidos: core
    }
    for (const sharedKey of core) {
      bundle.reuso_compartidos[sharedKey] = bundle.reuso_compartidos[sharedKey] || []
      if (!bundle.reuso_compartidos[sharedKey].includes('PEFC')) bundle.reuso_compartidos[sharedKey].push('PEFC')
    }
    const certDef = CERTIFICACIONES.find(c => c.key === 'PEFC_FM')
    if (certDef && !bundle.certificaciones.some(c => c.key === 'PEFC_FM')) bundle.certificaciones.push(certDef)
  }
}

// ── 3. rutas precomputadas (solo certs oficiales públicas) ─────────────────
const CERTS_RUTA = ['EUDR', 'FSC', 'PEFC', 'RFA', 'USDA_ORGANIC', 'GLOBAL_GAP', 'MARBETE_AGROCALIDAD']
bundle.rutas = {}
for (const cert of CERTS_RUTA) {
  try { bundle.rutas[cert] = roadmap(cert) } catch (e) { console.warn('· ruta falló para', cert, e.message) }
}

// ── 4. totales aditivos ────────────────────────────────────────────────────
bundle.totales = {
  n_formularios: bundle.schemas.length,
  n_campos: bundle.schemas.reduce((a, s) => a + (s.n_campos || 0), 0),
  n_control_points: bundle.schemas.reduce((a, s) => a + (s.n_control_points || 0), 0),
  validados_oficial: bundle.schemas.filter(s => s.validation_status === 'VALIDADO_OFICIAL').length
}
bundle.version = '0.2.0'

// ── Verificación de fuga de nombres de cliente (#02) ───────────────────────
const PROHIBIDOS = /cargill|barry|callebaut|promise verified|nestl[eé]|ofi\b/i
const leak = JSON.stringify(bundle).match(PROHIBIDOS)
if (leak) { console.error('ABORTA: posible nombre de cliente en el bundle →', leak[0]); process.exit(1) }

fs.writeFileSync(BUNDLE, JSON.stringify(bundle, null, 0))
console.log('OK · schemas agregados:', agregados, '| total formularios:', bundle.totales.n_formularios, '| validados:', bundle.totales.validados_oficial)
console.log('rutas:', Object.keys(bundle.rutas).join(', '))
console.log('PEFC en bundle:', bundle.schemas.some(s => s.form_key === 'pefc_manejo_forestal'))
console.log('sin fuga de nombres de cliente: OK')
