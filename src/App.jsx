import React, { useEffect, useMemo, useState } from 'react'
import { CertForm, useCertCapture, readFormFromContainer, progresoDe } from './eudr-react/index.js'
import { buildCertReadyPreviewHtml } from './eudr-react/capture/export-policy.js'
import { engine, setCaptureSession, db } from './engine.js'
import { supabase } from './supabase.js'
import { adoptShellSessionIfEmbedded, estamosEmbebidos } from './shell-bridge.js'

// ¿corremos embebidos en el shell del APK? (iframe). Gatea el comportamiento que NO aplica embebido:
// el shell es dueño de la sesión y de la navegación → no cerramos sesión ni mostramos login propio.
const EMBEBIDO = estamosEmbebidos()
import bundle from './schemas.bundle.json'
import RoadmapCert from './RoadmapCert.jsx'

const SCHEMAS = (bundle.schemas || []).filter(s => !s.legacy)
const CERTS = bundle.certificaciones || []
const CERT_LABEL = Object.assign(
  Object.fromEntries(CERTS.map(c => [c.key, c.titulo])),
  { FSC: 'FSC — Manejo forestal', PEFC: 'PEFC — Manejo forestal' }
)
const CERT_ICON = {
  GENERAL: '📋', EUDR: '🛡️', FSC: '🌲', FSC_FM: '🌲', FSC_CoC: '🔗', RFA: '🐸',
  PEFC: '🌲', PEFC_FM: '🌲',
  USDA_ORGANIC: '🌱', GLOBAL_GAP: '✅', MARBETE_AGROCALIDAD: '🏷️', COMPARTIDO: '🔗'
}

// Roles canónicos del ecosistema (fn_is_canonical_role) mapeados a nivel operativo del encuestador.
// nivel: admin (god) · gestion · supervision · captura · lectura. De aquí salen las capacidades de la UI.
const ROLES = {
  god: { label: 'Administrador VG', nivel: 'admin' },
  producer_admin: { label: 'Productor (dueño)', nivel: 'gestion' },
  gerente_general: { label: 'Gerente general', nivel: 'gestion' },
  gerente_agricola: { label: 'Gerente agrícola', nivel: 'gestion' },
  gerente_sostenibilidad: { label: 'Gerente de sostenibilidad', nivel: 'gestion' },
  gerente_hacienda: { label: 'Gerente de hacienda', nivel: 'gestion' },
  manager: { label: 'Gerente', nivel: 'gestion' },
  supervisor: { label: 'Supervisor', nivel: 'supervision' },
  field_worker: { label: 'Trabajador de campo', nivel: 'captura' },
  tecnico: { label: 'Técnico', nivel: 'captura' },
  fumigador: { label: 'Fumigador', nivel: 'captura' },
  packhouse_operator: { label: 'Operador de empacadora', nivel: 'captura' }, // 13º canónico (A6, #03 G1)
  lector: { label: 'Solo lectura', nivel: 'lectura' }
}
// Capacidades derivadas del nivel (gating de UI). El servidor es la fuente de verdad; esto es UX.
function capsDeRol(rol) {
  const nivel = (ROLES[rol] || {}).nivel || 'captura'
  return {
    nivel,
    puedeCapturar: nivel !== 'lectura',                 // lector no escribe
    puedeExportar: nivel === 'gestion' || nivel === 'admin' || nivel === 'lectura', // entregables: gestión/auditor
    esLector: nivel === 'lectura',
    esAdmin: nivel === 'admin'
  }
}

function groupByCert(schemas) {
  const g = {}
  for (const s of schemas) {
    const c = (s.certificacion === 'FSC_FM' || s.certificacion === 'FSC_CoC') ? 'FSC'
      : (s.certificacion === 'PEFC_FM' || s.certificacion === 'PEFC_CoC') ? 'PEFC'
      : s.certificacion
    ;(g[c] = g[c] || []).push(s)
  }
  return g
}

function SyncBadge({ status }) {
  const { pending = 0, failed = 0, synced = 0, offline } = status || {}
  return (
    <div className={'badge ' + (offline ? 'off' : 'on')}>
      <span className="pulse" />{offline ? 'sin conexión' : 'en línea'}
      <small>· {pending} pend · {failed} fall · {synced} sync</small>
    </div>
  )
}

function Login({ onDemo }) {
  const [email, setEmail] = useState('')
  const [pass, setPass] = useState('')
  const [msg, setMsg] = useState(null)
  const [busy, setBusy] = useState(false)
  const [verCorreo, setVerCorreo] = useState(false)
  async function signInGoogle() {
    setBusy(true); setMsg(null)
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: window.location.origin + window.location.pathname }
    })
    if (error) { setMsg(error.message); setBusy(false) }
  }
  async function signIn(e) {
    e.preventDefault(); setBusy(true); setMsg(null)
    const { error } = await supabase.auth.signInWithPassword({ email, password: pass })
    if (error) setMsg(error.message)
    setBusy(false)
  }
  return (
    <div className="card login">
      <h1>VG · Captura de Certificaciones</h1>
      <p className="muted">Ingresa con tu cuenta del ecosistema VG. El acceso a cada finca lo controla
        el servidor. Captura sin conexión; sincroniza al volver la señal.</p>
      <button type="button" className="google" disabled={busy} onClick={signInGoogle}>
        <span className="g">G</span> Continuar con Google
      </button>
      <button type="button" className="link" style={{ marginTop: 10 }} onClick={() => setVerCorreo(v => !v)}>
        {verCorreo ? 'Ocultar el ingreso por correo' : 'Ingresar con correo y contraseña'}
      </button>
      {verCorreo ? (
        <form onSubmit={signIn} style={{ marginTop: 8 }}>
          <label>Correo<input type="email" value={email} onChange={e => setEmail(e.target.value)} required /></label>
          <label>Contraseña<input type="password" value={pass} onChange={e => setPass(e.target.value)} required /></label>
          <button disabled={busy}>{busy ? 'Ingresando…' : 'Ingresar'}</button>
        </form>
      ) : null}
      {msg ? <div className="err">{msg}</div> : null}
      <button type="button" className="link demo-link" onClick={onDemo}>
        Explorar en modo demo (captura local, sin sincronizar) →
      </button>
    </div>
  )
}

// Estado D del contrato de acceso (kit #02): cuenta del ecosistema SIN acceso al encuestador.
// No se la manda al login de nuevo; se le ofrece solicitar acceso. La identidad es la misma del resto.
function SinAcceso({ email, onSalir }) {
  const msg = encodeURIComponent('Hola, soy ' + email + '. Solicito acceso al Encuestador de Certificaciones (EUDR) de Visión Geográfica.')
  return (
    <div className="wrap"><div className="card login">
      <h1>Encuestador de Certificaciones</h1>
      <p className="muted">Tu cuenta <b>{email}</b> ya es parte del ecosistema VG, pero todavía no tiene
        acceso al Encuestador. Pídeselo a tu administrador y lo activamos al instante.</p>
      <a className="google" style={{ textDecoration: 'none', color: '#1f2937' }} target="_blank" rel="noopener"
        href={'https://wa.me/593967216547?text=' + msg}>Solicitar acceso por WhatsApp</a>
      <button type="button" className="link" style={{ marginTop: 10 }} onClick={onSalir}>Cambiar de cuenta</button>
    </div></div>
  )
}

// Gate "Mi perfil" — identidad Capa 0 del productor (onboarding F1). La identificación (cédula/RUC/
// pasaporte) es el ancla única anti-duplicados que hace las certificaciones tuyas y auditables.
// R1-safe: "Completar luego" nunca bloquea. R2: si no hay señal o la RPC aún no existe, guarda local y avanza.
function MiPerfilGate({ email, onListo, onOmitir }) {
  const [tipo, setTipo] = useState('cedula')
  const [ident, setIdent] = useState('')
  const [nombre, setNombre] = useState('')
  const [apellido, setApellido] = useState('')
  const [telefono, setTelefono] = useState('')
  const [consent, setConsent] = useState(false)
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState(null)
  const LABELS = { cedula: 'Cédula', ruc: 'RUC', pasaporte: 'Pasaporte' }

  async function guardar(e) {
    e.preventDefault()
    if (!ident.trim() || !nombre.trim() || !apellido.trim()) { setMsg('Completa tu identificación, nombre y apellido.'); return }
    if (!consent) { setMsg('Necesitamos tu autorización para guardar tus datos.'); return }
    setBusy(true); setMsg(null)
    try {
      // Contrato CANÓNICO de identidad (bus B2, dueño #03). Orden indicado por #03: ensure_producer_self
      // (crea/enlaza el producer por email del JWT + consent base) → upsert_my_profile (identidad real con cédula).
      // R23: no reimplementar identidad; la misma "Mi perfil" del visor/ERP, una sola fuente.
      await supabase.rpc('ensure_producer_self', { p_display_name: (nombre + ' ' + apellido).trim(), p_tenant_slug_origin: 'eudr' })
      const { error } = await supabase.rpc('upsert_my_profile', {
        p_nombre: nombre.trim(), p_apellido: apellido.trim(),
        p_tipo_documento: tipo, p_numero_documento: ident.trim(),
        p_telefono: telefono.trim() || null
      })
      if (error) throw error
      onListo(true)
    } catch (err) {
      // offline: guardamos en el dispositivo y dejamos avanzar (R1: no bloquear). Se sincroniza al volver la señal.
      localStorage.setItem('vg_perfil_pendiente', JSON.stringify({ tipo, ident: ident.trim(), nombre: nombre.trim(), apellido: apellido.trim(), telefono: telefono.trim(), consent }))
      setMsg('Guardamos tu perfil en este dispositivo; se registrará al volver la señal.')
      setTimeout(() => onListo(true), 1200)
    } finally { setBusy(false) }
  }

  return (
    <div className="wrap"><div className="card login">
      <h1>Tu perfil de productor</h1>
      <p className="muted">Antes de empezar, dinos quién eres. Tu identificación (cédula, RUC o pasaporte)
        es tu ancla única: evita duplicados y hace que tus certificaciones sean tuyas y auditables.</p>
      <form onSubmit={guardar}>
        <label>Tipo de identificación
          <select value={tipo} onChange={e => setTipo(e.target.value)}>
            <option value="cedula">Cédula</option>
            <option value="ruc">RUC</option>
            <option value="pasaporte">Pasaporte</option>
          </select>
        </label>
        <label>{LABELS[tipo]}<input value={ident} onChange={e => setIdent(e.target.value)} placeholder="Número de identificación" required /></label>
        <label>Nombre<input value={nombre} onChange={e => setNombre(e.target.value)} placeholder="Tus nombres" required /></label>
        <label>Apellido<input value={apellido} onChange={e => setApellido(e.target.value)} placeholder="Tus apellidos" required /></label>
        <label>Teléfono (opcional)<input value={telefono} onChange={e => setTelefono(e.target.value)} placeholder="+593…" /></label>
        <label className="check"><input type="checkbox" checked={consent} onChange={e => setConsent(e.target.checked)} />
          <span>Autorizo a VG a guardar mis datos para gestionar mis certificaciones. Mis datos son míos; yo decido con quién los comparto.</span></label>
        {msg ? <div className="err">{msg}</div> : null}
        <button disabled={busy}>{busy ? 'Guardando…' : 'Guardar mi perfil'}</button>
      </form>
      <button type="button" className="link" style={{ marginTop: 10 }} onClick={onOmitir}>Completar luego</button>
    </div></div>
  )
}

// Tablero de progreso de TODAS las certificaciones del productor (gamificación, paso 2).
// Lee los borradores guardados en IndexedDB del contexto actual (finca/productor) y, por cada
// certificación, hace el rollup de avance con el MISMO progresoDe del formulario (una sola fuente de
// verdad del cálculo). Offline-first: no consulta al servidor, sirve sin señal.
function TableroProgreso({ grouped, certKeys, slug, productor, finca, onPick, onClose }) {
  const [best, setBest] = useState(null)
  const [abierta, setAbierta] = useState(null)
  useEffect(() => {
    let on = true
    ;(async () => {
      const all = await db.cert_responses.toArray()
      const ctx = all.filter(r => {
        const rs = r.client_slug || r.company_id
        if (slug && rs && rs !== slug) return false
        if (productor && r.productor_id && r.productor_id !== productor) return false
        if (finca && r.finca_id && r.finca_id !== finca) return false
        return true
      })
      // por cada formulario, el borrador más avanzado (heurística: más campos respondidos)
      const m = {}
      for (const r of ctx) {
        const d = r.data || {}
        const score = Object.keys(d).length
        if (!m[r.form_key] || score > m[r.form_key].score) m[r.form_key] = { data: d, score, sync: r.sync_status }
      }
      if (on) setBest(m)
    })()
    return () => { on = false }
  }, [slug, productor, finca])

  const filas = useMemo(() => (certKeys || []).map(cert => {
    const schemas = grouped[cert] || []
    let total = 0, hechas = 0, iniciados = 0, vendibles = 0
    const forms = schemas.map(s => {
      const data = best?.[s.form_key]?.data || {}
      const p = progresoDe(s, data)
      total += p.total; hechas += p.hechas
      if (p.hechas > 0) iniciados++
      if (p.vendible) vendibles++
      return { form_key: s.form_key, titulo: s.titulo, p, sync: best?.[s.form_key]?.sync }
    })
    const pct = total ? Math.round(100 * hechas / total) : 0
    return { cert, pct, total, hechas, forms, nForms: schemas.length, iniciados, vendibles }
  }), [certKeys, grouped, best])

  const totalForms = filas.reduce((a, f) => a + f.nForms, 0)
  const iniciadosTot = filas.reduce((a, f) => a + f.iniciados, 0)
  const vendiblesTot = filas.reduce((a, f) => a + f.vendibles, 0)

  return (
    <div className="overlay" onClick={onClose}>
      <div className="sheet" onClick={e => e.stopPropagation()}>
        <div className="sheet-head">
          <strong>📊 Mi progreso{slug ? ` · ${slug}` : ''}</strong>
          <button className="link" onClick={onClose}>Cerrar ✕</button>
        </div>
        <div className="tablero">
          {best === null ? <p className="muted">Cargando tu avance…</p> : (
            <>
              <p className="muted tablero-resumen">
                {iniciadosTot}/{totalForms} formularios iniciados · {vendiblesTot} listos para entregar ·
                avance guardado sin conexión.
              </p>
              {filas.map(f => (
                <div key={f.cert} className="tcert">
                  <button className="tcert-head" onClick={() => setAbierta(a => a === f.cert ? null : f.cert)}>
                    <span className="ic">{CERT_ICON[f.cert] || '📄'}</span>
                    <span className="tcert-name">{CERT_LABEL[f.cert] || f.cert}</span>
                    <span className="tcert-meta muted">{f.iniciados}/{f.nForms} form · {f.hechas}/{f.total} campos</span>
                    <span className="tcert-pct">{f.pct}%</span>
                  </button>
                  <div className="pbar"><span className={'pfill' + (f.pct >= 100 ? ' full' : '')} style={{ width: f.pct + '%' }} /></div>
                  {abierta === f.cert ? (
                    <div className="tforms">
                      {f.forms.map(fm => (
                        <button key={fm.form_key} className="tform" onClick={() => onPick(f.cert, fm.form_key)}>
                          <span className="tform-name">{fm.titulo}</span>
                          <span className="tform-bar"><span className="pfill" style={{ width: fm.p.pct + '%' }} /></span>
                          <span className="tform-pct muted">{fm.p.pct}%{fm.p.vendible ? ' ✓' : ''}</span>
                        </button>
                      ))}
                    </div>
                  ) : null}
                </div>
              ))}
            </>
          )}
        </div>
      </div>
    </div>
  )
}

export default function App() {
  const [user, setUser] = useState(null)
  const [demo, setDemo] = useState(false)
  const [ready, setReady] = useState(false)
  const { status } = useCertCapture(engine)
  const effEmail = user?.email || (demo ? 'demo@vg.local' : null)

  // contexto piloto (en producción viene del tenant + visor)
  const [slug, setSlug] = useState(() => localStorage.getItem('vg_slug') || '')
  const [misFincas, setMisFincas] = useState([])
  const [accesoEudr, setAccesoEudr] = useState(null) // null=cargando, true, false (contrato de acceso, kit #02)
  const [moduleFlags, setModuleFlags] = useState([]) // estado C del kit: lock por módulo (convención cert_<key>)
  const [perfil, setPerfil] = useState('checking') // checking | ok | necesita | omitido (gate identidad Capa 0, F1)
  const [rol, setRol] = useState(null) // rol canónico del grant eudr (gating de UI por rol)
  const [productor, setProductor] = useState(() => localStorage.getItem('vg_prod') || '')
  const [finca, setFinca] = useState(() => localStorage.getItem('vg_finca') || '')
  const [certSel, setCertSel] = useState('EUDR')
  const [formKey, setFormKey] = useState('')
  const [preview, setPreview] = useState(null)
  const [tablero, setTablero] = useState(false)
  const [estadoPorForm, setEstadoPorForm] = useState({}) // progreso por formulario del cert actual (hoja de ruta)

  useEffect(() => {
    let mounted = true
    ;(async () => {
      // Si estamos embebidos en el shell del APK, adopta la sesión del shell (postMessage) ANTES de leerla.
      // Fuera del iframe es no-op → la app standalone sigue igual (login Google normal).
      try { await adoptShellSessionIfEmbedded() } catch { /* nunca bloquea */ }
      const { data } = await supabase.auth.getSession()
      if (mounted) { setUser(data.session?.user || null); setReady(true) }
    })()
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setUser(s?.user || null))
    return () => { mounted = false; sub.subscription.unsubscribe() }
  }, [])

  useEffect(() => { setCaptureSession({ slug, email: effEmail }); localStorage.setItem('vg_slug', slug) }, [slug, effEmail])

  // Carga el producto EUDR del usuario vía la RPC canónica public.my_products() (#03): misma fuente que
  // /api/identity/me, respeta expiración y es RLS-safe (no expone otros usuarios). De ahí salen sus fincas
  // (client_slugs, las mismas del visor/ERP) y los module_flags (estado C: lock por módulo). Materializa la
  // relación cross-product: el encuestador no es una isla, comparte la finca y la cuenta del resto.
  useEffect(() => {
    if (!user) { setMisFincas([]); setAccesoEudr(null); setModuleFlags([]); setRol(null); return }
    let cancelado = false
    ;(async () => {
      // Embebido en el APK la sesión llega por postMessage (setSession) y el token puede tardar un tick en
      // propagarse → my_products correría como ANÓNIMO y devolvería [] (RPC: uid null → '[]'). Eso NO es
      // "sin acceso" (bug #06): reintentamos ante error o lista vacía teniendo sesión, y solo NEGAMOS si
      // tras los reintentos hay productos SIN eudr. Error persistente ⇒ 'error' (reintentar), no negar.
      let data = null, err = null
      for (let intento = 0; intento < 3 && !cancelado; intento++) {
        const res = await supabase.rpc('my_products')
        if (cancelado) return
        data = res.data; err = res.error
        if (!err && Array.isArray(data) && data.length > 0) break
        if (intento < 2) await new Promise(r => setTimeout(r, 600))
      }
      if (cancelado) return
      if (err) { setAccesoEudr('error'); setMisFincas([]); setModuleFlags([]); setRol(null); return }
      const eudr = (data || []).find(p => p.product === 'eudr')
      if (!eudr) { setMisFincas([]); setAccesoEudr(false); setModuleFlags([]); setRol(null); return }
      // my_products() trae role + sku_tier (mig 093, #03): fincas + permisos + rol en UNA llamada.
      setMisFincas([...new Set(eudr.client_slugs || [])].sort())
      setModuleFlags(eudr.module_flags || [])
      setRol(eudr.role || null)
      setAccesoEudr(true)
    })().catch(() => { if (!cancelado) { setAccesoEudr('error'); setMisFincas([]); setModuleFlags([]); setRol(null) } })
    return () => { cancelado = true }
  }, [user])
  useEffect(() => { localStorage.setItem('vg_prod', productor) }, [productor])
  useEffect(() => { localStorage.setItem('vg_finca', finca) }, [finca])


  // ¿el productor ya tiene su perfil Capa 0? (onboarding F1). Si la RPC get_my_profile aún no existe
  // (la construye #03) o no hay señal, NO bloqueamos: el gate queda dormido hasta que el backend exista.
  useEffect(() => {
    if (!user) { setPerfil('checking'); return }
    let on = true
    supabase.rpc('get_my_profile').then(({ data, error }) => {
      if (!on) return
      if (error) { setPerfil('ok'); return } // RPC no disponible todavía → dormido, no molesta en producción
      const p = Array.isArray(data) ? data[0] : data
      setPerfil(p && (p.has_profile || p.profile_completo) ? 'ok' : 'necesita') // contrato canónico get_my_profile (B2)
    }).catch(() => { if (on) setPerfil('ok') })
    return () => { on = false }
  }, [user])

  const grouped = useMemo(() => groupByCert(SCHEMAS), [])
  // Estado C (kit #02): si el grant trae module_flags, solo se ven las certificaciones habilitadas por un
  // flag `cert_<key>`. Comodín `*` (convención del ecosistema, lo usan tablero/visor) = todas. Sin flags =
  // acceso total a todas (caso actual de los grants eudr).
  const certKeys = useMemo(() => {
    const all = Object.keys(grouped)
    if (!moduleFlags.length || moduleFlags.includes('*')) return all
    const permitidas = all.filter(c => moduleFlags.includes('cert_' + c.toLowerCase()))
    return permitidas.length ? permitidas : all // failsafe: nunca lockear todo por un flag mal sembrado
  }, [grouped, moduleFlags])
  const formsForCert = grouped[certSel] || []
  const schema = SCHEMAS.find(s => s.form_key === formKey)
  const caps = capsDeRol(rol) // capacidades de UI según el rol (lector=solo lectura, etc.)

  // Progreso por formulario del cert seleccionado (alimenta los estados de la hoja de ruta).
  // Misma fuente de verdad que el tablero: borradores en IDB del contexto + progresoDe.
  useEffect(() => {
    let on = true
    ;(async () => {
      const all = await db.cert_responses.toArray()
      const ctx = all.filter(r => {
        const rs = r.client_slug || r.company_id
        if (slug && rs && rs !== slug) return false
        if (productor && r.productor_id && r.productor_id !== productor) return false
        if (finca && r.finca_id && r.finca_id !== finca) return false
        return true
      })
      const best = {}
      for (const r of ctx) {
        const d = r.data || {}; const sc = Object.keys(d).length
        if (!best[r.form_key] || sc > best[r.form_key].score) best[r.form_key] = { data: d, score: sc }
      }
      const map = {}
      for (const s of (grouped[certSel] || [])) {
        const p = progresoDe(s, best[s.form_key]?.data || {})
        map[s.form_key] = { pct: p.total ? Math.round(100 * p.hechas / p.total) : 0, vendible: !!p.vendible }
      }
      if (on) setEstadoPorForm(map)
    })().catch(() => {})
    return () => { on = false }
  }, [certSel, slug, productor, finca, formKey, grouped])

  // si la cert seleccionada deja de estar permitida (cambió el grant), salta a la primera visible
  useEffect(() => {
    if (certKeys.length && !certKeys.includes(certSel)) { setCertSel(certKeys[0]); setFormKey('') }
  }, [certKeys, certSel])

  function handlePreview() {
    if (!schema) return
    const cont = document.querySelector('.vg-certform')
    const data = cont ? readFormFromContainer(cont) : {}
    // plan 'free' en piloto/demo => preview con marca de agua. En producción vendría del tier del usuario.
    const html = buildCertReadyPreviewHtml(schema, { data, certificacion: schema.certificacion },
      { plan: 'free', productor_id: productor, finca_id: finca })
    setPreview(html)
  }

  if (!ready) return <div className="wrap"><div className="card">Cargando…</div></div>
  // Embebido en el shell SIN sesión adoptada: NO mostramos el login Google (el OAuth de Google no corre
  // dentro de un iframe). El shell es dueño de la sesión → ofrecemos reintentar/reabrir el módulo.
  if (EMBEBIDO && !user) return (
    <div className="wrap"><div className="card login">
      <h1>Sesión no disponible</h1>
      <p className="muted">No se pudo cargar tu sesión desde la app. Vuelve a abrir “Certificaciones” desde el
        menú de VG Suite, o reintenta.</p>
      <button type="button" className="google" onClick={() => window.location.reload()}>Reintentar</button>
    </div></div>
  )
  if (!user && !demo) return <div className="wrap"><Login onDemo={() => setDemo(true)} /></div>
  // No pudimos LEER los permisos (error/timeout de my_products) ≠ "no tiene acceso". NO mandamos a pedir
  // acceso por WhatsApp a quien SÍ tiene el grant (bug #06): ofrecemos reintentar.
  if (user && accesoEudr === 'error') return (
    <div className="wrap"><div className="card login">
      <h1>No pudimos cargar tus permisos</h1>
      <p className="muted">Tu sesión está activa, pero no se pudo leer tu acceso al Encuestador. Suele ser
        temporal — reintenta.</p>
      <button type="button" className="google" onClick={() => window.location.reload()}>Reintentar</button>
    </div></div>
  )
  // En embebido, "cambiar de cuenta" NO cierra la sesión (es compartida con el shell); recarga el módulo.
  if (user && accesoEudr === false) return <SinAcceso email={user.email} onSalir={() => EMBEBIDO ? window.location.reload() : supabase.auth.signOut()} />
  if (user && accesoEudr && perfil === 'necesita')
    return <MiPerfilGate email={user.email} onListo={() => setPerfil('ok')} onOmitir={() => setPerfil('omitido')} />

  return (
    <div className="wrap">
      <header className="topbar">
        <span className="brand"><span className="dot" /> VG · Certificaciones</span>
        {rol && ROLES[rol] ? <span className={'rolbadge ' + caps.nivel}>{ROLES[rol].label}</span> : null}
        <span className="spacer" />
        <button className="link" onClick={() => setTablero(true)}>📊 Mi progreso</button>
        <SyncBadge status={status} />
        {!EMBEBIDO ? (
          <button className="link" onClick={() => { if (user) supabase.auth.signOut(); setDemo(false) }}>Salir</button>
        ) : null}
      </header>
      {demo && !user ? (
        <div className="card" style={{ background: '#fdf3e3', borderColor: '#f0d9a8' }}>
          <strong>Modo demo.</strong> <span className="muted">Captura local real (offline-first + antifraude +
          nivel de verificación) sin sincronizar al servidor. Para sincronizar de verdad, ingresa con una cuenta VG con acceso a la finca.</span>
        </div>
      ) : null}

      <div className="card ctx">
        <h3>Contexto del levantamiento</h3>
        <div className="grid3">
          <label>Finca {misFincas.length ? `(tus ${misFincas.length} fincas)` : ''}
            {misFincas.length ? (
              <select value={slug} onChange={e => setSlug(e.target.value)}>
                <option value="">— elige tu finca —</option>
                {misFincas.map(f => <option key={f} value={f}>{f}</option>)}
              </select>
            ) : (
              <input value={slug} onChange={e => setSlug(e.target.value)} placeholder="ej. demo-cert" />
            )}
          </label>
          <label>Productor (producer_id)<input value={productor} onChange={e => setProductor(e.target.value)} placeholder="PRD-001" /></label>
          <label>Finca/Lote (finca_id)<input value={finca} onChange={e => setFinca(e.target.value)} placeholder="GY-001" /></label>
        </div>
        <p className="muted">El polígono se conecta del visor en producción; aquí el levantamiento es de piloto.</p>
      </div>

      <div className="card ctx">
        <h3>Certificación</h3>
        <div className="chips">
          {certKeys.map(c => (
            <button key={c} className={'chip ' + (certSel === c ? 'sel' : '')}
              onClick={() => { setCertSel(c); setFormKey('') }}>
              <span className="ic">{CERT_ICON[c] || '📄'}</span>{CERT_LABEL[c] || c}
            </button>
          ))}
        </div>
        <select value={formKey} onChange={e => setFormKey(e.target.value)}>
          <option value="">— elegir formulario ({formsForCert.length}) —</option>
          {formsForCert.map(s => <option key={s.form_key} value={s.form_key}>{s.titulo}</option>)}
        </select>
      </div>

      {schema ? (
        <div className="card">
          {caps.esLector ? (
            <div className="rol-aviso lectura">👁️ Modo solo lectura. Tu rol puede revisar y previsualizar, pero no editar ni guardar capturas.</div>
          ) : null}
          <CertForm
            schema={schema}
            engine={engine}
            readonly={caps.esLector}
            productor_id={productor || null}
            finca_id={finca || null}
            onConnectPolygon={async () => {
              // En el APK, el shell abre el mapa del visor (bridge SSO #07/#11) y devuelve el polígono real.
              // En esta PWA suelta (piloto) devolvemos un polígono de ejemplo para mostrar el flujo.
              const demo = { type: 'Polygon', coordinates: [[[-79.46, -1.47], [-79.455, -1.47], [-79.455, -1.465], [-79.46, -1.465], [-79.46, -1.47]]] }
              return { geoshape: demo, origen: 'capturado_aqui' }
            }}
            onSaved={(res) => { /* el badge refleja el estado; el sync es automático */ }}
          />
          <div className="export-bar">
            <button type="button" className="primary" onClick={handlePreview}>📄 Vista previa para el certificador</button>
            <span className="muted">Borrador con marca de agua. El entregable válido para entregar requiere un plan de pago.</span>
          </div>
        </div>
      ) : (
        <RoadmapCert
          cert={CERT_LABEL[certSel] || certSel}
          ruta={(bundle.rutas || {})[certSel]}
          forms={formsForCert}
          estadoPorForm={estadoPorForm}
          onPick={(fk) => { setFormKey(fk); window.scrollTo(0, 0) }}
        />
      )}

      <footer className="foot muted">
        {SCHEMAS.length} formularios · {bundle.totales?.n_control_points || '—'} puntos de control · datos sellados con cadena de integridad. noindex.
      </footer>

      {tablero ? (
        <TableroProgreso
          grouped={grouped} certKeys={certKeys}
          slug={slug} productor={productor} finca={finca}
          onPick={(cert, fk) => { setCertSel(cert); setFormKey(fk); setTablero(false); window.scrollTo(0, 0) }}
          onClose={() => setTablero(false)}
        />
      ) : null}

      {preview ? (
        <div className="overlay" onClick={() => setPreview(null)}>
          <div className="sheet" onClick={e => e.stopPropagation()}>
            <div className="sheet-head">
              <strong>Vista previa para el certificador</strong>
              <button className="link" onClick={() => setPreview(null)}>Cerrar ✕</button>
            </div>
            <iframe className="sheet-frame" srcDoc={preview} title="Vista previa cert-ready" />
          </div>
        </div>
      ) : null}
    </div>
  )
}
