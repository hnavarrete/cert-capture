import React, { useEffect, useMemo, useState } from 'react'
import { CertForm, useCertCapture } from './eudr-react/index.js'
import { engine, setCaptureSession } from './engine.js'
import { supabase } from './supabase.js'
import bundle from './schemas.bundle.json'

const SCHEMAS = (bundle.schemas || []).filter(s => !s.legacy)
const CERTS = bundle.certificaciones || []
const CERT_LABEL = Object.fromEntries(CERTS.map(c => [c.key, c.titulo]))

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
      {offline ? '◌ sin conexión' : '● en línea'} · pendientes {pending} · fallidas {failed} · sincronizadas {synced}
    </div>
  )
}

function Login() {
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
    </form>
  )
}

export default function App() {
  const [user, setUser] = useState(null)
  const [ready, setReady] = useState(false)
  const { status } = useCertCapture(engine)

  // contexto piloto (en producción viene del tenant + visor)
  const [slug, setSlug] = useState(() => localStorage.getItem('vg_slug') || '')
  const [productor, setProductor] = useState(() => localStorage.getItem('vg_prod') || '')
  const [finca, setFinca] = useState(() => localStorage.getItem('vg_finca') || '')
  const [certSel, setCertSel] = useState('EUDR')
  const [formKey, setFormKey] = useState('')

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => { setUser(data.session?.user || null); setReady(true) })
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setUser(s?.user || null))
    return () => sub.subscription.unsubscribe()
  }, [])

  useEffect(() => { setCaptureSession({ slug, email: user?.email || null }); localStorage.setItem('vg_slug', slug) }, [slug, user])
  useEffect(() => { localStorage.setItem('vg_prod', productor) }, [productor])
  useEffect(() => { localStorage.setItem('vg_finca', finca) }, [finca])

  const grouped = useMemo(() => groupByCert(SCHEMAS), [])
  const formsForCert = grouped[certSel] || []
  const schema = SCHEMAS.find(s => s.form_key === formKey)

  if (!ready) return <div className="wrap"><div className="card">Cargando…</div></div>
  if (!user) return <div className="wrap"><Login /></div>

  return (
    <div className="wrap">
      <header className="topbar">
        <strong>VG · Certificaciones</strong>
        <SyncBadge status={status} />
        <button className="link" onClick={() => supabase.auth.signOut()}>Salir ({user.email})</button>
      </header>

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
              onClick={() => { setCertSel(c); setFormKey('') }}>{CERT_LABEL[c] || c}</button>
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
            onConnectPolygon={() => alert('En producción: se abre el visor y se conecta el polígono existente de la finca (no se recaptura).')}
            onSaved={(res) => { /* el badge refleja el estado; el sync es automático */ }}
          />
        </div>
      ) : <div className="card muted">Elige una certificación y un formulario para empezar a capturar.</div>}

      <footer className="foot muted">
        {SCHEMAS.length} formularios · {bundle.totales?.n_control_points || '—'} puntos de control · datos sellados con cadena de integridad. noindex.
      </footer>
    </div>
  )
}
