import React, { useEffect, useMemo, useState } from 'react'
import { CertForm, useCertCapture, readFormFromContainer } from './eudr-react/index.js'
import { buildCertReadyPreviewHtml } from './eudr-react/capture/export-policy.js'
import { engine, setCaptureSession } from './engine.js'
import { supabase } from './supabase.js'
import bundle from './schemas.bundle.json'

const SCHEMAS = (bundle.schemas || []).filter(s => !s.legacy)
const CERTS = bundle.certificaciones || []
const CERT_LABEL = Object.fromEntries(CERTS.map(c => [c.key, c.titulo]))
const CERT_ICON = {
  GENERAL: '📋', EUDR: '🛡️', FSC: '🌲', FSC_FM: '🌲', FSC_CoC: '🔗', RFA: '🐸',
  USDA_ORGANIC: '🌱', GLOBAL_GAP: '✅', MARBETE_AGROCALIDAD: '🏷️', COMPARTIDO: '🔗'
}

function groupByCert(schemas) {
  const g = {}
  for (const s of schemas) {
    const c = (s.certificacion === 'FSC_FM' || s.certificacion === 'FSC_CoC') ? 'FSC' : s.certificacion
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
  async function signIn(e) {
    e.preventDefault(); setBusy(true); setMsg(null)
    const { error } = await supabase.auth.signInWithPassword({ email, password: pass })
    if (error) setMsg(error.message)
    setBusy(false)
  }
  return (
    <form className="card login" onSubmit={signIn}>
      <h1>VG · Captura de Certificaciones</h1>
      <p className="muted">Ingresa con tu cuenta del ecosistema VG. El acceso a cada finca lo controla
        el servidor (RLS). Captura offline; sincroniza al volver la conexión.</p>
      <label>Correo<input type="email" value={email} onChange={e => setEmail(e.target.value)} required /></label>
      <label>Contraseña<input type="password" value={pass} onChange={e => setPass(e.target.value)} required /></label>
      <button disabled={busy}>{busy ? 'Ingresando…' : 'Ingresar'}</button>
      {msg ? <div className="err">{msg}</div> : null}
      <button type="button" className="link demo-link" onClick={onDemo}>
        Explorar en modo demo (captura local, sin sincronizar) →
      </button>
    </form>
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
  const [productor, setProductor] = useState(() => localStorage.getItem('vg_prod') || '')
  const [finca, setFinca] = useState(() => localStorage.getItem('vg_finca') || '')
  const [certSel, setCertSel] = useState('EUDR')
  const [formKey, setFormKey] = useState('')
  const [preview, setPreview] = useState(null)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => { setUser(data.session?.user || null); setReady(true) })
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setUser(s?.user || null))
    return () => sub.subscription.unsubscribe()
  }, [])

  useEffect(() => { setCaptureSession({ slug, email: effEmail }); localStorage.setItem('vg_slug', slug) }, [slug, effEmail])
  useEffect(() => { localStorage.setItem('vg_prod', productor) }, [productor])
  useEffect(() => { localStorage.setItem('vg_finca', finca) }, [finca])

  const grouped = useMemo(() => groupByCert(SCHEMAS), [])
  const formsForCert = grouped[certSel] || []
  const schema = SCHEMAS.find(s => s.form_key === formKey)

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
  if (!user && !demo) return <div className="wrap"><Login onDemo={() => setDemo(true)} /></div>

  return (
    <div className="wrap">
      <header className="topbar">
        <span className="brand"><span className="dot" /> VG · Certificaciones</span>
        <span className="spacer" />
        <SyncBadge status={status} />
        <button className="link" onClick={() => { if (user) supabase.auth.signOut(); setDemo(false) }}>Salir</button>
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
          <label>Finca (client_slug)<input value={slug} onChange={e => setSlug(e.target.value)} placeholder="ej. demo-cert" /></label>
          <label>Productor (producer_id)<input value={productor} onChange={e => setProductor(e.target.value)} placeholder="PRD-001" /></label>
          <label>Finca/Lote (finca_id)<input value={finca} onChange={e => setFinca(e.target.value)} placeholder="GY-001" /></label>
        </div>
        <p className="muted">El polígono se conecta del visor en producción; aquí el levantamiento es de piloto.</p>
      </div>

      <div className="card ctx">
        <h3>Certificación</h3>
        <div className="chips">
          {Object.keys(grouped).map(c => (
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
          <CertForm
            schema={schema}
            engine={engine}
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
      ) : <div className="card muted">Elige una certificación y un formulario para empezar a capturar.</div>}

      <footer className="foot muted">
        {SCHEMAS.length} formularios · {bundle.totales?.n_control_points || '—'} puntos de control · datos sellados con cadena de integridad. noindex.
      </footer>

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
