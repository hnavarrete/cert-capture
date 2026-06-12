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

// transport: sube cada fila a la RPC public.cert_upsert_response (upsert por local_id + sellado server-side).
async function transport({ rows, photos }) {
  // sin sesión autenticada (p. ej. modo demo) no se intenta el RPC: el dato queda en IDB (no se
  // pierde, R2) y se sincroniza cuando el usuario inicie sesión con acceso a la finca.
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return { ok: false, reason: 'sin sesión' }
  const serverIds = {}
  for (const row of rows) {
    const clientSlug = row.client_slug || row.company_id || session.slug || null
    // 1) Subir las EVIDENCIAS/fotos al bucket privado de Supabase Storage (cert-evidencias).
    //    Path: <client_slug>/<local_id>/<field>.<ext> -> la RLS valida acceso a la finca con el path.
    //    Aseguradas en el servidor + respaldadas; la referencia (path) va en cert_responses.fotos.
    const fotoRefs = []
    for (const p of (photos || []).filter(x => x.local_id === row.local_id)) {
      const mime = p.mime || 'image/jpeg'
      const ext = mime.includes('png') ? 'png' : mime.includes('webp') ? 'webp' : mime.includes('pdf') ? 'pdf' : 'jpg'
      const safe = String(p.field || p.photo_id || 'evidencia').replace(/[^\w.-]/g, '_')
      const path = `${clientSlug || 'sin-slug'}/${row.local_id}/${safe}.${ext}`
      const { error: upErr } = await supabase.storage.from('cert-evidencias')
        .upload(path, p.blob, { upsert: true, contentType: mime })
      if (upErr) { console.warn('[sync] foto a Storage:', upErr.message); return { ok: false } }
      fotoRefs.push({ field: p.field, path, photo_id: p.photo_id, bucket: 'cert-evidencias' })
    }
    // 2) Subir la respuesta (con las referencias de las fotos ya en Storage).
    const payload = {
      local_id: row.local_id,
      client_slug: clientSlug,
      form_key: row.form_key,
      certificacion: row.certificacion,
      cultivo: row.cultivo || null,
      producer_id: row.productor_id || null,
      finca_id: row.finca_id || null,
      data: row.data || {},
      fotos: fotoRefs.length ? fotoRefs : (row.fotos || []),
      geom: row.geom ? JSON.stringify(row.geom) : null,
      email_usuario: row.Email_Usuario || session.user?.email || null,
      timestamp_creacion: row.Timestamp_Creacion || null
    }
    const { data, error } = await supabase.rpc('cert_upsert_response', { p: payload })
    if (error) { console.warn('[sync] cert_upsert_response:', error.message); return { ok: false } }
    serverIds[row.local_id] = data
  }
  return { ok: true, serverIds }
}

export const engine = createCertOfflineEngine({
  db,
  transport,
  getCompanyId: () => session.slug,        // se persiste como company_id; el transport lo usa como client_slug
  getUser: () => ({ email: session.email }),
  // Capa 1 antifraude: evalúa plausibilidad OFFLINE al guardar (no bloquea; marca el nivel de riesgo)
  antifraude: (record) => {
    try { return evaluateRules(buildAntifraudeCtxEUDR(record)) } catch { return null }
  }
})

export { db }
