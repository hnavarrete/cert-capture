// Bridge SSO del APK VG Suite (bus B12 / B1). Cuando el encuestador corre EMBEBIDO en el shell
// (iframe), la sesión NO viene por cookie (cross-site): el shell la pasa por postMessage. Usamos el
// guest canónico de @vgsdk/auth (createSsoGuest) para pedir el JWT al shell e inyectarlo en el cliente
// Supabase. FUERA del iframe es no-op total → la app standalone (cert.visiongeografica.com) sigue con su
// login Google normal, sin cambios. Contrato verificado contra @vgsdk/auth@0.4.0 (dist/sso.d.ts).
import { createSsoGuest } from '@vgsdk/auth/sso'
import { supabase } from './supabase.js'

// Orígenes de shell aceptados (whitelist que valida el guest). PROD + staging + local.
const SHELL_ORIGINS = [
  'https://app.visiongeografica.com',
  'https://visor.visiongeografica.com',
  'https://piloto.visorgeografico.com',
  'http://localhost:5173',
  'http://localhost:5180'
]

function estamosEmbebidos() {
  try { return typeof window !== 'undefined' && window.parent && window.parent !== window } catch { return false }
}

/**
 * Si corremos dentro del shell del APK, pide la sesión al shell y la inyecta en Supabase.
 * Devuelve true si adoptó una sesión del shell; false si no (standalone, sin shell, o sin sesión).
 * NUNCA lanza: ante cualquier fallo, deja que la app caiga a su login normal (R1: no bloquear).
 */
export async function adoptShellSessionIfEmbedded() {
  if (!estamosEmbebidos()) return false
  let guest
  try {
    guest = createSsoGuest({ shellOrigins: SHELL_ORIGINS, timeoutMs: 6000 })
    const s = await guest.requestSession()
    // El shell puede devolver {access_token, refresh_token} o {session:{...}}; aceptamos ambos.
    const access_token = s?.access_token || s?.session?.access_token
    const refresh_token = s?.refresh_token || s?.session?.refresh_token
    if (access_token && refresh_token) {
      const { error } = await supabase.auth.setSession({ access_token, refresh_token })
      if (error) { console.warn('[shell-bridge] setSession:', error.message); return false }
      return true
    }
    console.warn('[shell-bridge] el shell no devolvió tokens utilizables')
    return false
  } catch (e) {
    console.warn('[shell-bridge] sin sesión del shell (sigo con login normal):', e?.message || e)
    return false
  } finally {
    try { guest?.dispose() } catch {}
  }
}
