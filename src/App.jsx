import React, { useEffect, useMemo, useState } from 'react'
import { CertForm, useCertCapture, readFormFromContainer, progresoDe } from './eudr-react/index.js'
import { buildCertReadyPreviewHtml } from './eudr-react/capture/export-policy.js'
import { engine, setCaptureSession, db } from './engine.js'
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
  const [productor, setProductor] = useState(() => localStorage.getItem('vg_prod') || '')
  const [finca, setFinca] = useState(() => localStorage.getItem('vg_finca') || '')
  const [certSel, setCertSel] = useState('EUDR')
  const [formKey, setFormKey] = useState('')
  const [preview, setPreview] = useState(null)
  const [tablero, setTablero] = useState(false)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => { setUser(data.session?.user || null); setReady(true) })
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setUser(s?.user || null))
    return () => sub.subscription.unsubscribe()
  }, [])

  useEffect(() => { setCaptureSession({ slug, email: effEmail }); localStorage.setItem('vg_slug', slug) }, [slug, effEmail])

  // Carga el producto EUDR del usuario vía la RPC canónica public.my_products() (#03): misma fuente que
  // /api/identity/me, respeta expiración y es RLS-safe (no expone otros usuarios). De ahí salen sus fincas
  // (client_slugs, las mismas del visor/ERP) y los module_flags (estado C: lock por módulo). Materializa la
  // relación cross-product: el encuestador no es una isla, comparte la finca y la cuenta del resto.
  useEffect(() => {
    if (!user) { setMisFincas([]); setAccesoEudr(null); setModuleFlags([]); return }
    supabase.rpc('my_products')
      .then(({ data }) => {
        const eudr = (data || []).find(p => p.product === 'eudr')
        if (!eudr) { setMisFincas([]); setAccesoEudr(false); setModuleFlags([]); return }
        setMisFincas([...new Set(eudr.client_slugs || [])].sort())
        setModuleFlags(eudr.module_flags || [])
        setAccesoEudr(true)
      }).catch(() => { setMisFincas([]); setAccesoEudr(false); setModuleFlags([]) })
  }, [user])
  useEffect(() => { localStorage.setItem('vg_prod', productor) }, [productor])
  useEffect(() => { localStorage.setItem('vg_finca', finca) }, [finca])

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
  if (!user && !demo) return <div className="wrap"><Login onDemo={() => setDemo(true)} /></div>
  if (user && accesoEudr === false) return <SinAcceso email={user.email} onSalir={() => supabase.auth.signOut()} />

  return (
    <div className="wrap">
      <header className="topbar">
        <span className="brand"><span className="dot" /> VG · Certificaciones</span>
        <span className="spacer" />
        <button className="link" onClick={() => setTablero(true)}>📊 Mi progreso</button>
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
