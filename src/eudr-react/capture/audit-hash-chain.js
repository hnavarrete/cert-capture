// Cadena de integridad audit-grade para respuestas de certificación (item P0 5.8).
//
// Para que VG sea ENTE OFICIAL de certificación/auditoría, los datos capturados deben
// ser INALTERABLES y demostrablemente íntegros. Este módulo implementa:
//
//  1. Hash SHA-256 canónico de cada respuesta (data + geom + fotos + metadata).
//  2. Cadena de hashes (hash chain): cada respuesta incluye el hash de la anterior,
//     formando una cadena inmutable por (client_slug, form_key). Si alguien altera o
//     borra una respuesta, la cadena se rompe y la manipulación es detectable.
//  3. Sello de tiempo RFC 3161 (TimeStamp Authority): hook para sellar el hash con una
//     TSA externa y obtener un token verificable de "este dato existía en este momento".
//
// AGNÓSTICO de framework: usa WebCrypto (crypto.subtle), disponible en navegador,
// React Native (con polyfill) y Node 18+. Sin dependencias.

// --- Serialización canónica (orden estable de claves para hash reproducible) ---
function canonical(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value)
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']'
  const keys = Object.keys(value).sort()
  return '{' + keys.map(k => JSON.stringify(k) + ':' + canonical(value[k])).join(',') + '}'
}

// --- SHA-256 hex (WebCrypto) ---
async function sha256hex(text) {
  const enc = new TextEncoder().encode(text)
  const buf = await (globalThis.crypto?.subtle?.digest('SHA-256', enc))
  if (!buf) throw new Error('[audit-hash] WebCrypto no disponible; usar polyfill en este entorno')
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, '0')).join('')
}

/**
 * Calcula el hash de integridad de una respuesta, encadenado al hash previo.
 * El payload que se sella incluye lo que define la respuesta (no los campos de
 * estado que cambian por sync): local_id, form_key, certificacion, client_slug,
 * producer_id, finca_id, data, fotos (refs), geom, timestamp de captura.
 *
 * @param {object} record    - la respuesta (cert_response).
 * @param {string} prevHash  - hash de la respuesta anterior en la cadena ('' si es la primera).
 * @returns {Promise<string>} hash SHA-256 hex de esta respuesta.
 */
export async function computeAuditHash(record, prevHash = '') {
  const payload = {
    local_id: record.local_id,
    form_key: record.form_key,
    certificacion: record.certificacion,
    client_slug: record.client_slug ?? null,
    producer_id: record.producer_id ?? null,
    finca_id: record.finca_id ?? null,
    data: record.data ?? {},
    fotos: (record.fotos ?? []).map(f => f.photo_id || f.field || f),
    geom: record.geom ?? null,
    timestamp_creacion: record.Timestamp_Creacion ?? record.timestamp_creacion ?? null,
    prev_hash: prevHash || ''
  }
  return sha256hex(canonical(payload))
}

/**
 * Verifica una cadena de respuestas: recalcula cada hash y confirma el encadenamiento.
 * Devuelve { ok, brokenAt } — brokenAt = local_id de la primera respuesta alterada.
 *
 * @param {Array} chain - respuestas ordenadas por created_at ascendente, con .audit_hash.
 */
export async function verifyChain(chain) {
  let prev = ''
  for (const r of chain) {
    const expected = await computeAuditHash(r, prev)
    if (r.audit_hash && r.audit_hash !== expected) {
      return { ok: false, brokenAt: r.local_id, expected, found: r.audit_hash }
    }
    prev = r.audit_hash || expected
  }
  return { ok: true, brokenAt: null }
}

/**
 * Sella el hash con una TimeStamp Authority RFC 3161 (sello de tiempo verificable).
 * Implementación pendiente de la TSA elegida (ver docs/SPEC-AUDIT-HASH-RFC3161.md).
 * Hasta integrar la TSA, devuelve un sello local con marca de tiempo del servidor
 * (no es RFC 3161 completo, pero deja el campo poblado y la estructura lista).
 *
 * @param {string} auditHash - el hash SHA-256 de la respuesta.
 * @param {object} opts       - { tsaUrl } endpoint de la TSA (FreeTSA, DigiCert, etc.).
 * @returns {Promise<{ seal, tsa, sealed_at, rfc3161 }>}
 */
export async function timestampSeal(auditHash, opts = {}) {
  // RFC 3161 real requiere construir un TimeStampReq (DER) y POST a la TSA con
  // Content-Type application/timestamp-query, parsear el TimeStampResp. Ver la spec.
  // Placeholder verificable hasta integrar la TSA:
  if (opts.tsaUrl) {
    // Hook: aquí iría la llamada real a la TSA. Se deja para la integración server-side
    // (Edge Function), ya que requiere ASN.1/DER y no es ideal en el cliente.
    return { seal: null, tsa: opts.tsaUrl, sealed_at: null, rfc3161: false, pending: 'integrar TSA server-side' }
  }
  // Sello local de respaldo (marca de tiempo + hash). NO es RFC 3161; placeholder.
  const sealed_at = new Date().toISOString()
  const seal = await sha256hex(auditHash + '|' + sealed_at)
  return { seal, tsa: 'local', sealed_at, rfc3161: false }
}

export default { computeAuditHash, verifyChain, timestampSeal }
