// Motor de captura OFFLINE-FIRST para respuestas de form-schemas de certificación.
//
// Regla rectora VG R1 (dato del campo sagrado) + R2 (offline-safe universal):
// toda entrevista, encuesta, visita o registro que se levante en campo se guarda
// SIN CONEXIÓN primero. Cero pérdida de datos. El sync al servidor es diferido.
//
// AGNÓSTICO de framework: vanilla JS + Dexie. Lo usa EUDR (Vue) hoy y el módulo
// del APK VG Suite (React) mañana. Una sola lógica offline para "una sola app".
//
// Cadena obligatoria (R2): valor leído del DOM → IndexedDB (inmediato) → sync queue
// → flush al servidor (diferido, con reintento). El servidor NUNCA está en el camino
// crítico de "guardar". El usuario guarda y sigue, esté online u offline.
//
// Patrones R2 aplicados:
//  1. Persistir en IDB ANTES de cualquier intento de upload.
//  2. Cero try/catch que descarte data: si el server falla, el item queda en queue.
//  3. Fotos: el blob va a IDB antes de subir (se ve sin red incluso tras el upload).
//  4. Reintento automático en window 'online'. El usuario no presiona "Sincronizar".
//  5. Estado de sync REAL (pending/failed/synced). El badge no miente.
//  6. Lectura del DOM con ref/blur la hace el COMPONENTE antes de llamar saveResponse()
//     (el IME buffer de Android no llega al state hasta blur). Ver readDomValue().

import { computeAuditHash, verifyChain } from './audit-hash-chain.js'

const STORE = 'cert_responses'      // respuestas de formularios de certificación
const PHOTOS = 'cert_photos'        // blobs de fotos offline-first
const QUEUE = 'cert_sync_queue'     // cola de sync (push diferido)

// uuid v4 sin dependencias (idempotencia del registro)
function uuid() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = (Math.random() * 16) | 0
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16)
  })
}

/**
 * Crea/abre la base offline para certificaciones. Recibe una instancia de Dexie
 * (la del producto) o crea una propia si se pasa el constructor.
 * @param {object} opts
 * @param {object} opts.db      - instancia Dexie ya abierta (preferido).
 * @param {Function} opts.transport - async ({ rows, photos }) => { ok, serverIds } : sube al server.
 * @param {Function} [opts.getCompanyId] - () => companyId actual (multi-tenant).
 * @param {Function} [opts.getUser] - () => { email } del técnico (captura automática).
 */
export function createCertOfflineEngine({ db, transport, getCompanyId = () => null, getUser = () => ({}), antifraude = null }) {
  if (!db) throw new Error('[cert-offline] se requiere una instancia Dexie (db).')
  if (typeof transport !== 'function') throw new Error('[cert-offline] se requiere transport(fn) para el flush.')

  const listeners = new Set()
  function emit() { const s = statusSnapshot(); listeners.forEach(fn => { try { fn(s) } catch {} }) }
  let _counts = { pending: 0, failed: 0, synced: 0, total: 0 }
  function statusSnapshot() { return { ..._counts, offline: !navigatorOnline() } }
  function navigatorOnline() { return typeof navigator === 'undefined' ? true : navigator.onLine }

  async function refreshCounts() {
    const all = await db.table(STORE).toArray()
    _counts = {
      total: all.length,
      pending: all.filter(r => r.sync_status === 'pending').length,
      failed: all.filter(r => r.sync_status === 'failed').length,
      synced: all.filter(r => r.sync_status === 'synced').length
    }
    emit()
    return _counts
  }

  /**
   * GUARDA una respuesta de formulario OFFLINE-FIRST. Devuelve inmediatamente tras
   * persistir en IDB (no espera al servidor). Es la función que el componente llama
   * al presionar "Guardar" en una entrevista/encuesta/visita.
   *
   * @param {object} args
   * @param {string} args.form_key       - clave del form-schema (ej. 'pv_cargill', 'eudr_dds').
   * @param {string} args.certificacion  - 'PV_CARGILL' | 'EUDR' | 'RFA' | ...
   * @param {object} args.data           - respuestas {seccion.campo: valor} leídas del DOM.
   * @param {Array}  [args.fotos]        - [{ field, blob, mime }] capturadas (van a IDB como blob).
   * @param {object} [args.geom]         - { type:'Polygon'|'Point', coordinates } si aplica.
   * @param {string} [args.productor_id]
   * @param {string} [args.finca_id]
   * @param {string} [args.local_id]     - para EDITAR un registro existente (idempotencia).
   * @returns {Promise<{ local_id, sync_status }>}
   */
  async function saveResponse(args) {
    const now = Date.now()
    const local_id = args.local_id || uuid()
    const user = getUser() || {}

    // 1) Persistir las fotos como BLOB en IDB ANTES de cualquier upload (R2 #3).
    const fotoRefs = []
    for (const f of (args.fotos || [])) {
      if (!f || !f.blob) continue
      const photo_id = uuid()
      await db.table(PHOTOS).put({
        photo_id, local_id, field: f.field, blob: f.blob, mime: f.mime || 'image/jpeg',
        sync_status: 'pending', created_at: now
      })
      fotoRefs.push({ field: f.field, photo_id })
    }

    // 2) Persistir la respuesta en IDB (R2 #1) — esto es el "guardado" real.
    const record = {
      local_id,
      form_key: args.form_key,
      certificacion: args.certificacion || null,
      company_id: getCompanyId(),
      productor_id: args.productor_id || null,
      finca_id: args.finca_id || null,
      data: args.data || {},
      fotos: fotoRefs,
      geom: args.geom || null,
      Email_Usuario: user.email || null,
      Timestamp_Creacion: new Date(now).toISOString(),
      sync_status: 'pending',
      updated_at: now,
      created_at: args.local_id ? undefined : now
    }
    // put = upsert por local_id (permite editar offline sin perder el original).
    const existing = await db.table(STORE).where('local_id').equals(local_id).first()
    if (existing) {
      record._idb_id = existing._idb_id
      record.created_at = existing.created_at
    }

    // ANTIFRAUDE (Capa 1+2): evalúa plausibilidad y nivel de riesgo al guardar, OFFLINE, en el
    // dispositivo. Hook opcional inyectado por el producto (agnóstico de las reglas específicas).
    // NO bloquea el guardado (R1): los flags son señales para el muestreo de riesgo y el nivel de
    // verificación, no un gate de captura. Los flags son DERIVADOS del data/geom/fotos (que el hash
    // sella), por lo que son recomputables y verificables sin cambiar el payload del hash.
    if (typeof antifraude === 'function') {
      try {
        const af = await antifraude(record)   // -> { flags, score, nivel_riesgo }
        if (af) { record.antifraude = af; record.nivel_riesgo = af.nivel_riesgo || null }
      } catch { /* nunca bloquea el guardado */ }
    }

    // CADENA DE INTEGRIDAD (item P0 5.8): hash SHA-256 encadenado al registro previo
    // de la misma cadena (mismo form_key + company_id). Hace el dato audit-grade local;
    // la cadena canónica la re-sella el servidor en orden de llegada. R1: si WebCrypto
    // falla en este entorno, NO bloquea el guardado (el dato del campo es sagrado).
    try {
      const cadena = (await db.table(STORE).where('form_key').equals(args.form_key).toArray())
        .filter(r => r.company_id === record.company_id && r.local_id !== local_id && r.audit_hash)
        .sort((a, b) => (a.created_at || 0) - (b.created_at || 0))
      const prevHash = cadena.length ? cadena[cadena.length - 1].audit_hash : ''
      record.prev_hash = prevHash
      record.audit_hash = await computeAuditHash(record, prevHash)
      record.audit_sealed = false   // lo sella el servidor (RFC 3161) al confirmar el sync
    } catch (e) {
      record.audit_hash = null      // sin hash local; el servidor lo calcula al recibir
    }

    await db.table(STORE).put(record)

    // 3) Encolar para sync (R2 #2: queda en queue aunque no haya red).
    await db.table(QUEUE).put({
      queue_id: uuid(), local_id, form_key: args.form_key,
      accion: existing ? 'update' : 'create', created_at: now, attempts: 0
    })

    await refreshCounts()

    // 4) Intentar flush en background SI hay red. Si falla, queda en queue (no se pierde).
    if (navigatorOnline()) { flush().catch(() => {}) }

    return { local_id, sync_status: 'pending' }
  }

  /**
   * FLUSH: sube los registros pending al servidor. Reintenta los failed. Cero
   * descarte: si el transport falla, el item se marca 'failed' y queda en queue.
   */
  let _flushing = false
  async function flush() {
    if (_flushing || !navigatorOnline()) return statusSnapshot()
    _flushing = true
    try {
      const pendientes = await db.table(STORE)
        .where('sync_status').anyOf('pending', 'failed').toArray()
      for (const row of pendientes) {
        // adjuntar blobs de fotos pendientes de este registro
        const photos = await db.table(PHOTOS).where('local_id').equals(row.local_id).toArray()
        try {
          const res = await transport({ rows: [row], photos })
          if (res && res.ok) {
            await db.table(STORE).update(row._idb_id, { sync_status: 'synced', server_id: res.serverIds?.[row.local_id] || null, synced_at: Date.now() })
            for (const p of photos) await db.table(PHOTOS).update(p.photo_id, { sync_status: 'synced' })
            await db.table(QUEUE).where('local_id').equals(row.local_id).delete()
          } else {
            await db.table(STORE).update(row._idb_id, { sync_status: 'failed' })
          }
        } catch (e) {
          // R2 #2: NO se descarta. Queda 'failed' en queue para el próximo flush.
          await db.table(STORE).update(row._idb_id, { sync_status: 'failed' })
        }
      }
    } finally {
      _flushing = false
      await refreshCounts()
    }
    return statusSnapshot()
  }

  /** Respuestas guardadas localmente (para listar/editar offline). */
  async function listResponses(form_key) {
    const q = db.table(STORE)
    const rows = form_key ? await q.where('form_key').equals(form_key).toArray() : await q.toArray()
    return rows.sort((a, b) => (b.updated_at || 0) - (a.updated_at || 0))
  }

  async function getResponse(local_id) {
    return db.table(STORE).where('local_id').equals(local_id).first()
  }

  /** Blob de una foto offline (para mostrar sin red). */
  async function getPhotoBlob(photo_id) {
    const p = await db.table(PHOTOS).get(photo_id)
    return p ? p.blob : null
  }

  /**
   * Verifica la integridad de la cadena de una certificación (modo auditor).
   * Recalcula cada hash y confirma el encadenamiento. Si alguien alteró o borró un
   * registro local, devuelve { ok:false, brokenAt }. Audit-grade para "ente oficial".
   * @param {string} [form_key] - limita la verificación a una cadena (form). Sin él, verifica todas.
   */
  async function verifyResponseChain(form_key) {
    const rows = (await listResponses(form_key)).slice().reverse() // ascendente por created_at
    return verifyChain(rows)
  }

  function onStatus(fn) { listeners.add(fn); fn(statusSnapshot()); return () => listeners.delete(fn) }

  // Reintento automático al volver online (R2 #4). El usuario NO presiona Sincronizar.
  if (typeof window !== 'undefined') {
    window.addEventListener('online', () => { flush().catch(() => {}); emit() })
    window.addEventListener('offline', () => emit())
  }

  refreshCounts()

  return { saveResponse, flush, listResponses, getResponse, getPhotoBlob, verifyResponseChain, onStatus, refreshCounts, statusSnapshot }
}

/**
 * Lee el valor REAL de un input desde el DOM (R2 #6). En webview Android el IME
 * buffer no llega al state hasta blur; este helper fuerza blur + lee del DOM.
 * El componente debe usar esto al construir `data` antes de saveResponse().
 * @param {HTMLElement} elRef - el input/textarea (ref.current en React, ref en Vue).
 */
export function readDomValue(elRef) {
  if (!elRef) return ''
  try { elRef.blur() } catch {}
  return elRef.value != null ? elRef.value : (elRef.textContent || '')
}

/**
 * Construye el objeto `data` leyendo del DOM todos los inputs de un contenedor
 * (R2 #6). Usar al guardar para evitar el race del IME. Mapea por [data-field].
 * @param {HTMLElement} containerEl - contenedor del formulario.
 */
export function readFormFromDom(containerEl) {
  const data = {}
  if (!containerEl) return data
  containerEl.querySelectorAll('[data-field]').forEach(el => {
    try { el.blur() } catch {}
    const field = el.getAttribute('data-field')
    if (el.type === 'checkbox') data[field] = el.checked
    else data[field] = el.value != null ? el.value : (el.textContent || '')
  })
  return data
}
