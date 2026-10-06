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
  /* 🔴 EL MOTIVO DEL ÚLTIMO INTENTO, A LA VISTA (6-oct-2026). Antes un respaldo fallido solo dejaba un
     console.warn: una clienta cargó semanas, nada llegó al servidor y nadie se enteró. Ahora el transporte
     devuelve { error: { tipo, mensaje } } (o { skip, reason }) y el estado lo expone para que la app lo
     diga en lenguaje llano. Se limpia cuando un respaldo completo sale bien. */
  let _lastError = null
  let _lastFlushAt = null
  function statusSnapshot() { return { ..._counts, offline: !navigatorOnline(), lastError: _lastError, lastFlushAt: _lastFlushAt } }
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
    //    Primero van las heredadas de la versión anterior (ver abajo), en su orden; después las nuevas.
    const fotoRefs = []
    for (const f of (args.fotos_previas || [])) {
      if (!f || !f.photo_id || fotoRefs.some(x => x.photo_id === f.photo_id)) continue
      fotoRefs.push({ field: f.field, photo_id: f.photo_id })
    }
    for (const f of (args.fotos || [])) {
      if (!f || !f.blob) continue
      const photo_id = uuid()
      await db.table(PHOTOS).put({
        photo_id, local_id, field: f.field, blob: f.blob, mime: f.mime || 'image/jpeg',
        name: f.name || null, sync_status: 'pending', created_at: now
      })
      fotoRefs.push({ field: f.field, photo_id })
    }
    /* 🔴 VERSIONES, NO SOBRESCRITURA (5-oct-2026). Cada guardado es un registro NUEVO de la cadena de
       integridad: la versión anterior queda intacta y sellada, como exige una auditoría. Para que la
       versión nueva sea COMPLETA (y no solo lo que se tocó en esta sesión), lleva las evidencias que ya
       estaban guardadas como REFERENCIA a su blob —sin volver a copiarlo— y el local_id de la versión
       de la que parte (`version_de`). Antes no había ni lo uno ni lo otro: el formulario se abría vacío
       y cada guardado empezaba de cero. */

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
      version_de: args.version_de || null,
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

    return { local_id, sync_status: 'pending', fotos: fotoRefs, version_de: record.version_de }
  }

  /**
   * FLUSH: sube los registros pending al servidor. Reintenta los failed. Cero
   * descarte: si el transport falla, el item se marca 'failed' y queda en queue.
   */
  let _flushing = false
  async function flush() {
    if (_flushing || !navigatorOnline()) return statusSnapshot()
    _flushing = true
    let problema = null
    try {
      let pendientes = await db.table(STORE)
        .where('sync_status').anyOf('pending', 'failed').toArray()
      // dos vueltas como máximo: la segunda solo para las versiones que se renombraron (ver «sellada» abajo)
      for (let vuelta = 0; vuelta < 2 && pendientes.length; vuelta++) {
        const renombradas = []
        for (const row of pendientes) {
          const r = await subirUna(row)
          if (r.renombrada) renombradas.push(r.renombrada)
          else if (r.problema && !problema) problema = r.problema
        }
        pendientes = renombradas
      }
    } finally {
      _flushing = false
      _lastFlushAt = Date.now()
      _lastError = problema
      await refreshCounts()
    }
    return statusSnapshot()
  }

  // Sube UNA versión. Devuelve { ok } | { problema } | { renombrada: fila } (la segunda vuelta la reintenta).
  async function subirUna(row) {
    // adjuntar blobs de fotos pendientes de este registro
    const photos = await db.table(PHOTOS).where('local_id').equals(row.local_id).toArray()
    // + las evidencias que esta versión hereda de una anterior (referencia, el blob vive una sola vez)
    const heredadas = (row.fotos || []).map(f => f.photo_id).filter(id => id && !photos.some(p => p.photo_id === id))
    if (heredadas.length) for (const p of await db.table(PHOTOS).bulkGet(heredadas)) if (p) photos.push(p)
    try {
      const res = await transport({ rows: [row], photos })
      if (res && res.ok) {
        await db.table(STORE).update(row._idb_id, { sync_status: 'synced', server_id: res.serverIds?.[row.local_id] || null, synced_at: Date.now(), sync_error: null })
        for (const p of photos) if (p.sync_status !== 'synced') await db.table(PHOTOS).update(p.photo_id, { sync_status: 'synced' })
        await db.table(QUEUE).where('local_id').equals(row.local_id).delete()
        return { ok: true }
      }
      if (res && res.skip) {
        // El transport NO lo intentó (p. ej., no hay sesión: modo demo o sesión vencida). No es un
        // error de subida: sigue 'pending' («en este dispositivo») y se reintenta en el próximo flush.
        // (cert-capture, 5-oct-2026: el modo demo marcaba cada guardado como «error al subir».)
        return { problema: res.error || { tipo: 'sin_sesion', mensaje: res.reason || '' } }
      }
      const error = (res && res.error) || { tipo: 'otro', mensaje: 'el servidor no confirmó el respaldo' }
      /* 🔴 SELLADA (6-oct-2026). El servidor ya tiene ese local_id sellado con OTRO contenido y no lo reescribe.
         Reintentar el mismo local_id fallaría para siempre. Lo que el usuario guardó se respalda como una
         VERSIÓN NUEVA: mismo contenido, local_id nuevo y su hash recalculado. Lo sellado no se toca. */
      if (error.tipo === 'sellada' && !row.reemplaza_local_id) {
        const nuevo = { ...row, local_id: uuid(), reemplaza_local_id: row.local_id, sync_status: 'pending', sync_error: null }
        try { nuevo.audit_hash = await computeAuditHash(nuevo, row.prev_hash || '') } catch { nuevo.audit_hash = null }
        await db.table(STORE).put(nuevo)
        await db.table(QUEUE).where('local_id').equals(row.local_id).modify({ local_id: nuevo.local_id })
        return { renombrada: nuevo }
      }
      await db.table(STORE).update(row._idb_id, { sync_status: 'failed', sync_error: error })
      return { problema: error }
    } catch (e) {
      // R2 #2: NO se descarta. Queda 'failed' en queue para el próximo flush.
      const error = { tipo: 'otro', mensaje: (e && e.message) || String(e) }
      await db.table(STORE).update(row._idb_id, { sync_status: 'failed', sync_error: error })
      return { problema: error }
    }
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

  /**
   * RETOMAR: estado vigente de un formulario en un contexto (finca/productor/lote), armado con TODAS
   * sus versiones guardadas en el dispositivo (ver rehidratarVersiones). Es lo que el formulario
   * muestra al abrirse: sin esto, cada vez se abría vacío y «Puedes salir y retomar» no era verdad.
   * No escribe nada: solo lee la bóveda local.
   * @param {string} form_key
   * @param {object} [ctx] - { company_id, productor_id, finca_id }: el mismo filtro del tablero.
   * @returns {Promise<null | { data, fotos:[{field,photo_id,name,mime}], local_id, versiones, updated_at }>}
   */
  async function getLatestState(form_key, ctx = {}) {
    if (!form_key) return null
    // sin company_id explícito, el de la sesión actual (la finca elegida), como al guardar
    const c = { ...ctx, company_id: ctx.company_id !== undefined ? ctx.company_id : getCompanyId() }
    const rows = (await db.table(STORE).where('form_key').equals(form_key).toArray())
      .filter(r => enContexto(r, c))
    if (!rows.length) return null
    const ids = [...new Set(rows.flatMap(r => (r.fotos || []).map(f => f.photo_id)).filter(Boolean))]
    const fotosPorId = {}
    if (ids.length) for (const p of await db.table(PHOTOS).bulkGet(ids)) if (p) fotosPorId[p.photo_id] = p
    const estado = rehidratarVersiones(rows, fotosPorId)
    // cuántas de esas versiones llegaron del servidor (guardadas en otro equipo): lo dice el aviso de retomar
    if (estado) estado.remotas = rows.filter(r => r.desde_servidor).length
    return estado
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

  return { saveResponse, flush, listResponses, getResponse, getLatestState, getPhotoBlob, verifyResponseChain, onStatus, refreshCounts, statusSnapshot }
}

/**
 * ¿El registro pertenece al contexto elegido? Mismo criterio laxo del tablero de progreso: un dato
 * que el registro no trae (sin finca, sin productor) no lo excluye.
 */
export function enContexto(r, { company_id, productor_id, finca_id } = {}) {
  const rs = r.client_slug || r.company_id
  if (company_id && rs && rs !== company_id) return false
  if (productor_id && r.productor_id && r.productor_id !== productor_id) return false
  if (finca_id && r.finca_id && r.finca_id !== finca_id) return false
  return true
}

const vacio = v => v === undefined || v === null || v === '' || v === false || (Array.isArray(v) && v.length === 0)

/**
 * Pliega las versiones guardadas de UN formulario en su estado vigente (función pura, sin IDB).
 *
 * 🔴 Dos clases de versión, y por qué se tratan distinto (5-oct-2026):
 *  - Versión que CONTINÚA otra (`version_de`): se guardó con el formulario mostrando lo anterior, así
 *    que lo que trae es el estado completo de lo que se vio. Un campo vacío ahí es un vaciado
 *    deliberado y SÍ borra el valor previo. Sus evidencias son la lista completa.
 *  - Versión SIN `version_de` (todas las anteriores a este arreglo): se guardó desde un formulario que
 *    se abría VACÍO. Sus campos vacíos no son decisiones, son el formulario en blanco: no pisan nada.
 *    Solo aporta lo que sí trae, y sus evidencias se SUMAN (cada sesión subía las suyas). Así lo que la
 *    persona cargó por partes durante días vuelve a aparecer junto, sin perder ninguna parte.
 *
 * @param {Array} rows - registros de cert_responses del mismo form_key (cualquier orden).
 * @param {object} [fotosPorId] - photo_id → registro de cert_photos (para nombre y tipo).
 */
export function rehidratarVersiones(rows, fotosPorId = {}) {
  const orden = (rows || []).slice().sort((a, b) => (a.created_at || a.updated_at || 0) - (b.created_at || b.updated_at || 0))
  if (!orden.length) return null
  let data = {}
  let fotos = []
  const nombres = {}   // photo_id → nombre, tomado de la versión donde la evidencia se guardó por primera vez
  for (const r of orden) {
    const d = r.data || {}
    const refs = (r.fotos || []).filter(f => f && f.photo_id).map(f => {
      const p = fotosPorId[f.photo_id] || {}
      if (!(f.photo_id in nombres)) nombres[f.photo_id] = p.name || nombreHeredado(d, f.field)
      return { field: f.field, photo_id: f.photo_id, mime: p.mime || null, name: nombres[f.photo_id], size: p.blob?.size ?? null }
    })
    if (r.version_de) {
      data = { ...data, ...d }
      fotos = refs
    } else {
      for (const [k, v] of Object.entries(d)) if (!vacio(v)) data[k] = v
      for (const f of refs) {
        // la misma evidencia guardada dos veces en una sesión (mismo campo, nombre y tamaño) no se duplica
        const dup = fotos.some(x => x.photo_id === f.photo_id ||
          (base(x.field) === base(f.field) && x.name && x.name === f.name && x.size != null && x.size === f.size))
        if (!dup) fotos.push(f)
      }
    }
  }
  // el campo de evidencia guarda los nombres de TODOS sus archivos vigentes (lo lee la vista previa)
  const porCampo = {}
  for (const f of fotos) (porCampo[base(f.field)] = porCampo[base(f.field)] || []).push(f.name || 'archivo')
  for (const [k, nombres] of Object.entries(porCampo)) data[k] = nombres.join(' · ')
  const ult = orden[orden.length - 1]
  return { data, fotos, local_id: ult.local_id, versiones: orden.length, updated_at: ult.updated_at || ult.created_at || null }
}

function base(field) { return String(field || '').split('#')[0] }
// versiones viejas: el blob no guardaba su nombre, pero el campo sí (nombres unidos con « · », en orden)
function nombreHeredado(data, field) {
  const [b, n] = String(field || '').split('#')
  const nombres = String(data[b] || '').split(' · ').filter(Boolean)
  return nombres[n ? parseInt(n, 10) - 1 : 0] || null
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
