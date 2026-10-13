import React, { useEffect, useMemo, useState } from 'react'
import { CertForm, useCertCapture, readFormFromContainer, progresoDe } from './eudr-react/index.js'
import { Icono } from './eudr-react/CertForm.jsx'
import { rehidratarVersiones, enContexto } from './eudr-react/capture/cert-offline-engine.js'
import { buildCertReadyPreviewHtml } from './eudr-react/capture/export-policy.js'
import { engine, setCaptureSession, db, traerDelServidor, limpiarRespaldadoDelEquipo, clasificarError } from './engine.js'
import { RespaldoAviso, IntegridadCadena } from './Respaldo.jsx'
import { supabase } from './supabase.js'
import { adoptShellSessionIfEmbedded, estamosEmbebidos, consumeHandoffIfPresent } from './shell-bridge.js'

// ¿corremos embebidos en el shell del APK? (iframe). Gatea el comportamiento que NO aplica embebido:
// el shell es dueño de la sesión y de la navegación → no cerramos sesión ni mostramos login propio.
const EMBEBIDO = estamosEmbebidos()
import bundle from './schemas.bundle.json'
import RoadmapCert from './RoadmapCert.jsx'
import Boveda from './Boveda.jsx'
import { VGLogin } from '@vgsdk/auth-ui'
/* C1 · comprobacion de contrasenas filtradas. Vive en @vgsdk/auth y se exporta desde la entrada
   principal (index.ts:83), asi que NO hace falta subruta ni subir de version de auth-ui: el
   componente pone la caja y el producto trae el motor (inversion de control). Ver CABLEAR-C1.md. */
import { contrasenaFiltrada, mensajeSiFiltrada } from '@vgsdk/auth'
import { DesafioSegundoFactor, faltaSegundoFactor, verificarCodigoTotp } from './SegundoFactor.jsx'

const SCHEMAS = (bundle.schemas || []).filter(s => !s.legacy)
const CERTS = bundle.certificaciones || []
const CERT_LABEL = Object.assign(
  Object.fromEntries(CERTS.map(c => [c.key, c.titulo])),
  { FSC: 'FSC — Manejo forestal', PEFC: 'PEFC — Manejo forestal' }
)
// Íconos Material Symbols (línea visual VG: nunca emojis en cara pública)
const CERT_ICON = {
  GENERAL: 'assignment', EUDR: 'shield', FSC: 'forest', FSC_FM: 'forest', FSC_CoC: 'link', RFA: 'eco',
  PEFC: 'park', PEFC_FM: 'park', PEFC_CoC: 'link', RSPO: 'nature', ISCC: 'nature', CARBONO: 'co2',
  USDA_ORGANIC: 'compost', GLOBAL_GAP: 'verified', MARBETE_AGROCALIDAD: 'sell', COMPARTIDO: 'hub'
}

/* Estado VIGENTE de cada formulario en el contexto elegido: el mismo pliegue de versiones que usa el
   formulario al retomarse (rehidratarVersiones). Antes el tablero y la hoja de ruta tomaban «el
   borrador con más campos», que con guardados parciales podía no ser ninguno de los que se ven. */
function vigentesPorForm(all, { slug, productor, finca }) {
  const grupos = {}
  for (const r of all) {
    if (!enContexto(r, { company_id: slug || null, productor_id: productor || null, finca_id: finca || null })) continue
    ;(grupos[r.form_key] = grupos[r.form_key] || []).push(r)
  }
  const m = {}
  for (const [fk, rows] of Object.entries(grupos)) {
    const v = rehidratarVersiones(rows)
    const ult = rows.slice().sort((a, b) => (b.created_at || 0) - (a.created_at || 0))[0]
    if (v) m[fk] = { data: v.data, sync: ult && ult.sync_status }
  }
  return m
}

// R-FECHA-VERSIÓN: versión y hora de la construcción (las fija vite.config.js al construir)
const VG_VERSION = typeof __VG_VERSION__ !== 'undefined' ? __VG_VERSION__ : 'dev'
const VG_BUILD = typeof __VG_BUILD__ !== 'undefined' ? __VG_BUILD__ : ''

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

// Login único del ecosistema VG: componente compartido <VGLogin> (@vgsdk/auth-ui).
// Mismas vías + look que visor/erp/campo (Google + correo/contraseña + magic-link),
// branding por tenant, marca VG siempre. cert SOLO inyecta sus handlers Supabase
// (desacoplado). El modo demo se conserva debajo (gancho de exploración sin sesión).
function Login({ onDemo, onAvisoC1 }) {
  return (
    <div style={{ width: '100%', maxWidth: 420, margin: '0 auto' }}>
      <VGLogin
        branding={{ tenantName: 'VG · Certificaciones' }}
        onGoogle={async () => {
          const { error } = await supabase.auth.signInWithOAuth({
            provider: 'google',
            options: { redirectTo: window.location.origin + window.location.pathname }
          })
          if (error) throw new Error(error.message)
        }}
        /* Segundo factor (código de 6 dígitos). Llega con @vgsdk/auth-ui@1.0.0.
         *
         * 🔴 EL CONTRATO, y es lo que advirtió #11 al construirlo: el MFA se señala **resolviendo
         * con "mfa"**, NUNCA lanzando. El componente ya trata `throw` como fallo, y necesitar un
         * código NO es un fallo: es éxito a medias. Si se lanzara, la ruta de error existente le
         * diría al usuario que su contraseña falló — cuando fue correcta.
         *
         * Cómo se sabe que falta: Supabase compara el nivel de garantía ACTUAL con el SIGUIENTE.
         * Si difieren (`aal1` vs `aal2`), la cuenta tiene un factor inscrito y todavía no se
         * verificó en esta sesión. Quien no tenga MFA da los dos iguales y este camino ni se toca:
         * por eso las cuentas de siempre entran igual que ayer.
         *
         * 🔴 13-oct-2026 (ASVS L1): este paso por sí solo NO protegía. La sesión aal1 llega a la app por
         * onAuthStateChange en cuanto signInWithPassword responde, y la app la aceptaba sin mirar el nivel.
         * Ahora quien manda es la compuerta de App (faltaSegundoFactor → DesafioSegundoFactor), que corre en
         * TODA sesión: contraseña, Google, enlace por correo y sesión guardada al recargar. */
        onPassword={async (email, password) => {
          /* 🔴 C1 AVISA, NO BLOQUEA — y me aparto a proposito del recorte de #11, que hace
           * `if (aviso) throw`. La razon esta medida en el propio motor, no es corazonada:
           *
           *   filtradas.ts:148  «bloquear un CAMBIO de contrasena porque no hay senal rompe...»
           *   filtradas.ts:157  el mensaje termina en «Conviene elegir otra.»
           *
           * El motor esta escrito para el momento en que alguien ELIGE una clave. Aqui es un
           * INICIO DE SESION, y cert no tiene registro ni cambio de clave: `onGoogle`,
           * `onPassword`, `onTotp`, `onMagicLink` y nada mas. Lanzar dejaria a la persona fuera
           * de su propia cuenta con un texto que le pide algo que esa pantalla no permite hacer.
           * Eso no es un control: es una puerta cerrada sin llave, y en campo se traduce en un
           * tecnico que no puede capturar. Se comprueba, se deja entrar, y se avisa dentro.
           *
           * Se mira ANTES del signIn porque es cuando se tiene el texto plano en la mano.
           * `contrasenaFiltrada` NUNCA lanza por red: devuelve `desconocido`, que deja pasar. */
          let avisoFiltrada = null
          try { avisoFiltrada = mensajeSiFiltrada(await contrasenaFiltrada(password)) }
          catch (e) { /* ni un fallo del propio control puede impedir entrar */ }
          const { error } = await supabase.auth.signInWithPassword({ email, password })
          if (error) throw new Error(error.message)
          if (avisoFiltrada && onAvisoC1) onAvisoC1(avisoFiltrada)
          const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel()
          if (aal && aal.nextLevel && aal.currentLevel !== aal.nextLevel) return 'mfa'
        }}
        /* La misma verificación que el desafío de la compuerta (SegundoFactor.jsx): lanza si el código falla. */
        onTotp={verificarCodigoTotp}
        onMagicLink={async (email) => {
          const { error } = await supabase.auth.signInWithOtp({
            email,
            options: { emailRedirectTo: window.location.origin + window.location.pathname }
          })
          if (error) throw new Error(error.message)
        }}
      />
      <button type="button" className="link demo-link" style={{ marginTop: 12, display: 'block', width: '100%', textAlign: 'center' }} onClick={onDemo}>
        Explorar en modo demo (captura local, sin sincronizar) <Icono n="arrow_forward" />
      </button>
      {/* R-AYUDA: el centro de ayuda en video vive dentro del producto (/ayuda/) */}
      <a className="ayuda-enlace" href="ayuda/"><Icono n="play_circle" />Ayuda en video</a>
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

const CLAVE_PERFIL_PENDIENTE = 'vg_perfil_pendiente'
const leerPerfilPendiente = () => { try { return JSON.parse(localStorage.getItem(CLAVE_PERFIL_PENDIENTE) || 'null') } catch { return null } }
const borrarPerfilPendiente = () => { try { localStorage.removeItem(CLAVE_PERFIL_PENDIENTE) } catch {} }

function mensajePerfil(codigo) {
  const c = String(codigo || '')
  if (/campos_obligatorios/.test(c)) return 'Faltan datos obligatorios: identificación, nombre, apellido y cargo.'
  if (/duplicate|unique|23505|ya (existe|est[aá] registrad)/i.test(c))
    return 'Ese número de identificación ya está registrado en otra cuenta. Escriba a Visión Geográfica para revisarlo.'
  return 'No se pudo guardar el perfil (' + (c || 'sin detalle') + ').'
}

/**
 * Registra el perfil en el servidor con el contrato CANÓNICO de identidad (bus B2, dueño #03), en el orden que
 * indicó #03: ensure_producer_self (crea/enlaza el producer por el email del JWT + consent base) →
 * upsert_my_profile (identidad real con la cédula). R23: no se reimplementa; es el mismo «Mi perfil» del visor/ERP.
 *
 * 🔴 13-oct-2026 (auditoría ASVS L1): se llamaba a upsert_my_profile con 5 argumentos. La versión de 7 —la que
 * PostgREST elige con esos nombres— exige p_cargo y, si falta, CONTESTA {ok:false, error:'campos_obligatorios'}
 * sin error ni excepción. Solo se miraba `error`: el perfil se daba por guardado y no se guardaba nunca. Tampoco
 * se miraba el resultado de ensure_producer_self. Ahora se miran los dos, y se manda p_cargo.
 * @returns {Promise<{ ok: true } | { red: true } | { error: string }>} red = sin señal (se guarda en el equipo)
 */
async function registrarPerfil(d) {
  const fallo = (err) => (clasificarError(err).tipo === 'sin_red' ? { red: true } : { error: mensajePerfil(err && (err.message || err.code)) })
  try {
    const r1 = await supabase.rpc('ensure_producer_self', { p_display_name: (d.nombre + ' ' + d.apellido).trim(), p_tenant_slug_origin: 'eudr' })
    if (r1.error) return fallo(r1.error)
    if (r1.data && r1.data.ok === false) return { error: mensajePerfil(r1.data.error) }
    const r2 = await supabase.rpc('upsert_my_profile', {
      p_nombre: d.nombre, p_apellido: d.apellido, p_cargo: d.cargo,
      p_tipo_documento: d.tipo, p_numero_documento: d.ident,
      p_telefono: d.telefono || null
    })
    if (r2.error) return fallo(r2.error)
    if (r2.data && r2.data.ok === false) return { error: mensajePerfil(r2.data.error) }
    return { ok: true }
  } catch (e) { return fallo(e) }
}

// Gate "Mi perfil" — identidad Capa 0 del productor (onboarding F1). La identificación (cédula/RUC/
// pasaporte) es el ancla única anti-duplicados que hace las certificaciones tuyas y auditables.
// R1-safe: "Completar luego" nunca bloquea. R2: SOLO sin señal se guarda en el equipo y se avanza; se registra
// la próxima vez que la app abra con señal. Si el servidor RECHAZA el perfil, se dice y no se da por guardado.
function MiPerfilGate({ email, onListo, onOmitir, inicial = null, avisoInicial = null }) {
  const [tipo, setTipo] = useState(inicial?.tipo || 'cedula')
  const [ident, setIdent] = useState(inicial?.ident || '')
  const [nombre, setNombre] = useState(inicial?.nombre || '')
  const [apellido, setApellido] = useState(inicial?.apellido || '')
  const [cargo, setCargo] = useState(inicial?.cargo || '')
  const [telefono, setTelefono] = useState(inicial?.telefono || '')
  const [consent, setConsent] = useState(!!inicial?.consent)
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState(avisoInicial)
  const LABELS = { cedula: 'Cédula', ruc: 'RUC', pasaporte: 'Pasaporte' }

  async function guardar(e) {
    e.preventDefault()
    if (!ident.trim() || !nombre.trim() || !apellido.trim() || !cargo.trim()) { setMsg('Completa tu identificación, nombre, apellido y cargo.'); return }
    if (!consent) { setMsg('Necesitamos tu autorización para guardar tus datos.'); return }
    setBusy(true); setMsg(null)
    const d = { tipo, ident: ident.trim(), nombre: nombre.trim(), apellido: apellido.trim(), cargo: cargo.trim(), telefono: telefono.trim(), consent }
    const r = await registrarPerfil(d)
    setBusy(false)
    if (r.ok) { borrarPerfilPendiente(); onListo(true); return }
    if (r.red) {
      // sin señal: se guarda en el dispositivo y se deja avanzar (R1: no bloquear). Se registra al volver la señal.
      try { localStorage.setItem(CLAVE_PERFIL_PENDIENTE, JSON.stringify(d)) } catch {}
      setMsg('Sin señal: guardamos tu perfil en este dispositivo; se registrará la próxima vez que abras la app con señal.')
      setTimeout(() => onListo(true), 1600)
      return
    }
    setMsg(r.error)   // el servidor lo rechazó: se dice y NO se da por guardado
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
        <label>Cargo<input value={cargo} onChange={e => setCargo(e.target.value)} list="cargos-perfil" placeholder="ej. Productor, técnico de campo" required /></label>
        <datalist id="cargos-perfil">
          <option value="Productor" /><option value="Técnico de campo" /><option value="Gerente de finca" />
          <option value="Responsable de certificaciones" /><option value="Supervisor" />
        </datalist>
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
function TableroProgreso({ grouped, certKeys, slug, productor, finca, onPick, onClose, conSesion = false }) {
  const [best, setBest] = useState(null)
  const [abierta, setAbierta] = useState(null)
  useEffect(() => {
    let on = true
    ;(async () => {
      // con sesión y finca, primero lo que esté en el servidor y falte en este equipo (retomar desde otro equipo);
      // con tope de 6 s: sin señal, el tablero se arma con lo del equipo
      try { await Promise.race([traerDelServidor(null), new Promise(r => setTimeout(r, 6000))]) } catch {}
      const all = await db.cert_responses.toArray()
      if (on) setBest(vigentesPorForm(all, { slug, productor, finca }))
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
          <strong><Icono n="bar_chart" />Mi progreso{slug ? ` · ${slug}` : ''}</strong>
          <button className="link" onClick={onClose}>Cerrar <Icono n="close" /></button>
        </div>
        <div className="tablero">
          {best === null ? <p className="muted">Cargando tu avance…</p> : (
            <>
              <p className="muted tablero-resumen">
                {iniciadosTot}/{totalForms} formularios iniciados · {vendiblesTot} listos para entregar ·
                avance guardado sin conexión{conSesion && slug ? ', y lo respaldado en el servidor desde cualquier equipo' : ''}.
              </p>
              {filas.map(f => (
                <div key={f.cert} className="tcert">
                  <button className="tcert-head" onClick={() => setAbierta(a => a === f.cert ? null : f.cert)}>
                    <Icono n={CERT_ICON[f.cert] || 'description'} className="ic" />
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
                          <span className="tform-pct muted">{fm.p.pct}%{fm.p.vendible ? <Icono n="check_circle" className="ok" /> : null}</span>
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
  /* 🔴 Segundo factor (13-oct-2026). `sesionUser` es el usuario de la sesión, tenga el nivel que tenga; `user`
     —el que usa TODA la app: permisos, perfil, respaldo— solo existe cuando la sesión ya cumplió el segundo
     factor (o la cuenta no lo tiene). Así ninguna llamada con sesión sale mientras falte el código. */
  const [sesionUser, setSesionUser] = useState(null)
  const [aal, setAal] = useState('ok') // ok · falta (la cuenta tiene factor verificado y la sesión es aal1)
  const user = aal === 'ok' ? sesionUser : null
  // ?demo=1 entra directo al modo demostración (enlaces «Probarlo» del centro de ayuda). Captura local, sin sincronizar.
  const [demo, setDemo] = useState(() => { try { return new URLSearchParams(window.location.search).has('demo') } catch { return false } })
  const [avisoC1, setAvisoC1] = useState(null)   // C1: contrasena en filtraciones. Avisa, no bloquea.
  const [ready, setReady] = useState(false)
  const { status, flush } = useCertCapture(engine)
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
  const [boveda, setBoveda] = useState(false)
  const [estadoPorForm, setEstadoPorForm] = useState({}) // progreso por formulario del cert actual (hoja de ruta)
  const [salida, setSalida] = useState(null) // null · { pendientes } (pide confirmar) · 'saliendo'

  useEffect(() => {
    let mounted = true
    /* El nivel se calcula ANTES de entregar el usuario: si se fijara primero, la app alcanzaría a pintarse con
       la sesión aal1. Cada cambio lleva su turno y solo el último se aplica. No se pasa por «Cargando…» en cada
       renovación del token: eso desmontaría el formulario y perdería lo escrito sin guardar. */
    let turno = 0
    async function aplicarSesion(session) {
      const mio = ++turno
      const falta = await faltaSegundoFactor(session).catch(() => !!session)
      if (!mounted || mio !== turno) return
      setSesionUser(session?.user || null)
      setAal(falta ? 'falta' : 'ok')
    }
    ;(async () => {
      // Handoff SSO "Abrir aparte": si el APK abrió cert standalone con ?vg_handoff=<code>, canjea el
      // code por sesión ANTES de leerla → no re-login. Si no hay code o falla, es no-op (login normal).
      try { await consumeHandoffIfPresent() } catch { /* nunca bloquea */ }
      // Si estamos embebidos en el shell del APK, adopta la sesión del shell (postMessage) ANTES de leerla.
      // Fuera del iframe es no-op → la app standalone sigue igual (login Google normal).
      try { await adoptShellSessionIfEmbedded() } catch { /* nunca bloquea */ }
      const { data } = await supabase.auth.getSession()
      await aplicarSesion(data.session)
      if (mounted) setReady(true)
    })()
    /* Se difiere con setTimeout: en versiones anteriores de supabase-js, llamar a sus métodos DENTRO de este aviso
       podía trabarse (el aviso corría con el candado de la sesión tomado). La 2.108 instalada dice que ya es seguro;
       diferirlo no cuesta nada y protege si el paquete cambia de versión. */
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => { setTimeout(() => { aplicarSesion(s) }, 0) })
    return () => { mounted = false; sub.subscription.unsubscribe() }
  }, [])

  // tras verificar el código, se vuelve a mirar el nivel con la sesión nueva (aal2)
  async function revisarNivel() {
    const { data } = await supabase.auth.getSession()
    const falta = await faltaSegundoFactor(data.session).catch(() => !!data.session)
    setSesionUser(data.session?.user || null)
    setAal(falta ? 'falta' : 'ok')
  }

  // vacío = se quita la clave (no se deja una clave vacía: al salir se borran todas las vg_*)
  const guardarLocal = (k, v) => { try { if (v) localStorage.setItem(k, v); else localStorage.removeItem(k) } catch {} }
  useEffect(() => { setCaptureSession({ slug, email: effEmail }); guardarLocal('vg_slug', slug) }, [slug, effEmail])

  // 🔴 Respaldo (6-oct-2026): al entrar con sesión o al elegir la finca se intenta respaldar lo pendiente (antes
  // solo al guardar o al volver la señal), y mientras quede algo pendiente se reintenta cada 90 s.
  const pendientes = (status.pending || 0) + (status.failed || 0)
  useEffect(() => { if (user && slug) flush() }, [user, slug, flush])
  useEffect(() => {
    if (!user || !slug || !pendientes) return
    const t = setInterval(() => { flush() }, 90000)
    return () => clearInterval(t)
  }, [user, slug, pendientes, flush])

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
  useEffect(() => { guardarLocal('vg_prod', productor) }, [productor])
  useEffect(() => { guardarLocal('vg_finca', finca) }, [finca])

  /* 🔴 SALIR (13-oct-2026, auditoría ASVS L1). Antes solo cerraba la sesión y dejaba en el teléfono la finca, el
     productor, el perfil pendiente (con la cédula) y todo lo capturado. Ahora: se intenta respaldar lo pendiente
     (8 s como tope); si aun así queda algo sin respaldar, se avisa y se pide confirmar; al salir se borran las
     claves vg_* y lo ya respaldado de la base local (limpiarRespaldadoDelEquipo). Lo pendiente no se borra (R1).
     En modo demo «Salir» sigue siendo solo dejar la demo: sus capturas esperan a que alguien inicie sesión. */
  async function salir(confirmado = false) {
    if (!user) { setDemo(false); return }
    if (!confirmado) {
      setSalida('saliendo')
      try { await Promise.race([flush(), new Promise(r => setTimeout(r, 8000))]) } catch {}
      const n = await db.cert_responses.where('sync_status').anyOf('pending', 'failed').count().catch(() => 0)
      if (n) { setSalida({ pendientes: n }); return }
    }
    setSalida('saliendo')
    try { await limpiarRespaldadoDelEquipo() } catch { /* no impide salir */ }
    try {
      for (const k of Object.keys(localStorage)) if (k.startsWith('vg_')) localStorage.removeItem(k)
    } catch {}
    setSlug(''); setProductor(''); setFinca(''); setFormKey('')
    const { error } = await supabase.auth.signOut()
    if (error) {
      /* Sin señal, supabase-js no puede avisar al servidor y DEJA la sesión puesta (devuelve el error sin borrarla).
         Se quita del equipo a mano y se recarga: en este teléfono ya no queda sesión. */
      try {
        localStorage.removeItem(supabase.auth.storageKey)
        localStorage.removeItem(supabase.auth.storageKey + '-code-verifier')
      } catch {}
      window.location.reload()
      return
    }
    setSalida(null); setDemo(false)
  }


  // ¿el productor ya tiene su perfil Capa 0? (onboarding F1). Si la RPC get_my_profile aún no existe
  // (la construye #03) o no hay señal, NO bloqueamos: el gate queda dormido hasta que el backend exista.
  // 13-oct-2026: un perfil guardado sin señal por fin se registra aquí (antes se prometía «se registrará al volver
  // la señal» y nada lo leía). Si el servidor lo rechaza, el formulario vuelve con el motivo y lo ya escrito.
  const [perfilInicial, setPerfilInicial] = useState(null) // { datos, aviso } para precargar el formulario
  useEffect(() => {
    if (!user) { setPerfil('checking'); return }
    let on = true
    supabase.rpc('get_my_profile').then(async ({ data, error }) => {
      if (!on) return
      if (error) { setPerfil('ok'); return } // RPC no disponible todavía → dormido, no molesta en producción
      const p = Array.isArray(data) ? data[0] : data
      const tiene = !!(p && (p.has_profile || p.profile_completo)) // contrato canónico get_my_profile (B2)
      const pend = leerPerfilPendiente()
      if (tiene) { if (pend) borrarPerfilPendiente(); setPerfil('ok'); return }
      if (!pend) { setPerfil('necesita'); return }
      const r = await registrarPerfil(pend)
      if (!on) return
      if (r.ok) { borrarPerfilPendiente(); setPerfil('ok'); return }
      if (r.red) { setPerfil('ok'); return }   // sigue sin señal: se reintenta la próxima vez
      setPerfilInicial({ datos: pend, aviso: r.error })
      setPerfil('necesita')
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
      const best = vigentesPorForm(await db.cert_responses.toArray(), { slug, productor, finca })
      const map = {}
      /* 🔴 Los tramos del NÚCLEO compartido (shared_*) son de la certificación COMPARTIDO, no de la norma
         elegida: iterando solo grouped[certSel] nunca tenían estado, la hoja de ruta los mostraba «sin
         empezar» aunque ya estuvieran capturados y la «Ventaja inicial» no aparecía nunca (lo destapó la
         grabación del video de ayuda, 5-oct-2026). Se calcula el estado de TODOS los tramos de la ruta. */
      const claves = new Set((grouped[certSel] || []).map(s => s.form_key))
      for (const pil of (((bundle.rutas || {})[certSel] || {}).pilares || [])) for (const t of pil.tramos || []) claves.add(t.form_key)
      for (const fk of claves) {
        const s = SCHEMAS.find(x => x.form_key === fk)
        if (!s) continue
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

  // Confirmación de «Salir» con versiones sin respaldar. Va en la vista principal y en la de «sin acceso».
  const hojaSalida = salida && salida.pendientes ? (
    <div className="overlay" onClick={() => setSalida(null)}>
      <div className="sheet" onClick={e => e.stopPropagation()} role="alertdialog" aria-labelledby="salida-titulo">
        <div className="sheet-head">
          <strong id="salida-titulo"><Icono n="warning" />Quedan {salida.pendientes} {salida.pendientes === 1 ? 'versión' : 'versiones'} sin respaldar</strong>
        </div>
        <div className="tablero">
          <p>Están guardadas solo en este equipo y todavía no llegaron al servidor.</p>
          <p className="muted">Si sale ahora, no se borran: se quedan en este teléfono hasta que se respalden, y
            quien use el equipo después podría verlas. Lo que ya está respaldado, la finca elegida y el perfil
            pendiente sí se borran de este equipo.</p>
          <div className="export-bar">
            <button type="button" className="primary" onClick={() => { setSalida(null); flush() }}>
              <Icono n="cloud_upload" />Quedarme y respaldar</button>
            <button type="button" className="link" onClick={() => salir(true)}>Salir de todas formas</button>
          </div>
        </div>
      </div>
    </div>
  ) : null

  if (!ready) return <div className="wrap"><div className="card">Cargando…</div></div>
  // Sesión abierta sin el segundo factor: ni la app ni ninguna llamada con sesión hasta verificar el código.
  // Embebido, «Usar otra cuenta» no cierra la sesión (es la del shell): recarga el módulo, igual que SinAcceso.
  if (sesionUser && aal === 'falta') return (
    <DesafioSegundoFactor email={sesionUser.email} onVerificado={revisarNivel}
      onOtraCuenta={() => EMBEBIDO ? window.location.reload() : supabase.auth.signOut()} />
  )
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
  if (!user && !demo) return <div className="wrap"><Login onDemo={() => setDemo(true)} onAvisoC1={setAvisoC1} /></div>
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
  if (user && accesoEudr === false) return <>{hojaSalida}<SinAcceso email={user.email} onSalir={() => EMBEBIDO ? window.location.reload() : salir()} /></>
  if (user && accesoEudr && perfil === 'necesita')
    return <MiPerfilGate email={user.email} inicial={perfilInicial?.datos} avisoInicial={perfilInicial?.aviso}
      onListo={() => setPerfil('ok')} onOmitir={() => setPerfil('omitido')} />

  return (
    <div className="wrap">
      {avisoC1 && (
        <div className="card" style={{ borderLeft: '4px solid #d97706', marginBottom: 12 }} role="status">
          <strong>Conviene cambiar su contraseña</strong>
          <p className="muted" style={{ margin: '6px 0 10px' }}>{avisoC1}</p>
          <button type="button" className="link" onClick={() => setAvisoC1(null)}>Entendido</button>
        </div>
      )}
      <header className="topbar">
        <span className="brand"><span className="dot" /> VG · Certificaciones</span>
        {rol && ROLES[rol] ? <span className={'rolbadge ' + caps.nivel}>{ROLES[rol].label}</span> : null}
        <span className="spacer" />
        <button className="link" onClick={() => setTablero(true)}><Icono n="bar_chart" />Mi progreso</button>
        <button className="link" onClick={() => setBoveda(true)}><Icono n="lock" />Mi bóveda</button>
        <a className="link" href="ayuda/"><Icono n="play_circle" />Ayuda en video</a>
        <SyncBadge status={status} />
        {!EMBEBIDO ? (
          <button className="link" disabled={salida === 'saliendo'} onClick={() => salir()}>{salida === 'saliendo' ? 'Saliendo…' : 'Salir'}</button>
        ) : null}
      </header>
      {/* El respaldo, a la vista y sin abrir nada (6-oct-2026). En modo demo es el aviso amarillo de siempre, con
          la cuenta de lo que queda solo en este equipo. */}
      {!caps.esLector ? (
        <RespaldoAviso
          status={status} conSesion={!!user} demo={demo && !user} slug={slug} email={user?.email}
          onFlush={flush}
          onLogin={() => { setDemo(false); if (user) supabase.auth.signOut() }}
          onElegirFinca={() => { const el = document.getElementById('campo-finca'); if (el) { el.scrollIntoView({ block: 'center' }); el.focus() } }}
        />
      ) : null}

      <div className="card ctx">
        <h3>Contexto del levantamiento</h3>
        <div className="grid3">
          <label>Finca {misFincas.length ? `(tus ${misFincas.length} fincas)` : ''}
            {misFincas.length ? (
              <select id="campo-finca" value={slug} onChange={e => setSlug(e.target.value)}>
                <option value="">— elige tu finca —</option>
                {misFincas.map(f => <option key={f} value={f}>{f}</option>)}
              </select>
            ) : (
              <input id="campo-finca" value={slug} onChange={e => setSlug(e.target.value)} placeholder="ej. demo-cert" />
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
              <Icono n={CERT_ICON[c] || 'description'} className="ic" />{CERT_LABEL[c] || c}
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
            <div className="rol-aviso lectura"><Icono n="visibility" />Modo solo lectura. Tu rol puede revisar y previsualizar, pero no editar ni guardar capturas.</div>
          ) : null}
          {user && slug ? <IntegridadCadena formKey={formKey} refrescar={status.synced} /> : null}
          <CertForm
            key={[formKey, slug, productor, finca].join('|')}
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
            <button type="button" className="primary" onClick={handlePreview}><Icono n="description" />Vista previa para el certificador</button>
            <span className="muted">Borrador con marca de agua. El entregable válido para el certificador es una función premium.</span>
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
        {SCHEMAS.length} formularios · {bundle.totales?.n_control_points || '—'} puntos de control · datos sellados con cadena de integridad.
        <div className="foot-vg">VG Certificaciones™ · Visión Geográfica™ · Versión {VG_VERSION}{VG_BUILD ? ' · ' + VG_BUILD : ''} · <a href="https://www.visiongeografica.com/privacidad/" target="_blank" rel="noopener">Política de privacidad</a></div>
      </footer>

      {tablero ? (
        <TableroProgreso
          grouped={grouped} certKeys={certKeys}
          slug={slug} productor={productor} finca={finca} conSesion={!!user}
          onPick={(cert, fk) => { setCertSel(cert); setFormKey(fk); setTablero(false); window.scrollTo(0, 0) }}
          onClose={() => setTablero(false)}
        />
      ) : null}

      {boveda ? (
        <Boveda
          slug={slug} productor={productor} finca={finca}
          status={status} onFlush={flush}
          conSesion={!!user} demo={demo && !user} email={user?.email}
          onClose={() => setBoveda(false)}
        />
      ) : null}

      {hojaSalida}

      {preview ? (
        <div className="overlay" onClick={() => setPreview(null)}>
          <div className="sheet" onClick={e => e.stopPropagation()}>
            <div className="sheet-head">
              <strong>Vista previa para el certificador</strong>
              <button className="link" onClick={() => setPreview(null)}>Cerrar <Icono n="close" /></button>
            </div>
            <iframe className="sheet-frame" srcDoc={preview} title="Vista previa cert-ready" />
          </div>
        </div>
      ) : null}
    </div>
  )
}
