// Capa 3 del marco antifraude — muestreo basado en riesgo para la inspección de campo.
// Ver docs/ANTIFRAUDE-VERACIDAD-DATOS-PRODUCTOR.md.
//
// VG no inspecciona todo (inviable) ni al azar (injusto e ineficiente). Decide A QUIÉN inspeccionar
// según el RIESGO que produjo la Capa 1 (fraud-rules-engine) y un PRESUPUESTO de inspección
// (capacidad del equipo de campo). AGNÓSTICO: vanilla JS, sin dependencias.
//
// Principios:
//  1. Censo de críticos: todo registro con flag crítico se inspecciona (no es opcional).
//  2. Proporcional al riesgo: mayor fracción de los de riesgo alto que de los medios.
//  3. Muestreo de disuasión: una fracción de los de bajo riesgo, para que el honesto sepa que
//     puede ser auditado (disuade el fraude oportunista). Es la clave de que la gamificación
//     no se vuelva un "todos mienten porque nadie revisa".
//  4. Determinista y AUDITABLE: la selección no usa azar opaco; usa un hash estable del id, de modo
//     que es reproducible y defendible ("se seleccionó por un criterio reproducible, no arbitrario").
//  5. Respeta el presupuesto, priorizando críticos > alto > medio > disuasión.

// hash estable (FNV-1a 32-bit) de un id -> [0,1). Reemplaza Math.random para que el muestreo sea
// reproducible y auditable (mismo input -> misma selección).
function stableUnit(id, salt = '') {
  let h = 0x811c9dc5
  const s = String(id) + '|' + salt
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i)
    h = Math.imul(h, 0x01000193)
  }
  return ((h >>> 0) % 100000) / 100000
}

const DEFAULTS = {
  presupuesto: Infinity,   // máximo de inspecciones (capacidad del equipo). Infinity = sin tope.
  frac_alto: 1.0,          // fracción de los de riesgo alto a inspeccionar
  frac_medio: 0.5,         // fracción de los de riesgo medio
  frac_disuasion: 0.1,     // fracción de los de bajo riesgo (muestreo de disuasión)
  salt: 'vg-rbs-v1'        // sal del hash (rotar por campaña para que no sea predecible quién cae)
}

const PRIORIDAD = { critico: 0, alto: 1, medio: 2, bajo: 3 }

/**
 * Selecciona los registros a inspeccionar en campo.
 *
 * @param {Array} items - [{ id, nivel_riesgo: 'critico'|'alto'|'medio'|'bajo', score?, nivel_verificacion? }]
 * @param {object} [opts] - ver DEFAULTS.
 * @returns {{ seleccionados, motivos, cobertura, presupuesto_usado, presupuesto, omitidos_por_presupuesto }}
 */
export function selectForInspection(items, opts = {}) {
  const o = { ...DEFAULTS, ...opts }
  const grupos = { critico: [], alto: [], medio: [], bajo: [] }
  for (const it of items) {
    const nivel = (it.nivel_riesgo && grupos[it.nivel_riesgo]) ? it.nivel_riesgo : 'bajo'
    grupos[nivel].push(it)
  }

  // dentro de cada grupo, ordenar por score desc (mayor riesgo primero) y desempatar por hash estable.
  const ordenar = (arr) => arr.slice().sort((a, b) =>
    (b.score || 0) - (a.score || 0) || (stableUnit(a.id, o.salt) - stableUnit(b.id, o.salt)))

  // candidatos por grupo según su fracción (críticos = censo; el resto por hash estable < fracción).
  const tomarFraccion = (arr, frac) => {
    if (frac >= 1) return ordenar(arr)
    if (frac <= 0) return []
    // los de score>0 entran por orden; los de score 0 entran por la lotería estable (disuasión).
    const conScore = ordenar(arr.filter(x => (x.score || 0) > 0))
    const sinScore = arr.filter(x => !(x.score || 0) > 0)
    const nObjetivo = Math.ceil(arr.length * frac)
    const elegidos = []
    for (const x of conScore) { if (elegidos.length >= nObjetivo) break; elegidos.push(x) }
    // completar con la lotería estable (los de menor hash caen)
    const loteria = sinScore.map(x => ({ x, u: stableUnit(x.id, o.salt) })).sort((a, b) => a.u - b.u)
    for (const { x } of loteria) { if (elegidos.length >= nObjetivo) break; elegidos.push(x) }
    return elegidos
  }

  const plan = [
    { nivel: 'critico', frac: 1.0, motivo: 'flag crítico: inspección obligatoria (censo)' },
    { nivel: 'alto', frac: o.frac_alto, motivo: 'riesgo alto: muestreo proporcional' },
    { nivel: 'medio', frac: o.frac_medio, motivo: 'riesgo medio: muestreo proporcional' },
    { nivel: 'bajo', frac: o.frac_disuasion, motivo: 'muestreo de disuasión' }
  ]

  const seleccionados = []
  const motivos = {}
  const cobertura = { critico: 0, alto: 0, medio: 0, bajo: 0 }
  let omitidos = 0

  for (const p of plan) {
    const cand = tomarFraccion(grupos[p.nivel], p.frac)
    for (const it of cand) {
      if (seleccionados.length >= o.presupuesto) { omitidos++; continue }
      seleccionados.push(it.id)
      motivos[it.id] = p.motivo
      cobertura[p.nivel]++
    }
  }

  return {
    seleccionados,
    motivos,
    cobertura,                                   // cuántos de cada nivel entraron
    presupuesto: o.presupuesto,
    presupuesto_usado: seleccionados.length,
    omitidos_por_presupuesto: omitidos           // si >0, log: NO se cubrió todo el plan (no silenciar)
  }
}

export default { selectForInspection }
