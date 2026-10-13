import { createClient } from '@supabase/supabase-js'

// URL + publishable key del proyecto ERP (corp-erp-geo-ia). La publishable key es PÚBLICA por diseño
// (va en el cliente); el acceso real lo controla RLS (fn_user_has_client_access) + el JWT del usuario.
export const SUPABASE_URL = 'https://fcahhxxzhsfdqqhhdrcl.supabase.co'
export const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_YTi04Ze30LGy1j_KKJ8tyg_6DHYzLQa'

/* 🔴 PENDIENTE · PKCE (auditoría ASVS L1, 13-oct-2026). Sin `flowType`, supabase-js usa el flujo IMPLÍCITO: al volver
   de Google o del enlace por correo, el access_token y el refresh_token llegan en el fragmento de la URL
   (#access_token=…), donde pueden quedar en el historial del navegador o en una captura de pantalla. Con
   `flowType: 'pkce'` llega solo un `?code=` de un solo uso, que se canjea con un verificador guardado en ESTE
   navegador.

   No se cambia todavía porque puede dejar a la gente fuera y solo se comprueba en vivo:
   - Ingreso con Google: las URL de retorno permitidas en Supabase deben aceptar `?code=`; hay que probarlo en el
     dominio publicado, no en local.
   - Enlace por correo: con PKCE el enlace solo funciona en el MISMO navegador que lo pidió. En el teléfono, el
     correo suele abrirlo en otro navegador o en la vista interna de la app de correo, y el ingreso fallaría.
   - Embebido en el APK y «Abrir aparte» (shell-bridge.js) entran con setSession y no pasan por aquí: no cambian,
     pero se prueban igual.
   Cuando se haga: agregar `flowType: 'pkce'` abajo, desplegar y probar los tres caminos en un teléfono real. */
export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: { persistSession: true, autoRefreshToken: true }
})
