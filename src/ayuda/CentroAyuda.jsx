// Centro de ayuda en video (R-AYUDA, 2-oct-2026): un video por flujo y por actor, DENTRO del producto.
// Lee ./ayuda.json (formato del kit vg-agriops/docs/ayuda-video/kit_video.py): flujos[].titulo · resumen · pasos ·
// video · portada · video_redes. El paso a paso escrito y el subtítulo del video salen del MISMO archivo de flujo.
// Los videos se sirven aparte (R-VIDEO, proyecto de Pages vg-cert-videos): el índice trae direcciones absolutas.
// Enlace directo a un flujo: /ayuda/#<id>.
import React, { useEffect, useMemo, useState } from 'react'

const url = a => a || undefined   // absolutas (vg-cert-videos.pages.dev) o relativas a /ayuda/

// Orden y nombre de cada actor, tal como existen en el código (App.jsx: ROLES / capsDeRol).
const ACTORES = [
  ['cuenta', 'Entrar y su cuenta'],
  ['productor', 'Productor o responsable de la finca (captura)'],
  ['lector', 'Solo lectura (auditor o consultor)']
]
const NOMBRE = Object.fromEntries(ACTORES)

export default function CentroAyuda() {
  const [datos, setDatos] = useState(null)
  const [error, setError] = useState('')
  const [q, setQ] = useState('')
  const [abierto, setAbierto] = useState(() => decodeURIComponent((window.location.hash || '').slice(1)))

  useEffect(() => {
    fetch('./ayuda.json', { cache: 'no-cache' })
      .then(r => { if (!r.ok) throw new Error('No se pudo cargar la ayuda (' + r.status + ').'); return r.json() })
      .then(setDatos)
      .catch(e => setError(e.message))
  }, [])

  // al cargar con #id, lleva el flujo a la vista
  useEffect(() => {
    if (!datos || !abierto) return
    const el = document.getElementById(abierto)
    if (el) setTimeout(() => el.scrollIntoView({ block: 'start' }), 50)
  }, [datos])

  useEffect(() => {
    const h = () => setAbierto(decodeURIComponent((window.location.hash || '').slice(1)))
    window.addEventListener('hashchange', h)
    return () => window.removeEventListener('hashchange', h)
  }, [])

  const flujos = useMemo(() => {
    const t = q.trim().toLowerCase()
    return (datos?.flujos || []).filter(f => !t ||
      [f.titulo, f.resumen, f.nota, ...(f.pasos || [])].join(' ').toLowerCase().includes(t))
  }, [datos, q])

  const grupos = useMemo(() => {
    const m = {}
    for (const f of flujos) (m[f.actor] = m[f.actor] || []).push(f)
    const orden = ACTORES.map(a => a[0])
    return Object.entries(m).sort((a, b) => (orden.indexOf(a[0]) + 99 * (orden.indexOf(a[0]) < 0)) - (orden.indexOf(b[0]) + 99 * (orden.indexOf(b[0]) < 0)))
  }, [flujos])

  const total = datos?.flujos?.length || 0
  const conVideo = (datos?.flujos || []).filter(f => f.video).length

  function abrir(id) {
    setAbierto(id)
    try { history.replaceState(null, '', '#' + id) } catch { /* sin historial */ }
  }

  return (
    <div className="wrap ayuda">
      <header className="topbar">
        <span className="brand"><span className="dot" /> VG · Certificaciones</span>
        <span className="spacer" />
        <a className="link" href="../">← Volver a la app</a>
      </header>

      <div className="card ayuda-cabeza">
        <div className="eyebrow">Ayuda en video</div>
        <h1>¿Cómo se hace en Certificaciones?</h1>
        <p className="muted">
          Cada tarea de la preparación para la auditoría, en un video corto y en un paso a paso escrito.
          Los videos se grabaron sobre el modo demostración, con datos de ejemplo.
        </p>
        <p className="muted" style={{ margin: 0 }}>
          <a href="../?demo=1">Probar la demostración</a> · <a href="../">Entrar a la app</a>
          {total ? <> · {total} temas, {conVideo} con video</> : null}
        </p>
        <input className="ayuda-buscar" type="search" placeholder="Buscar en la ayuda (por ejemplo: evidencia, sin conexión)"
          value={q} onChange={e => setQ(e.target.value)} aria-label="Buscar en la ayuda" />
      </div>

      {error ? <div className="card err">{error}</div> : null}
      {!datos && !error ? <div className="card muted">Cargando la ayuda…</div> : null}
      {datos && !flujos.length ? <div className="card muted">No hay temas que coincidan con «{q}».</div> : null}

      {grupos.map(([actor, lista]) => (
        <section key={actor} className="ayuda-grupo">
          <h2>{NOMBRE[actor] || actor}</h2>
          {lista.map(f => (
            <details key={f.id} id={f.id} className="card ayuda-item" open={abierto === f.id}
              onToggle={e => { if (e.currentTarget.open) abrir(f.id) }}>
              <summary>
                <span className="ayuda-titulo">{f.titulo}</span>
                {f.video
                  ? <span className="ayuda-chip">{f.segundos ? Math.round(f.segundos) + ' s' : 'video'}</span>
                  : <span className="ayuda-chip pend">video en preparación</span>}
              </summary>
              {f.resumen ? <p className="muted">{f.resumen}</p> : null}
              <div className="ayuda-flujo">
                {f.video ? (
                  <video controls preload="none" playsInline poster={url(f.portada)} src={url(f.video)} />
                ) : null}
                <div>
                  <ol className="ayuda-pasos">{(f.pasos || []).map((p, i) => <li key={i}>{p}</li>)}</ol>
                  {f.nota ? <p className="muted ayuda-nota">{f.nota}</p> : null}
                  <p className="ayuda-acciones">
                    {f.probar ? <a href={f.probar}>Probarlo →</a> : null}
                    <a href={'#' + f.id} onClick={e => { e.preventDefault(); abrir(f.id); try { navigator.clipboard.writeText(location.href.split('#')[0] + '#' + f.id) } catch {} }}>
                      Copiar enlace a este tema
                    </a>
                    {f.video_redes ? <a href={f.video_redes} target="_blank" rel="noopener">Versión para redes</a> : null}
                  </p>
                </div>
              </div>
            </details>
          ))}
        </section>
      ))}

      <footer className="foot muted">
        Visión Geográfica · Certificaciones. La app ayuda a preparar la auditoría; la decisión de certificar es del organismo de certificación.
      </footer>
    </div>
  )
}
