// Hoja de ruta de una certificación — pantalla "antes de iniciar el llenado".
// Agrupa los formularios por los 4 pilares universales, muestra tiempos estimados,
// el estado de cada tramo y el reuso del núcleo ("captura una vez, certifica
// muchas veces"). Alimentada por bundle.rutas[cert] (motor _roadmap.js) + el
// progreso guardado en IndexedDB. Iconografía sobria, sin emojis decorativos.
import React from 'react'

const COLOR_PILAR = {
  LEGAL_GOBERNANZA: '#1BABE1',
  AMBIENTAL: '#15803d',
  SOCIAL_LABORAL: '#7c3aed',
  GESTION_MEJORA: '#f59e0b'
}

function fmtMin(m) { return m >= 60 ? `${Math.floor(m / 60)} h ${m % 60} min` : `${m} min` }

function estadoTramo(est) {
  if (!est || !est.pct) return { txt: 'sin empezar', col: 'var(--muted)', pct: 0 }
  if (est.vendible || est.pct >= 100) return { txt: 'listo para auditoría', col: 'var(--ok-ink)', pct: 100 }
  return { txt: `en progreso · ${est.pct}%`, col: 'var(--forest)', pct: est.pct }
}

export default function RoadmapCert({ cert, ruta, forms, estadoPorForm, onPick }) {
  // Fallback: cert sin ruta precomputada (GENERAL, contratante) → lista simple.
  if (!ruta) {
    return (
      <div className="card">
        <h3>Formularios</h3>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {(forms || []).map(s => (
            <button key={s.form_key} className="chip" style={{ justifyContent: 'flex-start' }} onClick={() => onPick(s.form_key)}>
              {s.titulo}
            </button>
          ))}
        </div>
      </div>
    )
  }

  const est = estadoPorForm || {}
  // Avance global: campos hechos / total, ponderado por progreso de cada tramo.
  let pctGlobal = 0, nConProg = 0
  for (const p of ruta.pilares) for (const t of p.tramos) { const e = est[t.form_key]; if (e) { pctGlobal += (e.vendible ? 100 : e.pct || 0); nConProg++ } }
  pctGlobal = ruta.nTramos ? Math.round(pctGlobal / ruta.nTramos) : 0

  // ¿algo del núcleo ya avanzado? → ventaja inicial real.
  const coreHecho = ruta.pilares.flatMap(p => p.tramos).filter(t => t.esCore && est[t.form_key]?.pct)
  const minRestante = Math.max(0, ruta.totalMin - Math.round(ruta.totalMin * pctGlobal / 100))
  const alimentaMax = Math.max(0, ...ruta.pilares.flatMap(p => p.tramos).map(t => (t.alimenta || []).length))

  return (
    <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '16px 18px', borderBottom: '1px solid var(--line)' }}>
        <Ring pct={pctGlobal} />
        <div>
          <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '.8px', textTransform: 'uppercase', color: 'var(--blue)' }}>Hoja de ruta · antes de empezar</div>
          <div style={{ fontSize: 17, fontWeight: 700, color: 'var(--navy)' }}>{cert}</div>
          <div className="muted" style={{ margin: 0 }}>{ruta.pilares.length} pilares · {ruta.nTramos} tramos · {ruta.totalPreguntas} preguntas · ~{fmtMin(ruta.totalMin)}</div>
        </div>
      </div>

      <div style={{ margin: '14px 18px', padding: '12px 14px', background: 'var(--ok-bg)', borderRadius: 12, display: 'flex', gap: 10 }}>
        <span style={{ width: 8, borderRadius: 4, background: 'var(--ok)', flexShrink: 0 }} />
        <div style={{ fontSize: 13, color: 'var(--ok-ink)', lineHeight: 1.5 }}>
          {coreHecho.length
            ? <><strong>Ventaja inicial:</strong> ya capturaste {coreHecho.length} {coreHecho.length === 1 ? 'tramo' : 'tramos'} del núcleo compartido — cuentan aquí sin volver a llenarlos.</>
            : <><strong>Captura una vez, certifica muchas veces.</strong> El núcleo compartido se llena una sola vez y alimenta hasta {alimentaMax} certificaciones.</>}
        </div>
      </div>

      <div style={{ padding: '0 18px' }}>
        {ruta.pilares.map(p => (
          <div key={p.pilar} style={{ borderTop: '1px solid var(--line)', padding: '12px 0' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
              <span style={{ width: 10, height: 10, borderRadius: 3, background: COLOR_PILAR[p.pilar] || 'var(--muted)' }} />
              <span style={{ fontSize: 14, fontWeight: 700, color: 'var(--navy)' }}>{p.titulo}</span>
              <span className="muted" style={{ margin: 0, marginLeft: 'auto' }}>{p.tramos.length} {p.tramos.length === 1 ? 'tramo' : 'tramos'} · ~{fmtMin(p.min)}</span>
            </div>
            {p.tramos.map(t => {
              const s = estadoTramo(est[t.form_key])
              return (
                <button key={t.form_key} onClick={() => onPick(t.form_key)} style={{ width: '100%', textAlign: 'left', background: '#fcfdfe', border: '1px solid var(--line)', borderRadius: 11, padding: '10px 12px', margin: '0 0 8px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 10 }}>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontSize: 13.5, fontWeight: 600, color: 'var(--ink)' }}>{t.titulo}</div>
                    <div style={{ fontSize: 12, color: 'var(--muted)', marginTop: 2 }}>
                      ~{fmtMin(t.min)} · {t.nPreguntas} preguntas
                      {t.esCore ? <span style={{ color: 'var(--blue)', fontWeight: 600 }}> · núcleo{t.alimenta?.length ? ` → ${t.alimenta.length} certs` : ''}</span> : null}
                    </div>
                    {s.pct > 0 && s.pct < 100 ? <div style={{ height: 4, borderRadius: 2, background: 'var(--line)', marginTop: 6, overflow: 'hidden' }}><div style={{ width: `${s.pct}%`, height: '100%', background: 'var(--forest)' }} /></div> : null}
                  </div>
                  <span style={{ fontSize: 11, color: s.col, fontWeight: 600, whiteSpace: 'nowrap' }}>{s.txt}</span>
                </button>
              )
            })}
          </div>
        ))}
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: 10, padding: 18, borderTop: '1px solid var(--line)' }}>
        <Metric label="Tiempo restante" value={`~${fmtMin(minRestante)}`} />
        <Metric label="En varias pasadas" value={`${ruta.nTramos} tramos`} />
        <Metric label="Núcleo alimenta" value={`${alimentaMax} certs`} />
      </div>

      <div className="muted" style={{ padding: '0 18px 16px', margin: 0 }}>
        Se guarda solo. Puedes salir y retomar donde quedaste, sin conexión.
      </div>
    </div>
  )
}

function Metric({ label, value }) {
  return (
    <div style={{ background: 'var(--bg)', borderRadius: 11, padding: '10px 12px' }}>
      <div style={{ fontSize: 12, color: 'var(--muted)' }}>{label}</div>
      <div style={{ fontSize: 18, fontWeight: 700, color: 'var(--navy)', marginTop: 2 }}>{value}</div>
    </div>
  )
}

function Ring({ pct }) {
  const r = 15.5, c = 2 * Math.PI * r, off = c * (1 - (pct || 0) / 100)
  return (
    <div style={{ position: 'relative', width: 56, height: 56, flexShrink: 0 }}>
      <svg viewBox="0 0 36 36" style={{ width: 56, height: 56, transform: 'rotate(-90deg)' }}>
        <circle cx="18" cy="18" r={r} fill="none" stroke="var(--line)" strokeWidth="3" />
        <circle cx="18" cy="18" r={r} fill="none" stroke="var(--forest)" strokeWidth="3" strokeDasharray={c} strokeDashoffset={off} strokeLinecap="round" />
      </svg>
      <span style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 13, fontWeight: 700, color: 'var(--navy)' }}>{pct || 0}%</span>
    </div>
  )
}
