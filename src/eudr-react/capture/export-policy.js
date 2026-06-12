// Política de exportación — implementa la regla interna de monetización.
// Ver docs/INTERNO-monetizacion-exportacion-y-bloqueo-preguntas.md (INTERNO, no publicar).
//
// Tres activos: respuestas del productor (suyas, free, portables) · molde/estructura (IP de VG) ·
// exportación cert-ready (servicio de VG, pago). Este módulo aplica los niveles + EL BLOQUEO de la
// descarga masiva del catálogo de preguntas en blanco. AGNÓSTICO: vanilla JS, sin dependencias.

export const EXPORT_KIND = {
  CRUDO_PRODUCTOR: 'crudo_productor', // Free — las respuestas del productor (portabilidad LOPDP)
  CERT_READY: 'cert_ready',           // Pago — entregable en el formato del certificador (DDS/OSP/checklist)
  COMPARTIR: 'compartir'              // Pago/marketplace — grant + entregable sellado
}

const PLANES_PAGOS = new Set(['lite', 'pro', 'enterprise'])

/**
 * ¿Puede el usuario ejecutar este tipo de exportación?
 * @param {string} kind - EXPORT_KIND.*
 * @param {object} ctx  - { plan, consent }
 * @returns {{ allowed, tier, reason, requiresPlan?, requiresConsent? }}
 */
export function exportPolicy(kind, ctx = {}) {
  const plan = (ctx.plan || 'free').toLowerCase()
  if (kind === EXPORT_KIND.CRUDO_PRODUCTOR) {
    // Siempre permitido: es el dato del productor. Portabilidad (LOPDP) + farmer-owned.
    return { allowed: true, tier: 'free', reason: 'Portabilidad de los datos del productor.' }
  }
  if (kind === EXPORT_KIND.CERT_READY) {
    const ok = PLANES_PAGOS.has(plan)
    return {
      allowed: ok, tier: 'pago', requiresPlan: !ok,
      reason: ok ? 'Servicio de exportación al formato del certificador.'
        : 'El entregable en el formato exacto del certificador requiere un plan de pago.'
    }
  }
  if (kind === EXPORT_KIND.COMPARTIR) {
    const plOk = PLANES_PAGOS.has(plan)
    const coOk = ctx.consent === true
    return {
      allowed: plOk && coOk, tier: 'pago', requiresPlan: !plOk, requiresConsent: !coOk,
      reason: (plOk && coOk) ? 'Compartir con consentimiento del productor.'
        : 'Compartir requiere plan de pago y consentimiento explícito del productor.'
    }
  }
  return { allowed: false, reason: 'Tipo de exportación desconocido.' }
}

/**
 * Export CRUDO del productor: SOLO sus respuestas (campo + valor), sin el molde completo (sin los
 * criterios verbatim ni las preguntas que no respondió). Cumple portabilidad sin regalar el IP de VG.
 * @param {Array} respuestas - cert_responses del productor.
 * @returns {Array} filas { form_key, certificacion, campo, valor } (el caller serializa a CSV/JSON).
 */
export function exportRespuestasProductor(respuestas) {
  const rows = []
  for (const r of (respuestas || [])) {
    const data = r.data || {}
    for (const [campo, valor] of Object.entries(data)) {
      rows.push({
        form_key: r.form_key, certificacion: r.certificacion, campo,
        valor: Array.isArray(valor) ? valor.join('; ') : valor
      })
    }
  }
  return rows
}

/**
 * EL BLOQUEO. Niega cualquier intento de exportar el CATÁLOGO DE PREGUNTAS EN BLANCO (el molde de VG).
 * Heurística de "volcado de molde": pide explícitamente el molde/criterios, o pide preguntas en blanco
 * (sin respuestas) de uno o más formularios. NO bloquea el export del dato del productor.
 * @param {object} req - { soloMolde, incluirCriterios, incluirPreguntas, formularios:[], respuestas:[] }
 * @throws si el pedido es un volcado del catálogo.
 */
export function assertNoBulkQuestionDump(req = {}) {
  if (req.soloMolde || req.incluirCriterios) {
    throw new Error('[export-policy] Bloqueado: el catálogo de preguntas/criterios (molde de VG) no se exporta.')
  }
  const nResp = (req.respuestas || []).length
  const nForms = (req.formularios || []).length
  if (req.incluirPreguntas && nResp === 0 && nForms >= 1) {
    throw new Error('[export-policy] Bloqueado: descarga masiva de preguntas en blanco no permitida.')
  }
  return true
}

/**
 * Sirve SOLO lo necesario para capturar un formulario (on-demand), sin los criterios verbatim ni el
 * catálogo entero. Reduce la exposición del molde en el cliente (entregar un formulario, no las 1.734
 * preguntas). El criterio normativo completo se omite (es parte del IP que no viaja al cliente).
 * @param {object} schema
 */
export function questionsForCapture(schema) {
  if (!schema) return null
  return {
    form_key: schema.form_key, certificacion: schema.certificacion, titulo: schema.titulo,
    secciones: (schema.secciones || []).map(s => ({
      key: s.key, titulo: s.titulo, descripcion: s.descripcion,
      campos: (s.campos || []).map(c => ({
        key: c.key, label: c.label, tipo: c.tipo, opciones: c.opciones,
        required: c.required, unidad: c.unidad, help: c.help
        // NOTA: se omite `criterio` (texto normativo verbatim) — es IP de VG, no viaja al cliente.
      }))
    }))
  }
}

/**
 * Configuración de marca de agua para el preview cert-ready (patrón Canva: dejar VER un borrador
 * marcado antes de pagar). Plan de pago => sin marca de agua (entregable válido). Free => marcado.
 * @param {object} ctx - { plan }
 */
export function watermarkConfig(ctx = {}) {
  const plan = (ctx.plan || 'free').toLowerCase()
  const pagado = PLANES_PAGOS.has(plan)
  return {
    aplica: !pagado,
    texto: pagado ? null : 'VISTA PREVIA · VG · NO VÁLIDO PARA ENTREGA',
    nota: pagado ? null : 'Borrador. El entregable válido para el certificador requiere un plan de pago.'
  }
}

/**
 * Genera el HTML imprimible del preview cert-ready de UNA respuesta. Si el plan es free, superpone
 * la marca de agua diagonal. El productor VE cómo quedaría el entregable antes de pagar (sube conversión,
 * baja la sensación de bloqueo). El cert-ready oficial (server-side, pago) sale sin marca + con el sello.
 * @param {object} schema  - el form-schema (para los labels de las secciones/campos).
 * @param {object} respuesta - el cert_response { data, certificacion, ... }.
 * @param {object} ctx - { plan, productor_id, finca_id }
 * @returns {string} HTML autocontenido.
 */
export function buildCertReadyPreviewHtml(schema, respuesta, ctx = {}) {
  const wm = watermarkConfig(ctx)
  const data = (respuesta && respuesta.data) || {}
  const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))
  let filas = ''
  for (const sec of (schema.secciones || [])) {
    let campos = ''
    for (const c of (sec.campos || [])) {
      const key = sec.key + '.' + c.key
      const v = data[key]
      if (v == null || v === '' || (Array.isArray(v) && !v.length)) continue
      campos += `<tr><td class="k">${esc(c.label || c.key)}</td><td class="v">${esc(Array.isArray(v) ? v.join('; ') : v)}</td></tr>`
    }
    if (campos) filas += `<tr><td colspan="2" class="sec">${esc(sec.titulo || sec.key)}</td></tr>${campos}`
  }
  const wmCss = wm.aplica ? `body::before{content:"${esc(wm.texto)}";position:fixed;top:45%;left:50%;transform:translate(-50%,-50%) rotate(-30deg);font-size:34px;font-weight:800;color:rgba(220,40,40,.16);white-space:nowrap;pointer-events:none;z-index:9999}` : ''
  return `<!doctype html><html lang="es"><head><meta charset="utf-8"><title>${esc(schema.titulo || 'Certificación')} — VG</title>
<style>body{font-family:Inter,system-ui,sans-serif;color:#0f172a;max-width:760px;margin:24px auto;padding:0 16px}
h1{color:#0c1220;font-size:20px;border-bottom:3px solid;border-image:linear-gradient(90deg,#1BABE1,#9FC834)1;padding-bottom:8px}
.meta{color:#64748b;font-size:12px;margin:6px 0 14px}table{width:100%;border-collapse:collapse;font-size:13px}
td{padding:7px 10px;border-bottom:1px solid #e6ebf2;vertical-align:top}.sec{background:#0c1220;color:#fff;font-weight:700}
.k{color:#475569;width:46%}.v{font-weight:600}.foot{margin-top:18px;font-size:11px;color:#94a3b8}${wmCss}</style></head>
<body><h1>${esc(schema.titulo || schema.certificacion)}</h1>
<div class="meta">Certificación: ${esc(respuesta.certificacion || schema.certificacion)} · Productor: ${esc(ctx.productor_id || '—')} · Finca: ${esc(ctx.finca_id || '—')}</div>
<table>${filas || '<tr><td>Sin datos capturados aún.</td></tr>'}</table>
${wm.nota ? `<div class="foot">${esc(wm.nota)}</div>` : '<div class="foot">Entregable VG · cadena de integridad.</div>'}</body></html>`
}

export default { EXPORT_KIND, exportPolicy, exportRespuestasProductor, assertNoBulkQuestionDump, questionsForCapture, watermarkConfig, buildCertReadyPreviewHtml }
