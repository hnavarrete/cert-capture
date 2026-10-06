// Motor offline-first de la PWA + transport REAL a Supabase (RPC public.cert_upsert_response).
// Reusa la capa de captura agnóstica de @vgsdk/eudr-react (engine + antifraude).
import Dexie from 'dexie'
import { createCertOfflineEngine } from './eudr-react/capture/cert-offline-engine.js'
import { evaluateRules } from './eudr-react/capture/fraud-rules-engine.js'
import { buildAntifraudeCtxEUDR } from './eudr-react/useCertCapture.js'
import { supabase } from './supabase.js'

// sesión mutable (client_slug + email) que el App fija tras login + selección de tenant.
const session = { slug: null, email: null }
export function setCaptureSession({ slug, email }) {
  if (slug !== undefined) session.slug = slug
  if (email !== undefined) session.email = email
}
export function getCaptureSession() { return { ...session } }

const db = new Dexie('vg-cert-capture')
db.version(1).stores({
  cert_responses: '++_idb_id,local_id,form_key,sync_status,created_at',
  cert_photos: 'photo_id,local_id',
  cert_sync_queue: 'queue_id,local_id'
})

const BUCKET = 'cert-evidencias'
// El linaje de versiones (de qué versión parte cada guardado) viaja dentro de `data` con esta clave: la tabla del
// servidor no tiene columna para él, y sin él otro equipo no sabría plegar las versiones como lo hace este.
const CLAVE_VERSION_DE = '__version_de'

const enLinea = () => (typeof navigator === 'undefined' ? true : navigator.onLine !== false)

/**
 * Traduce un error de Supabase (RPC o Storage) a un motivo que la app puede decir en lenguaje llano.
 * tipos: sin_red · sin_sesion · sin_finca · sin_permiso · sellada · otro. El mensaje original se conserva.
 */
export function clasificarError(err) {
  const mensaje = String((err && (err.message || err.error_description || err.error)) || err || '')
  const t = tipo => ({ tipo, mensaje })
  if (!enLinea()) return t('sin_red')
  if (/failed to fetch|networkerror|load failed|network request failed|fetch failed|err_internet|err_network|timed? ?out/i.test(mensaje)) return t('sin_red')
  if (/respuesta sellada/i.test(mensaje)) return t('sellada')
  if (/<null>/.test(mensaje)) return t('sin_finca')
  if (/sin grant eudr|row-level security|not authorized|unauthorized|permission denied|\b403\b/i.test(mensaje)) return t('sin_permiso')
  if (/jwt|refresh token|invalid claim|session.*(missing|expired)|\b401\b/i.test(mensaje)) return t('sin_sesion')
  return t('otro')
}

function extDe(mime) {
  return mime.includes('png') ? 'png' : mime.includes('webp') ? 'webp' : mime.includes('pdf') ? 'pdf' : 'jpg'
}

// transport: sube cada fila a la RPC public.cert_upsert_response (upsert por local_id + sellado server-side).
async function transport({ rows, photos }) {
  // sin sesión autenticada (p. ej. modo demo) no se intenta el RPC: el dato queda en IDB (no se
  // pierde, R2) y se sincroniza cuando el usuario inicie sesión con acceso a la finca.
  /* 🔴 6-oct-2026: aquí antes decía `const { data: { session } } = …`, que TAPABA la variable de módulo
     `session` (slug + email). El respaldo `session.slug` de abajo leía la sesión de autenticación, que no
     tiene slug: sin finca en la fila, el client_slug salía null y el servidor lo rechazaba. */
  const { data: { session: authSession } } = await supabase.auth.getSession()
  if (!authSession) return { ok: false, skip: true, reason: 'sin sesión', error: { tipo: 'sin_sesion', mensaje: 'sin sesión' } }
  const serverIds = {}
  for (const row of rows) {
    const clientSlug = row.client_slug || row.company_id || session.slug || null
    // sin finca no hay a dónde respaldar: ni el bucket ni la RPC lo aceptan. Se dice, no se intenta.
    if (!clientSlug) return { ok: false, error: { tipo: 'sin_finca', mensaje: 'sin client_slug' } }
    // 1) Subir las EVIDENCIAS/fotos al bucket privado de Supabase Storage (cert-evidencias).
    //    Path: <client_slug>/<local_id>/<field>.<ext> -> la RLS valida acceso a la finca con el path.
    //    Aseguradas en el servidor + respaldadas; la referencia (path) va en cert_responses.fotos.
    const fotoRefs = []
    /* 🔴 Una versión nueva hereda evidencias de la anterior (5-oct-2026): el motor las pasa junto con las
       propias. Antes se filtraba por local_id === row.local_id y la versión subía SIN las heredadas.
       La ruta usa el local_id de la versión donde se guardó la evidencia: es la misma en todas las
       versiones, así que una evidencia ya subida no se vuelve a subir (y con upsert sería idempotente). */
    const ids = new Set((row.fotos || []).map(f => f.photo_id))
    for (const p of (photos || []).filter(x => x.local_id === row.local_id || ids.has(x.photo_id))) {
      const mime = p.mime || 'image/jpeg'
      /* 🔴 La ruta llevaba solo el nombre del campo y el upload va con upsert:true, así que dos
         evidencias del MISMO campo se pisaban en el bucket: subía la segunda y la primera
         desaparecía sin aviso. Se le agrega el identificador de la evidencia. Se puede cambiar
         el formato sin migrar nada porque cert_responses está en cero. */
      const safe = String(p.field || 'evidencia').replace(/[^\w.-]/g, '_')
      const sufijo = String(p.photo_id || '').replace(/[^\w]/g, '').slice(0, 8)
      // una evidencia traída del servidor (otro equipo) ya tiene su ruta: se reusa, no se vuelve a subir
      const path = p.path || `${clientSlug}/${p.local_id || row.local_id}/${safe}${sufijo ? '_' + sufijo : ''}.${extDe(mime)}`
      if (p.sync_status !== 'synced' && p.blob) {
        const { error: upErr } = await supabase.storage.from(BUCKET)
          .upload(path, p.blob, { upsert: true, contentType: mime })
        if (upErr) return { ok: false, error: clasificarError(upErr) }
      }
      fotoRefs.push({ field: p.field, path, photo_id: p.photo_id, bucket: BUCKET, name: p.name || null, mime })
    }
    // 2) Subir la respuesta (con las referencias de las fotos ya en Storage).
    const data = { ...(row.data || {}) }
    if (row.version_de) data[CLAVE_VERSION_DE] = row.version_de
    const payload = {
      local_id: row.local_id,
      client_slug: clientSlug,
      form_key: row.form_key,
      certificacion: row.certificacion,
      cultivo: row.cultivo || null,
      producer_id: row.productor_id || null,
      finca_id: row.finca_id || null,
      data,
      fotos: fotoRefs.length ? fotoRefs : (row.fotos || []),
      geom: row.geom ? JSON.stringify(row.geom) : null,
      email_usuario: row.Email_Usuario || authSession.user?.email || null,
      timestamp_creacion: row.Timestamp_Creacion || null,
      // 🔴 6-oct-2026: el servidor ahora GUARDA el hash del equipo y el de la versión anterior (antes los descartaba)
      audit_hash: row.audit_hash || null,
      prev_hash: row.prev_hash || null
    }
    const { data: id, error } = await supabase.rpc('cert_upsert_response', { p: payload })
    if (error) return { ok: false, error: clasificarError(error) }
    serverIds[row.local_id] = id
  }
  return { ok: true, serverIds }
}

const base = createCertOfflineEngine({
  db,
  transport,
  getCompanyId: () => session.slug,        // se persiste como company_id; el transport lo usa como client_slug
  getUser: () => ({ email: session.email }),
  // Capa 1 antifraude: evalúa plausibilidad OFFLINE al guardar (no bloquea; marca el nivel de riesgo)
  antifraude: (record) => {
    try { return evaluateRules(buildAntifraudeCtxEUDR(record)) } catch { return null }
  }
})

// promesa con tope de tiempo: sin señal o con red lenta, la app no se queda esperando al servidor
function conTope(promesa, ms) {
  let t
  return Promise.race([promesa, new Promise(res => { t = setTimeout(() => res({ tope: true }), ms) })]).finally(() => clearTimeout(t))
}

async function contexto() {
  if (!session.slug) return { motivo: 'sin_finca' }
  if (!enLinea()) return { motivo: 'sin_red' }
  const { data: { session: authSession } } = await supabase.auth.getSession()
  if (!authSession) return { motivo: 'sin_sesion' }
  return { slug: session.slug }
}

/**
 * RETOMAR DESDE OTRO EQUIPO (6-oct-2026). Trae las versiones que el servidor tiene de la finca elegida
 * (public.cert_mis_respuestas) y guarda en este equipo las que falten, como YA RESPALDADAS. El formulario las
 * pliega después con la misma lógica de versiones de siempre (rehidratarVersiones). Las evidencias NO se
 * descargan: se guarda su ruta y se muestran con una URL firmada cuando se abren. Sin sesión, sin finca o sin
 * red no hace nada: la app sigue con lo que hay en el equipo.
 * @param {string|null} form_key - un formulario, o null para todos los de la finca.
 */
export async function traerDelServidor(form_key = null) {
  const c = await contexto()
  if (!c.slug) return { ok: false, motivo: c.motivo }
  const { data, error } = await supabase.rpc('cert_mis_respuestas', { p_client_slug: c.slug, p_form_key: form_key || null })
  if (error) return { ok: false, error: clasificarError(error) }
  let nuevas = 0
  for (const r of (Array.isArray(data) ? data : [])) {
    if (!r || !r.local_id) continue
    if (await db.cert_responses.where('local_id').equals(r.local_id).first()) continue   // ya está en este equipo
    const d = { ...(r.data || {}) }
    const version_de = d[CLAVE_VERSION_DE] || null
    delete d[CLAVE_VERSION_DE]
    const fotos = []
    for (const f of (Array.isArray(r.fotos) ? r.fotos : [])) {
      if (!f || !f.photo_id) continue
      fotos.push({ field: f.field, photo_id: f.photo_id })
      if (!(await db.cert_photos.get(f.photo_id))) {
        await db.cert_photos.put({
          photo_id: f.photo_id, local_id: r.local_id, field: f.field, blob: null, mime: f.mime || null,
          name: f.name || null, path: f.path || null, bucket: f.bucket || BUCKET, sync_status: 'synced', remota: true
        })
      }
    }
    const ts = Date.parse(r.timestamp_creacion || r.created_at) || Date.now()
    await db.cert_responses.put({
      local_id: r.local_id, form_key: r.form_key, certificacion: r.certificacion || null,
      company_id: r.client_slug, productor_id: r.producer_id || null, finca_id: r.finca_id || null,
      data: d, fotos, version_de, geom: null, Email_Usuario: null,
      Timestamp_Creacion: r.timestamp_creacion || null, created_at: ts, updated_at: ts,
      audit_hash: r.audit_hash || null, prev_hash: r.prev_hash || null, audit_chain_seq: r.audit_chain_seq ?? null,
      content_hash: r.content_hash || null, sync_status: 'synced', server_id: r.id || null, synced_at: Date.now(),
      desde_servidor: true
    })
    nuevas++
  }
  if (nuevas) await base.refreshCounts()
  return { ok: true, nuevas, total: Array.isArray(data) ? data.length : 0 }
}

/**
 * Integridad del registro encadenado de un formulario EN EL SERVIDOR (public.cert_verificar_cadena).
 * Devuelve { ok, broken_at, total } o { error } / { motivo } si no se pudo consultar.
 */
export async function verificarCadena(form_key) {
  const c = await contexto()
  if (!c.slug) return { motivo: c.motivo }
  const { data, error } = await supabase.rpc('cert_verificar_cadena', { p_client_slug: c.slug, p_form_key: form_key })
  if (error) return { error: clasificarError(error) }
  const fila = Array.isArray(data) ? data[0] : data
  if (!fila) return { ok: true, broken_at: null, total: 0 }
  return { ok: fila.ok !== false, broken_at: fila.broken_at || null, total: Number(fila.total || 0) }
}

/**
 * Dirección para VER una evidencia. Si el archivo está en este equipo, una URL local del blob (quien la pide la
 * libera con URL.revokeObjectURL). Si vino del servidor, una URL firmada de una hora: el archivo no se duplica.
 * @returns {Promise<{ url, local: boolean } | null>}
 */
export async function urlEvidencia(photo_id) {
  const p = await db.cert_photos.get(photo_id)
  if (!p) return null
  if (p.blob) return { url: URL.createObjectURL(p.blob), local: true }
  if (!p.path) return null
  const { data, error } = await supabase.storage.from(p.bucket || BUCKET).createSignedUrl(p.path, 3600)
  if (error || !data?.signedUrl) return null
  return { url: data.signedUrl, local: false }
}

/* El motor que usa la app. Al abrir un formulario (getLatestState), antes de leer el equipo trae del servidor lo
   que falte, con un tope de 6 s: sin señal o con el servidor lento, se abre con lo que hay en el equipo. */
export const engine = {
  ...base,
  async getLatestState(form_key, ctx) {
    try { await conTope(traerDelServidor(form_key), 6000) } catch { /* nunca bloquea abrir el formulario */ }
    return base.getLatestState(form_key, ctx)
  },
  getPhotoUrl: urlEvidencia
}

export { db }
