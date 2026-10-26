// Evidencias de la IFA del grupo, en solo lectura — para el auditor externo, la directiva y calidad (QMS, parte 3c).
// Encargo v2 de #15, punto 4 de la demo. Lee public.cert_qms_evidencias_ifa (solo respuestas de GlobalG.A.P.) y abre
// cada documento con un enlace firmado de una hora; la política del depósito solo deja leer los de esas respuestas.
import React, { useEffect, useState } from 'react'
import { Icono } from './eudr-react/CertForm.jsx'
import bundle from './schemas.bundle.json'

const FORMS = Object.fromEntries(bundle.schemas.filter(s => s.certificacion === 'GLOBAL_GAP').map(s => [s.form_key, s]))
const RESP = { cumple: ['Cumple', 'ok'], no_cumple: ['No cumple', 'err'], na: ['No aplica', 'off'] }
const NIVEL_CLS = { Major: 'err', Minor: 'warn', Recommendation: 'off' }
const FECHA = (s) => { if (!s) return '—'; try { return new Date(s).toLocaleString('es', { dateStyle: 'medium', timeStyle: 'short' }) } catch { return s } }

// Puntos de control de un formulario con su clave de datos (`<sección>.<punto>`, como la escribe CertForm).
function puntosDe(form) {
  return (form?.secciones || []).flatMap(sec => sec.campos.filter(c => c.tipo === 'control_point')
    .map(c => ({ k: `${sec.key}.${c.key}`, code: c.code || c.key, nivel: c.nivel, label: c.label, seccion: sec.titulo })))
}
const respuesta = (data, k) => (data || {})[k + '.estado'] ?? ((data || {})[k] && data[k].estado)

export function EvidenciasIfa({ slug, api }) {
  const [filas, setFilas] = useState(null)
  const [err, setErr] = useState('')
  const [abierta, setAbierta] = useState(null)   // id de la respuesta abierta
  const [filtro, setFiltro] = useState('todos')

  useEffect(() => { setFilas(null); api.evidenciasIfa(slug).then(setFilas).catch(e => { setFilas([]); setErr(String(e?.message || e)) }) }, [slug])

  // la última versión por finca y formulario; las anteriores se cuentan
  const grupos = {}
  for (const f of filas || []) {
    const g = (grupos[`${f.finca_id || 'sin finca'}|${f.form_key}`] ||= [])
    g.push(f)
  }
  const ultimas = Object.values(grupos).map(v => ({ ...v.sort((a, b) => b.created_at.localeCompare(a.created_at))[0], versiones: v.length }))
    .sort((a, b) => (a.finca_id || '').localeCompare(b.finca_id || '') || a.form_key.localeCompare(b.form_key))

  return (
    <div className="qms-form ai-crono">
      <p className="muted">Lo que cada finca del grupo respondió de la IFA de GlobalG.A.P., punto por punto, con sus documentos. Solo lectura:
        nadie edita una respuesta guardada; cada cambio queda como una versión nueva, sellada.</p>
      {err ? <div className="qms-msg err" role="alert">{err}</div> : null}
      {filas === null ? <p className="muted">Cargando…</p> : !ultimas.length ? (
        <p className="muted">Todavía no hay respuestas de GlobalG.A.P. guardadas en el servidor para este grupo.</p>
      ) : (
        <ul className="qms-lista">
          {ultimas.map(r => {
            const form = FORMS[r.form_key]; const ps = puntosDe(form)
            const cuenta = { cumple: 0, no_cumple: 0, na: 0, sin: 0 }
            ps.forEach(p => { const v = respuesta(r.data, p.k); cuenta[RESP[v] ? v : 'sin']++ })
            const docs = (r.fotos || []).length
            return (
              <li key={r.id} className="qms-socio">
                <div className="qms-socio-cab"><strong>{r.finca_id || 'Sin finca'}</strong><span className="qms-estado off">{r.estado || 'completado'}</span></div>
                <div className="muted">{form?.titulo || r.form_key} · {FECHA(r.created_at)}{r.versiones > 1 ? ` · ${r.versiones} versiones` : ''}</div>
                <div className="muted">Cumple {cuenta.cumple} · no cumple {cuenta.no_cumple} · no aplica {cuenta.na} · sin responder {cuenta.sin} · {docs} documento{docs === 1 ? '' : 's'}</div>
                {r.audit_hash ? <div className="muted ev-sello">Sello: {String(r.audit_hash).slice(0, 16)}…{r.audit_timestamp_seal ? ' · con sello de tiempo' : ''}</div> : null}
                <div className="qms-acciones">
                  <button className="link" onClick={() => setAbierta(abierta === r.id ? null : r.id)}><Icono n={abierta === r.id ? 'expand_more' : 'chevron_right'} />{abierta === r.id ? 'Ocultar' : 'Ver punto por punto'}</button>
                </div>
                {abierta === r.id ? <Detalle r={r} ps={ps} api={api} filtro={filtro} setFiltro={setFiltro} /> : null}
              </li>)
          })}
        </ul>
      )}
    </div>
  )
}

function Detalle({ r, ps, api, filtro, setFiltro }) {
  const [urls, setUrls] = useState({})
  const fotosDe = (k) => (r.fotos || []).filter(f => f.field === k + '__evidencia' || f.field === k)
  const visibles = ps.filter(p => { const v = respuesta(r.data, p.k); return filtro === 'todos' || (filtro === 'no_cumple' && v === 'no_cumple') || (filtro === 'con_doc' && fotosDe(p.k).length) })
  const abrir = async (f) => {
    const u = await api.evidenciaUrl(f).catch(() => null)
    setUrls(x => ({ ...x, [f.path || f.photo_id]: u || 'error' }))
    if (u) window.open(u, '_blank', 'noopener,noreferrer')
  }
  return (
    <div className="ev-detalle">
      <div className="chips">
        {[['todos', 'Todos'], ['no_cumple', 'No cumple'], ['con_doc', 'Con documento']].map(([k, t]) =>
          <button key={k} className={'chip ' + (filtro === k ? 'sel' : '')} onClick={() => setFiltro(k)}>{t}</button>)}
      </div>
      {!visibles.length ? <p className="muted">Ningún punto en esta vista.</p> : (
        <ul className="ev-puntos">
          {visibles.map(p => { const v = respuesta(r.data, p.k); const [l, c] = RESP[v] || ['Sin responder', 'warn']; const fs = fotosDe(p.k); return (
            <li key={p.k}>
              <div className="ai-punto-cab"><b>{p.code}</b><span className={'qms-estado ' + (NIVEL_CLS[p.nivel] || 'off')}>{p.nivel}</span><span className={'qms-estado ' + c}>{l}</span></div>
              <div className="muted">{p.label}</div>
              {fs.length ? <div className="qms-acciones">{fs.map((f, i) => (
                <button key={i} className="link" onClick={() => abrir(f)}><Icono n="description" />{f.name || `Documento ${i + 1}`}
                  {urls[f.path || f.photo_id] === 'error' ? ' (no se pudo abrir)' : ''}</button>))}</div> : null}
            </li>) })}
        </ul>
      )}
    </div>
  )
}
