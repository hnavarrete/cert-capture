// Capa 1 del marco antifraude — motor de reglas de plausibilidad/consistencia.
// Ver docs/ANTIFRAUDE-VERACIDAD-DATOS-PRODUCTOR.md.
//
// Evalúa respuestas AUTO-REPORTADAS del productor contra reglas declarativas y produce FLAGS con
// severidad. Detecta el fraude en el ORIGEN (la cadena de integridad solo prueba que no se alteró
// después; esto prueba plausibilidad de la verdad). AGNÓSTICO: vanilla JS, sin dependencias.
//
// R1 — el dato del campo es sagrado: este motor NUNCA bloquea el guardado. Los flags son señales
// para (a) el muestreo basado en riesgo (Capa 3) y (b) el nivel de verificación (Capa 2). Un flag
// no impide capturar; impide que el dato cuente como "verificado" sin revisión.

export const SEVERIDAD = { LOW: 'low', MEDIUM: 'medium', HIGH: 'high', CRITICAL: 'critical' }
const PESO_SEVERIDAD = { low: 1, medium: 3, high: 7, critical: 15 }

// ---------------------------------------------------------------------------
// Helpers geométricos SIN dependencias.
// IMPORTANTE (regla VG feedback_area_precision_sig): el área cadastral oficial es el campo AREA del
// SIG y NUNCA se recomputa. El área planar de aquí se usa SOLO para un check de plausibilidad
// ("¿difiere mucho de lo declarado?"), nunca como verdad cadastral.
// ---------------------------------------------------------------------------

function outerRing(geom) {
  if (!geom) return null
  if (Array.isArray(geom) && Array.isArray(geom[0])) {
    // ya es un anillo [[lng,lat],...] o un Polygon coordinates [[[lng,lat]...]]
    return Array.isArray(geom[0][0]) ? geom[0] : geom
  }
  if (geom.type === 'Polygon') return geom.coordinates && geom.coordinates[0]
  if (geom.type === 'MultiPolygon') return geom.coordinates && geom.coordinates[0] && geom.coordinates[0][0]
  if (geom.coordinates) return Array.isArray(geom.coordinates[0][0]) ? geom.coordinates[0] : geom.coordinates
  return null
}

function ringIsClosed(ring) {
  if (!ring || ring.length < 4) return false
  const a = ring[0], b = ring[ring.length - 1]
  return a[0] === b[0] && a[1] === b[1]
}

// área planar aproximada en m² (proyección equirectangular local). Solo para plausibilidad.
function planarAreaM2(ring) {
  if (!ring || ring.length < 4) return 0
  const lat0 = ring.reduce((s, p) => s + p[1], 0) / ring.length
  const mPerDegLat = 110540
  const mPerDegLng = 111320 * Math.cos((lat0 * Math.PI) / 180)
  let acc = 0
  for (let i = 0; i < ring.length - 1; i++) {
    const x1 = ring[i][0] * mPerDegLng, y1 = ring[i][1] * mPerDegLat
    const x2 = ring[i + 1][0] * mPerDegLng, y2 = ring[i + 1][1] * mPerDegLat
    acc += x1 * y2 - x2 * y1
  }
  return Math.abs(acc) / 2
}

function segmentsIntersect(p1, p2, p3, p4) {
  function ccw(a, b, c) { return (c[1] - a[1]) * (b[0] - a[0]) > (b[1] - a[1]) * (c[0] - a[0]) }
  return ccw(p1, p3, p4) !== ccw(p2, p3, p4) && ccw(p1, p2, p3) !== ccw(p1, p2, p4)
}

function ringSelfIntersects(ring) {
  if (!ring || ring.length < 5) return false
  const n = ring.length - 1 // último = primero
  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      if (Math.abs(i - j) <= 1) continue
      if (i === 0 && j === n - 1) continue // aristas adyacentes en el cierre
      if (segmentsIntersect(ring[i], ring[i + 1], ring[j], ring[j + 1])) return true
    }
  }
  return false
}

function pointInRing(pt, ring) {
  let inside = false
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const xi = ring[i][0], yi = ring[i][1], xj = ring[j][0], yj = ring[j][1]
    const intersect = (yi > pt[1]) !== (yj > pt[1]) &&
      pt[0] < ((xj - xi) * (pt[1] - yi)) / (yj - yi) + xi
    if (intersect) inside = !inside
  }
  return inside
}

function metersBetween(a, b) {
  const lat0 = ((a[1] + b[1]) / 2) * Math.PI / 180
  const dx = (a[0] - b[0]) * 111320 * Math.cos(lat0)
  const dy = (a[1] - b[1]) * 110540
  return Math.sqrt(dx * dx + dy * dy)
}

function minDistToRingM(pt, ring) {
  let min = Infinity
  for (const v of ring) min = Math.min(min, metersBetween(pt, v))
  return min
}

// ---------------------------------------------------------------------------
// Reglas declarativas. Cada regla:
//   { id, capa, severidad, titulo, aplica(ctx)->bool, evaluar(ctx)-> true(PASA)|false(FLAG)|null(no evaluable), mensaje(ctx)->string }
// ctx normalizado (el adapter por certificación llena `fields`):
//   ctx.fields: { area_declarada_ha, volumen_declarado_kg, cultivo, usa_riego, consumo_agua_m3,
//                 declara_sin_deforestacion, ... }
//   ctx.geom:   GeoJSON Polygon | coordinates
//   ctx.fotos:  [{ field, lat, lng, timestamp, photo_id }]
//   ctx.externo:{ deforestacion:{ overlap_post_cutoff_ha, fuente }, catastro_area_ha }
//   ctx.params: { area_tol_pct=20, foto_dist_max_m=300, rinde_max_kg_ha:{cacao,banano,...} }
// ---------------------------------------------------------------------------

const DEFAULT_PARAMS = {
  area_tol_pct: 20,
  foto_dist_max_m: 300,
  // rendimiento máximo plausible por cultivo (kg/ha/año). Calibrable; valores conservadores altos.
  rinde_max_kg_ha: { cacao: 3000, banano: 70000, cafe: 4000, palma: 30000, default: 100000 }
}

export const DEFAULT_RULES = [
  {
    id: 'geom_valida',
    capa: 1,
    severidad: SEVERIDAD.CRITICAL,
    titulo: 'Geometría del polígono válida',
    aplica: (c) => !!outerRing(c.geom),
    evaluar: (c) => {
      const r = outerRing(c.geom)
      if (!r) return null
      if (r.length < 4 || !ringIsClosed(r)) return false
      if (ringSelfIntersects(r)) return false
      return true
    },
    mensaje: () => 'El polígono está mal formado (anillo no cerrado, pocos vértices o auto-intersección). Posible dibujo inválido o manipulación.'
  },
  {
    id: 'geom_area_vs_declarada',
    capa: 1,
    severidad: SEVERIDAD.HIGH,
    titulo: 'Área del polígono coincide con el área declarada',
    aplica: (c) => !!outerRing(c.geom) && c.fields && c.fields.area_declarada_ha > 0,
    evaluar: (c) => {
      const r = outerRing(c.geom)
      const haGeom = planarAreaM2(r) / 10000
      const haDecl = c.fields.area_declarada_ha
      if (!(haGeom > 0)) return null
      const difPct = Math.abs(haGeom - haDecl) / haDecl * 100
      return difPct <= (c.params.area_tol_pct || DEFAULT_PARAMS.area_tol_pct)
    },
    mensaje: (c) => {
      const r = outerRing(c.geom)
      const haGeom = (planarAreaM2(r) / 10000).toFixed(2)
      return `El área del polígono (~${haGeom} ha) difiere del área declarada (${c.fields.area_declarada_ha} ha) más de lo tolerado. Verificar polígono o dato.`
    }
  },
  {
    id: 'geom_area_vs_catastro',
    capa: 1,
    severidad: SEVERIDAD.HIGH,
    titulo: 'Área declarada coincide con el catastro',
    aplica: (c) => c.externo && c.externo.catastro_area_ha > 0 && c.fields && c.fields.area_declarada_ha > 0,
    evaluar: (c) => {
      const difPct = Math.abs(c.fields.area_declarada_ha - c.externo.catastro_area_ha) / c.externo.catastro_area_ha * 100
      return difPct <= (c.params.area_tol_pct || DEFAULT_PARAMS.area_tol_pct)
    },
    mensaje: (c) => `El área declarada (${c.fields.area_declarada_ha} ha) no coincide con el catastro (${c.externo.catastro_area_ha} ha). Posible sobre-declaración de tierra.`
  },
  {
    id: 'balance_masa',
    capa: 1,
    severidad: SEVERIDAD.HIGH,
    titulo: 'Volumen declarado plausible para el área (anti-lavado)',
    aplica: (c) => c.fields && c.fields.volumen_declarado_kg > 0 && c.fields.area_declarada_ha > 0,
    evaluar: (c) => {
      const cultivo = (c.fields.cultivo || 'default').toLowerCase()
      const tabla = (c.params.rinde_max_kg_ha || DEFAULT_PARAMS.rinde_max_kg_ha)
      const rindeMax = tabla[cultivo] || tabla.default
      const maxPlausible = c.fields.area_declarada_ha * rindeMax
      return c.fields.volumen_declarado_kg <= maxPlausible
    },
    mensaje: (c) => `El volumen declarado (${c.fields.volumen_declarado_kg} kg) supera lo que el área (${c.fields.area_declarada_ha} ha) puede producir. Riesgo de lavado de producto no certificado.`
  },
  {
    id: 'deforestacion_satelital',
    capa: 1,
    severidad: SEVERIDAD.CRITICAL,
    titulo: 'Sin deforestación post-cutoff (cross-check satelital)',
    aplica: (c) => c.externo && c.externo.deforestacion && typeof c.externo.deforestacion.overlap_post_cutoff_ha === 'number',
    evaluar: (c) => {
      const overlap = c.externo.deforestacion.overlap_post_cutoff_ha
      // si declara sin deforestación pero el satélite ve pérdida forestal post-cutoff -> FLAG crítico
      if (c.fields && c.fields.declara_sin_deforestacion === true && overlap > 0) return false
      return overlap === 0 ? true : (c.fields && c.fields.declara_sin_deforestacion === false ? true : false)
    },
    mensaje: (c) => `El cross-check satelital detecta ${c.externo.deforestacion.overlap_post_cutoff_ha} ha de pérdida forestal posterior al corte (fuente: ${c.externo.deforestacion.fuente || 'n/d'}) en un polígono declarado libre de deforestación. Incumplimiento EUDR crítico.`
  },
  {
    id: 'foto_geotag_presente',
    capa: 1,
    severidad: SEVERIDAD.MEDIUM,
    titulo: 'Las fotos de evidencia tienen geotag',
    aplica: (c) => Array.isArray(c.fotos) && c.fotos.length > 0,
    evaluar: (c) => c.fotos.every(f => typeof f.lat === 'number' && typeof f.lng === 'number'),
    mensaje: () => 'Una o más fotos de evidencia no tienen geolocalización (EXIF/GPS). Una foto sin geotag no es evidencia verificable.'
  },
  {
    id: 'foto_dentro_poligono',
    capa: 1,
    severidad: SEVERIDAD.HIGH,
    titulo: 'Las fotos geotaggeadas caen dentro de la finca',
    aplica: (c) => !!outerRing(c.geom) && Array.isArray(c.fotos) && c.fotos.some(f => typeof f.lat === 'number'),
    evaluar: (c) => {
      const r = outerRing(c.geom)
      const conGeo = c.fotos.filter(f => typeof f.lat === 'number' && typeof f.lng === 'number')
      if (!conGeo.length) return null
      const tol = c.params.foto_dist_max_m || DEFAULT_PARAMS.foto_dist_max_m
      return conGeo.every(f => {
        const pt = [f.lng, f.lat]
        return pointInRing(pt, r) || minDistToRingM(pt, r) <= tol
      })
    },
    mensaje: () => 'Una o más fotos fueron tomadas fuera del polígono de la finca. Posible foto de otra ubicación.'
  },
  {
    id: 'consistencia_riego_agua',
    capa: 1,
    severidad: SEVERIDAD.MEDIUM,
    titulo: 'Consistencia riego vs. consumo de agua',
    aplica: (c) => c.fields && (c.fields.usa_riego === false) && typeof c.fields.consumo_agua_m3 === 'number',
    evaluar: (c) => !(c.fields.usa_riego === false && c.fields.consumo_agua_m3 > 0),
    mensaje: () => 'Declara que no usa riego pero reporta consumo de agua de riego. Inconsistencia entre campos.'
  }
]

/**
 * Evalúa una respuesta contra el set de reglas. Devuelve los flags disparados, un score de riesgo
 * ponderado por severidad, y un nivel de riesgo agregado. NO bloquea nada.
 *
 * @param {object} ctx - { fields, geom, fotos, externo, params, certificacion }
 * @param {Array}  [rules=DEFAULT_RULES]
 * @returns {{ flags, score, nivel_riesgo, evaluadas, no_evaluables, paso }}
 */
export function evaluateRules(ctx, rules = DEFAULT_RULES) {
  const c = { ...ctx, params: { ...DEFAULT_PARAMS, ...(ctx.params || {}) }, fields: ctx.fields || {} }
  const flags = []
  let evaluadas = 0, noEval = 0, score = 0
  for (const rule of rules) {
    let aplica = true
    try { aplica = rule.aplica ? !!rule.aplica(c) : true } catch { aplica = false }
    if (!aplica) continue
    let res
    try { res = rule.evaluar(c) } catch { res = null }
    if (res === null || res === undefined) { noEval++; continue }
    evaluadas++
    if (res === false) {
      const peso = PESO_SEVERIDAD[rule.severidad] || 1
      score += peso
      flags.push({
        id: rule.id,
        severidad: rule.severidad,
        titulo: rule.titulo,
        mensaje: (() => { try { return rule.mensaje(c) } catch { return rule.titulo } })()
      })
    }
  }
  let nivel = 'bajo'
  if (flags.some(f => f.severidad === SEVERIDAD.CRITICAL)) nivel = 'critico'
  else if (score >= 7) nivel = 'alto'
  else if (score >= 3) nivel = 'medio'
  return { flags, score, nivel_riesgo: nivel, evaluadas, no_evaluables: noEval, paso: flags.length === 0 }
}

export default { evaluateRules, DEFAULT_RULES, SEVERIDAD }
