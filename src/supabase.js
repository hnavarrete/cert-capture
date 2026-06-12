import { createClient } from '@supabase/supabase-js'

// URL + publishable key del proyecto ERP (corp-erp-geo-ia). La publishable key es PÚBLICA por diseño
// (va en el cliente); el acceso real lo controla RLS (fn_user_has_client_access) + el JWT del usuario.
export const SUPABASE_URL = 'https://fcahhxxzhsfdqqhhdrcl.supabase.co'
export const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_YTi04Ze30LGy1j_KKJ8tyg_6DHYzLQa'

export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: { persistSession: true, autoRefreshToken: true }
})
