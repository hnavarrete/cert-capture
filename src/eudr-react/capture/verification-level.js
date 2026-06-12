// Capa 2 del marco antifraude — nivel de verificación y completitud verificada.
// Ver docs/ANTIFRAUDE-VERACIDAD-DATOS-PRODUCTOR.md.
//
// Resuelve la tensión "gamificación con seriedad": el marketplace paga por COMPLETITUD VERIFICADA,
// no por casillas marcadas. Cada respuesta/campo tiene un nivel de verificación 0..3; el factor de
// pago se calcula sobre el nivel ponderado, no sobre la completitud cruda. AGNÓSTICO: vanilla JS.
//
//   Nivel 0 — auto-declarado (sin evidencia)        -> NO paga
//   Nivel 1 — con evidencia que pasó la Capa 1       -> paga parcial
//   Nivel 2 — verificado por técnico VG en campo     -> paga mayor
//   Nivel 3 — auditado por tercero acreditado        -> paga completo

export const NIVEL = { AUTO: 0, EVIDENCIA: 1, CAMPO: 2, AUDITADO: 3 }

// factor de pago por nivel (calibrable). El nivel 0 NO paga: marcar sin evidencia no sirve.
export const FACTOR_PAGO_POR_NIVEL = { 0: 0.0, 1: 0.5, 2: 0.85, 3: 1.0 }

/**
 * Calcula el nivel de verificación de UN campo/respuesta a partir de su evidencia y estado.
 * Un flag CRÍTICO sin resolver degrada el nivel a 0 (no se puede confiar en el dato).
 *
 * @param {object} item
 * @param {boolean} item.declarado          - el productor respondió el campo.
 * @param {boolean} [item.tiene_evidencia]  - hay foto/doc adjunto y válido.
 * @param {boolean} [item.evidencia_paso_capa1] - la evidencia pasó la Capa 1 (geotag, dentro del polígono, etc.).
 * @param {boolean} [item.verificado_campo] - un técnico VG lo verificó en campo (≠ del que capturó: SoD).
 * @param {boolean} [item.auditado_tercero] - un auditor externo acreditado lo confirmó.
 * @param {boolean} [item.flag_critico]     - hay un flag crítico de Capa 1 sin resolver sobre este dato.
 * @returns {0|1|2|3}
 */
export function computeFieldLevel(item) {
  if (!item || !item.declarado) return NIVEL.AUTO
  if (item.flag_critico) return NIVEL.AUTO // dato no confiable hasta resolver el flag crítico
  if (item.auditado_tercero) return NIVEL.AUDITADO
  if (item.verificado_campo) return NIVEL.CAMPO
  if (item.tiene_evidencia && item.evidencia_paso_capa1 !== false) return NIVEL.EVIDENCIA
  return NIVEL.AUTO
}

/**
 * Completitud verificada de un conjunto de campos. Devuelve la cruda (todos los marcados), la
 * verificada (ponderada por nivel) y el factor de pago del marketplace.
 *
 * @param {Array} items - cada uno { key, peso=1, nivel } o { key, peso=1, ...flags para computeFieldLevel }
 * @param {object} [opts] - { factor=FACTOR_PAGO_POR_NIVEL }
 * @returns {{ total, declarados, cruda_pct, verificada_pct, pago_factor, por_nivel, faltan_evidencia }}
 */
export function computeVerifiedCompleteness(items, opts = {}) {
  const factor = opts.factor || FACTOR_PAGO_POR_NIVEL
  const total = items.length || 0
  if (!total) return { total: 0, declarados: 0, cruda_pct: 0, verificada_pct: 0, pago_factor: 0, por_nivel: { 0: 0, 1: 0, 2: 0, 3: 0 }, faltan_evidencia: [] }

  let sumaPeso = 0, declarados = 0, pesoDeclarado = 0, pagoPond = 0
  const porNivel = { 0: 0, 1: 0, 2: 0, 3: 0 }
  const faltanEvidencia = []

  for (const it of items) {
    const peso = it.peso || 1
    sumaPeso += peso
    const nivel = typeof it.nivel === 'number' ? it.nivel : computeFieldLevel(it)
    porNivel[nivel] = (porNivel[nivel] || 0) + 1
    if (nivel >= NIVEL.AUTO && (it.declarado || it.nivel >= 0)) { /* contado abajo */ }
    if (it.declarado || nivel > 0) { declarados++; pesoDeclarado += peso }
    pagoPond += peso * (factor[nivel] != null ? factor[nivel] : 0)
    if (nivel === NIVEL.AUTO && (it.declarado)) faltanEvidencia.push(it.key)
  }

  return {
    total,
    declarados,
    cruda_pct: Math.round((pesoDeclarado / sumaPeso) * 1000) / 10,        // % marcado (lo que un sistema ingenuo pagaría)
    verificada_pct: Math.round((pagoPond / sumaPeso) * 1000) / 10,        // % ponderado por nivel
    pago_factor: Math.round((pagoPond / sumaPeso) * 1000) / 1000,         // [0..1] factor de pago del marketplace
    por_nivel: porNivel,
    faltan_evidencia: faltanEvidencia                                     // campos marcados sin evidencia (la UI los señala)
  }
}

/**
 * Conecta la Capa 1 con la Capa 2: dado el resultado de evaluateRules y un mapa de qué flag-id
 * afecta a qué campo, marca `flag_critico` en los items correspondientes antes de calcular niveles.
 *
 * @param {Array} items   - items de completitud (con .key).
 * @param {object} evalResult - salida de evaluateRules() (tiene .flags).
 * @param {object} [flagFieldMap] - { 'rule_id': ['campo.key', ...] }. Si un flag crítico mapea a un campo, lo degrada.
 * @returns {Array} items con flag_critico propagado.
 */
export function applyFlagsToItems(items, evalResult, flagFieldMap = {}) {
  const criticos = new Set((evalResult.flags || []).filter(f => f.severidad === 'critical').map(f => f.id))
  if (!criticos.size) return items
  const camposAfectados = new Set()
  for (const id of criticos) for (const k of (flagFieldMap[id] || [])) camposAfectados.add(k)
  return items.map(it => camposAfectados.has(it.key) ? { ...it, flag_critico: true } : it)
}

export default { NIVEL, FACTOR_PAGO_POR_NIVEL, computeFieldLevel, computeVerifiedCompleteness, applyFlagsToItems }
