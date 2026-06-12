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
async function transport({ rows }) {
  const serverIds = {}
  for (const row of rows) {
    const payload = {
      local_id: row.local_id,
      client_slug: row.client_slug || row.company_id || session.slug,
      form_key: row.form_key,
      certificacion: row.certificacion,
      cultivo: row.cultivo || null,
      producer_id: row.productor_id || null,
      finca_id: row.finca_id || null,
      data: row.data || {},
      fotos: row.fotos || [],
      geom: row.geom ? JSON.stringify(row.geom) : null,
      email_usuario: row.Email_Usuario || session.email || null,
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
