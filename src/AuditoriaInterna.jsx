// Auditoría interna de finca — GlobalG.A.P. opción 2 (QMS v6.0, 05.02), parte 2. Encargo v2 de #15 (pitahaya).
//   · CronogramaGrupo: la directiva o calidad planifica y asigna (05.02 a, d, j), lee cada informe y decide (05.02 h, i).
//     El auditor externo lo ve en solo lectura.
//   · MisAuditorias: el auditor interno descarga lo asignado CON señal y hace la auditoría en la finca SIN señal; todo se
//     guarda en el equipo (IndexedDB) a cada toque, se firma en la pantalla y se envía solo cuando vuelve la señal.
//   · Informe: el informe con todo lo que pide 05.02 g, para leer o imprimir.
// El servidor (funciones cert_qms_* de 20261025000000) recalcula y decide; aquí solo se avisa antes de enviar.
import React, { useEffect, useMemo, useRef, useState } from 'react'
import { Icono } from './eudr-react/CertForm.jsx'
import {
  PUNTOS, SECCIONES, FUENTE, RESULTADOS, pideComentario, pidePlazo, faltantes, calcular, almacen, descargar, enviarPendientes, nivelDe
} from './qms-auditoria.js'

const local = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
const hoy = () => local(new Date())
const FECHA = (s) => { if (!s) return '—'; try { return new Date(s.length === 10 ? s + 'T12:00:00' : s).toLocaleDateString('es', { dateStyle: 'medium' }) } catch { return s } }
const HORA = (s) => { if (!s) return '—'; try { return new Date(s).toLocaleTimeString('es', { hour: '2-digit', minute: '2-digit' }) } catch { return s } }
const DURACION = (a, b) => { if (!a || !b) return '—'; const m = Math.round((new Date(b) - new Date(a)) / 60000); return m >= 60 ? `${Math.floor(m / 60)} h ${m % 60} min` : `${m} min` }
const PCT = (n) => (n == null ? '—' : String(n).replace('.', ',') + ' %')
const enLinea = () => (typeof navigator === 'undefined' ? true : navigator.onLine !== false)

const ESTADO_INSP = {
  planificada: ['Planificada', 'warn'],
  enviada: ['Por decidir', 'warn'],
  conforme: ['Conforme', 'ok'],
  no_conforme: ['No conforme', 'err'],
  cancelada: ['Cancelada', 'off']
}
const estadoDe = (i) => ESTADO_INSP[i.estado === 'decidida' ? i.decision : i.estado] || [i.estado, 'off']
const NIVEL_CLS = { Major: 'err', Minor: 'warn', Recommendation: 'off' }
// Vigencia: GlobalG.A.P. pide una auditoría interna por socio y por año (05.02 a).
const vencida = (m) => !m.ultima_auditoria_interna || (new Date() - new Date(m.ultima_auditoria_interna + 'T12:00:00')) / 864e5 > 365

// ═════════ cronograma del grupo ═════════
export function CronogramaGrupo({ slug, gestiona, api, socios, email, onSocios, onOk, onError }) {
  const [lista, setLista] = useState(null)
  const [plan, setPlan] = useState(null)        // { miembro, fecha, inspector }
  const [cancelar, setCancelar] = useState(null) // { i, motivo }
  const [informe, setInforme] = useState(null)

  const cargar = () => { setLista(null); api.cronograma(slug).then(setLista).catch(e => { setLista([]); onError(e) }) }
  useEffect(cargar, [slug])

  const abiertas = new Set((lista || []).filter(i => i.estado === 'planificada').map(i => i.miembro_id))
  const auditables = socios.filter(m => m.estado === 'activo' || m.estado === 'aspirante')
  const pendientes = auditables.filter(m => vencida(m) && !abiertas.has(m.id))
  const n = (f) => (lista || []).filter(f).length

  const abrirInforme = (i) => api.informe(i.id).then(setInforme).catch(onError)

  return (
    <div className="qms-form ai-crono">
      <div className="qms-metricas">
        <div><b>{auditables.length - auditables.filter(vencida).length}</b><span>con auditoría vigente</span></div>
        <div><b>{pendientes.length}</b><span>sin auditoría ni plan</span></div>
        <div><b>{n(i => i.estado === 'planificada')}</b><span>planificadas</span></div>
        <div><b>{n(i => i.estado === 'enviada')}</b><span>por decidir</span></div>
        <div><b>{n(i => i.estado === 'decidida' && i.decision === 'no_conforme')}</b><span>no conformes</span></div>
      </div>
      <p className="muted">Cada socio activo o aspirante necesita una auditoría interna al año (QMS 05.02 a). Un aspirante se audita y se aprueba antes de
        activarlo (05.02 e). El auditor interno no audita su propio trabajo diario (05.02 d), y quien hizo la auditoría no la aprueba (12.5 a).</p>

      {gestiona ? (
        <div className="qms-barra">
          <button className="primary" onClick={() => setPlan({ miembro: pendientes[0]?.id || auditables[0]?.id || '', fecha: hoy(), inspector: '' })}>
            <Icono n="event" />Planificar auditoría</button>
        </div>
      ) : null}

      {pendientes.length ? (
        <>
          <h4>Sin auditoría vigente ni planificada ({pendientes.length})</h4>
          <ul className="qms-lista">
            {pendientes.map(m => (
              <li key={m.id} className="qms-socio">
                <div className="qms-socio-cab"><strong>{m.nombre}</strong><span className="qms-estado err">{m.ultima_auditoria_interna ? 'Vencida' : 'Nunca auditado'}</span></div>
                <div className="muted">{m.estado === 'aspirante' ? 'Aspirante' : 'Activo'} · última auditoría interna: {FECHA(m.ultima_auditoria_interna)}</div>
                {gestiona ? <div className="qms-acciones"><button className="link" onClick={() => setPlan({ miembro: m.id, fecha: hoy(), inspector: '' })}><Icono n="event" />Planificar</button></div> : null}
              </li>
            ))}
          </ul>
        </>
      ) : null}

      <h4>Cronograma e informes</h4>
      {lista === null ? <p className="muted">Cargando…</p> : !lista.length ? <p className="muted">Todavía no hay auditorías internas planificadas.</p> : (
        <ul className="qms-lista">
          {lista.map(i => { const [l, c] = estadoDe(i); return (
            <li key={i.id} className="qms-socio">
              <div className="qms-socio-cab"><strong>{i.socio_nombre}</strong><span className={'qms-estado ' + c}>{l}</span></div>
              <div className="muted">{i.inicio ? `Hecha el ${FECHA(i.inicio)}` : `Planificada para el ${FECHA(i.fecha_plan)}`} · auditor interno: {i.inspector_correo}</div>
              {i.cumplimiento ? <div className="muted">Major {PCT(i.cumplimiento.pct_major)} · Minor {PCT(i.cumplimiento.pct_minor)} · {i.cumplimiento.cumple ? 'el cálculo cumple' : 'el cálculo no cumple'}</div> : null}
              {i.estado === 'cancelada' ? <div className="qms-motivo">Cancelada: {i.cancelada_motivo}</div> : null}
              {i.decidida_por_nombre ? <div className="muted">Aprobó: {i.decidida_por_nombre} · {FECHA(i.decidida_en)}</div> : null}
              <div className="qms-acciones">
                {i.inicio ? <button className="link" onClick={() => abrirInforme(i)}><Icono n="description" />{gestiona && i.estado === 'enviada' ? 'Ver informe y decidir' : 'Ver informe'}</button> : null}
                {gestiona && i.estado === 'planificada' ? <button className="link" onClick={() => setCancelar({ i, motivo: '' })}><Icono n="close" />Cancelar</button> : null}
              </div>
            </li>) })}
        </ul>
      )}

      {plan ? (
        <div className="overlay" onClick={() => setPlan(null)}>
          <div className="sheet qms-mini" onClick={e => e.stopPropagation()} role="dialog" aria-labelledby="ai-plan-t">
            <div className="sheet-head"><strong id="ai-plan-t">Planificar auditoría interna</strong>
              <button className="link" onClick={() => setPlan(null)}>Cerrar <Icono n="close" /></button></div>
            <div className="qms-form">
              <label>Socio
                <select id="ai-plan-socio" value={plan.miembro} onChange={e => setPlan({ ...plan, miembro: e.target.value })}>
                  {auditables.map(m => <option key={m.id} value={m.id} disabled={abiertas.has(m.id)}>{m.nombre}{abiertas.has(m.id) ? ' (ya planificada)' : ''}</option>)}
                </select>
              </label>
              <label>Fecha<input id="ai-plan-fecha" type="date" value={plan.fecha} onChange={e => setPlan({ ...plan, fecha: e.target.value })} /></label>
              <label>Correo del auditor interno
                <input id="ai-plan-insp" type="email" value={plan.inspector} onChange={e => setPlan({ ...plan, inspector: e.target.value })} maxLength={200} placeholder="la cuenta con la que entra a Certificaciones" />
              </label>
              <p className="muted">La auditoría le aparece en «Mis auditorías» a esa cuenta, que debe tener acceso al grupo. La descarga con señal y la hace en la finca sin señal.</p>
              <button className="primary" disabled={!plan.miembro || !plan.fecha || !plan.inspector.trim()}
                onClick={() => api.planificar(slug, plan.miembro, plan.fecha, plan.inspector.trim())
                  .then(() => { setPlan(null); cargar(); onOk('Auditoría planificada.') }).catch(onError)}>Planificar</button>
            </div>
          </div>
        </div>
      ) : null}

      {cancelar ? (
        <div className="overlay" onClick={() => setCancelar(null)}>
          <div className="sheet qms-mini" onClick={e => e.stopPropagation()} role="dialog" aria-labelledby="ai-canc-t">
            <div className="sheet-head"><strong id="ai-canc-t">Cancelar: {cancelar.i.socio_nombre}</strong>
              <button className="link" onClick={() => setCancelar(null)}>Cerrar <Icono n="close" /></button></div>
            <div className="qms-form">
              <label>Motivo (obligatorio)<textarea id="ai-canc-motivo" rows={3} maxLength={500} value={cancelar.motivo} onChange={e => setCancelar({ ...cancelar, motivo: e.target.value })} /></label>
              <button className="primary" disabled={!cancelar.motivo.trim()} onClick={() => api.cancelar(cancelar.i.id, cancelar.motivo)
                .then(() => { setCancelar(null); cargar(); onOk('Auditoría cancelada.') }).catch(onError)}>Cancelar la auditoría</button>
            </div>
          </div>
        </div>
      ) : null}

      {informe ? <Informe informe={informe} slug={slug} api={api} puedeDecidir={gestiona && informe.estado === 'enviada'}
        propia={!!email && (informe.inspector_correo || '').toLowerCase() === email.toLowerCase()}
        onCerrar={() => setInforme(null)} onDecidido={() => { setInforme(null); cargar(); onSocios(); onOk('Decisión guardada. La fecha quedó en el registro del socio.') }} onError={onError} /> : null}
    </div>
  )
}

// ═════════ el informe (05.02 g) ═════════
export function Informe({ informe: i, slug, api, puedeDecidir, propia, onCerrar, onDecidido, onError }) {
  const [d, setD] = useState({ decision: i.cumplimiento?.cumple ? 'conforme' : 'no_conforme', nombre: '', comentario: '' })
  const res = Array.isArray(i.resultados) ? i.resultados : []
  const ncs = res.filter(x => x.resultado === 'no_cumple')
  // un <details> cerrado no se imprime: se abren antes (R-PDF: lo impreso va desplegado)
  const imprimir = () => { document.querySelectorAll('.ai-informe details').forEach(x => { x.open = true }); document.body.classList.add('ai-imprimiendo'); window.print(); setTimeout(() => document.body.classList.remove('ai-imprimiendo'), 500) }
  const c = i.cumplimiento || {}
  const [l, cls] = estadoDe(i)
  return (
    <div className="overlay" onClick={onCerrar}>
      <div className="sheet qms-sheet" onClick={e => e.stopPropagation()} role="dialog" aria-labelledby="ai-inf-t">
        <div className="sheet-head"><strong id="ai-inf-t"><Icono n="description" /> Informe de auditoría interna</strong>
          <span className="ai-cab-acc"><button className="link" onClick={imprimir}><Icono n="print" />Imprimir</button>
            <button className="link" onClick={onCerrar}>Cerrar <Icono n="close" /></button></span></div>
        <div className="qms-cuerpo ai-informe">
          <div className="ai-inf-titulo">
            <div><h3>Auditoría interna de finca</h3><div className="muted">GlobalG.A.P. opción 2 · {FUENTE}</div></div>
            <span className={'qms-estado ' + cls}>{l}</span>
          </div>
          <dl className="ai-datos">
            <dt>Grupo</dt><dd>{i.client_slug || slug}</dd>
            <dt>Socio (i)</dt><dd>{i.socio_nombre} · {i.socio_identificacion}</dd>
            <dt>Sitios (i)</dt><dd>{(i.sitios || []).map(s => `${s.nombre} ${s.area_ha} ha${s.certificado ? ' (certificado)' : ''}`).join(' · ') || '—'}</dd>
            <dt>Productos registrados (v)</dt><dd>{(i.productos || []).map(p => `${p.cultivo} ${p.area_ha} ha`).join(' · ') || '—'}</dd>
            <dt>Fecha (iii)</dt><dd>{FECHA(i.inicio)}</dd>
            <dt>Inicio y fin (x)</dt><dd>{HORA(i.inicio)} – {HORA(i.fin)} · {DURACION(i.inicio, i.fin)}</dd>
            <dt>Auditor interno (iv)</dt><dd>{i.inspector_nombre} · {i.inspector_correo}</dd>
          </dl>

          <h4>Resultado con el cálculo de cumplimiento (ix)</h4>
          <div className="ai-calc">
            <div><b>{PCT(c.pct_major)}</b><span>Major ({c.major_aplicables - c.major_no_cumple} de {c.major_aplicables}) · se exige 100 %</span></div>
            <div><b>{PCT(c.pct_minor)}</b><span>Minor ({c.minor_aplicables - c.minor_no_cumple} de {c.minor_aplicables}) · se exige 95 %</span></div>
            <div><b>{c.no_aplica ?? 0}</b><span>puntos no aplican</span></div>
            <div><b className={c.cumple ? 'ai-ok' : 'ai-mal'}>{c.cumple ? 'Cumple' : 'No cumple'}</b><span>según el cálculo</span></div>
          </div>

          <h4>Incumplimientos y plazo de la acción correctiva (viii) · {ncs.length}</h4>
          {!ncs.length ? <p className="muted">Ninguno.</p> : (
            <ul className="ai-ncs">{ncs.map(x => { const p = PUNTOS.find(q => q.code === x.code) || {}; return (
              <li key={x.code}><b>{x.code}</b> <span className={'qms-estado ' + NIVEL_CLS[p.nivel]}>{p.nivel}</span> {p.label}
                <div className="muted">{x.comentario} · plazo: <b>{FECHA(x.plazo)}</b></div></li>) })}</ul>
          )}

          <details className="ai-todos">
            <summary>Resultado de cada uno de los {res.length} puntos, con sus comentarios (vi, vii)</summary>
            <div className="ai-tabla-wrap"><table className="ai-tabla">
              <thead><tr><th>Punto</th><th>Nivel</th><th>Resultado</th><th>Comentario</th></tr></thead>
              <tbody>{res.map(x => (
                <tr key={x.code} className={x.resultado}><td>{x.code}</td><td>{nivelDe(x.code)}</td><td>{RESULTADOS[x.resultado]}</td><td>{x.comentario || ''}{x.plazo ? ` · plazo ${FECHA(x.plazo)}` : ''}</td></tr>
              ))}</tbody>
            </table></div>
          </details>

          <h4>Firmas (ii, iv)</h4>
          <div className="ai-firmas">
            <figure>{i.firma_socio ? <img src={i.firma_socio} alt={'Firma de ' + i.firmante_nombre} /> : null}<figcaption>{i.firmante_nombre}<br /><span className="muted">por el socio o el responsable del sitio</span></figcaption></figure>
            <figure>{i.firma_inspector ? <img src={i.firma_inspector} alt={'Firma de ' + i.inspector_nombre} /> : null}<figcaption>{i.inspector_nombre}<br /><span className="muted">auditor interno</span></figcaption></figure>
          </div>

          <h4>Aprobación (xi)</h4>
          {i.estado === 'decidida' ? (
            <p><b>{i.decision === 'conforme' ? 'Conforme' : 'No conforme'}</b> · aprobó <b>{i.decidida_por_nombre}</b> el {FECHA(i.decidida_en)}
              {i.decision_comentario ? <><br /><span className="muted">{i.decision_comentario}</span></> : null}</p>
          ) : puedeDecidir && propia ? (
            <div className="rol-aviso lectura"><Icono n="info" />Usted hizo esta auditoría: la aprueba otra persona de calidad o el responsable del QMS (QMS 12.5 a).</div>
          ) : puedeDecidir ? (
            <div className="qms-form ai-decidir">
              <div className="ai-radios" role="radiogroup" aria-label="Decisión">
                <label className="qms-check"><input type="radio" name="ai-dec" checked={d.decision === 'conforme'} disabled={!c.cumple}
                  onChange={() => setD({ ...d, decision: 'conforme' })} />Conforme: el socio cumple</label>
                <label className="qms-check"><input type="radio" name="ai-dec" checked={d.decision === 'no_conforme'}
                  onChange={() => setD({ ...d, decision: 'no_conforme' })} />No conforme</label>
              </div>
              {!c.cumple ? <p className="muted">«Conforme» no se puede elegir: el cálculo no cumple (Major 100 % y Minor 95 %). Cuando se corrijan los incumplimientos, se planifica otra auditoría.</p> : null}
              <label>Su nombre (queda en el informe)<input id="ai-dec-nombre" value={d.nombre} onChange={e => setD({ ...d, nombre: e.target.value })} maxLength={200} /></label>
              <label>Comentario {d.decision === 'no_conforme' ? '(obligatorio)' : '(opcional)'}
                <textarea id="ai-dec-com" rows={3} maxLength={1000} value={d.comentario} onChange={e => setD({ ...d, comentario: e.target.value })} /></label>
              <button className="primary" disabled={!d.nombre.trim() || (d.decision === 'no_conforme' && !d.comentario.trim())}
                onClick={() => api.decidir(i.id, d.decision, d.nombre.trim(), d.comentario).then(onDecidido).catch(onError)}>Guardar la decisión</button>
            </div>
          ) : <p className="muted">Pendiente: la decide la directiva o el responsable de calidad del grupo.</p>}
        </div>
      </div>
    </div>
  )
}

// ═════════ firma en la pantalla ═════════
function FirmaPad({ id, valor, onCambio }) {
  const ref = useRef(null)
  const dibujando = useRef(false)
  // El lienzo toma la resolución de su tamaño EN PANTALLA (x2 para que el trazo no salga borroso). Si cambió desde que
  // se montó (la hoja todavía se abría, o se giró el teléfono), se vuelve a preparar, con la firma que ya hubiera.
  const preparar = (img) => {
    const cv = ref.current; const r = cv.getBoundingClientRect()
    if (cv.width === Math.round(r.width * 2) && cv.height === Math.round(r.height * 2)) return
    cv.width = Math.round(r.width * 2); cv.height = Math.round(r.height * 2)
    const g = cv.getContext('2d'); g.setTransform(2, 0, 0, 2, 0, 0); g.lineWidth = 2.2; g.lineCap = 'round'; g.lineJoin = 'round'; g.strokeStyle = '#0A1128'
    if (img) { const im = new Image(); im.onload = () => g.drawImage(im, 0, 0, r.width, r.height); im.src = img }
  }
  useEffect(() => { preparar(valor) }, [])
  const pos = (e) => { const r = ref.current.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top] }
  const abajo = (e) => {
    e.preventDefault(); preparar(valor); ref.current.setPointerCapture(e.pointerId); dibujando.current = true
    const g = ref.current.getContext('2d'); g.beginPath(); g.moveTo(...pos(e))
  }
  const mueve = (e) => { if (!dibujando.current) return; const g = ref.current.getContext('2d'); g.lineTo(...pos(e)); g.stroke() }
  const arriba = () => {
    if (!dibujando.current) return; dibujando.current = false
    // se guarda reducida (ancho 480): la firma viaja al servidor y pesa poco
    const cv = ref.current; const o = document.createElement('canvas'); o.width = 480; o.height = Math.round(480 * cv.height / cv.width)
    o.getContext('2d').drawImage(cv, 0, 0, o.width, o.height); onCambio(o.toDataURL('image/png'))
  }
  const borrar = () => { const cv = ref.current; cv.getContext('2d').clearRect(0, 0, cv.width, cv.height); onCambio(null) }
  return (
    <div className="ai-firma">
      <canvas id={id} ref={ref} onPointerDown={abajo} onPointerMove={mueve} onPointerUp={arriba} onPointerCancel={arriba} aria-label="Espacio para firmar con el dedo" />
      <button type="button" className="link" onClick={borrar}>Borrar firma</button>
    </div>
  )
}

// ═════════ el auditor interno: sus auditorías, con y sin señal ═════════
export function MisAuditorias({ api, demo, cuenta, onClose }) {
  const [lista, setLista] = useState(null)
  const [abierta, setAbierta] = useState(null)
  const [msg, setMsg] = useState(null)   // { t, cls }
  const [senal, setSenal] = useState(enLinea())
  const tabla = useMemo(() => almacen(demo, cuenta), [demo, cuenta])

  const leer = () => tabla.toArray().then(l => setLista(l.sort((a, b) => (a.estado_local === 'enviada') - (b.estado_local === 'enviada') || a.fecha_plan.localeCompare(b.fecha_plan))))
  const enviar = async (silencioso) => {
    const r = await enviarPendientes(api, demo, cuenta); await leer()
    if (r.enviadas) setMsg({ t: r.enviadas === 1 ? 'Informe enviado.' : `${r.enviadas} informes enviados.`, cls: 'ok' })
    else if (r.sinRed && !silencioso) setMsg({ t: 'Sin señal: los informes firmados siguen guardados en este equipo y se envían solos al volver la señal.', cls: 'err' })
  }
  const actualizar = async () => {
    setMsg(null)
    try { const n = await descargar(api, demo, cuenta); await leer(); setMsg({ t: n ? `${n} auditoría${n === 1 ? '' : 's'} nueva${n === 1 ? '' : 's'} guardada${n === 1 ? '' : 's'} en este equipo: ya se pueden hacer sin señal.` : 'Lista al día y guardada en este equipo.', cls: 'ok' }) } catch (e) {
      await leer(); setMsg({ t: enLinea() ? String(e?.message || e) : 'Sin señal: se muestra lo que ya está guardado en este equipo.', cls: 'err' })
    }
    enviar(true)
  }
  useEffect(() => { actualizar() }, [])
  useEffect(() => {
    const on = () => { setSenal(true); enviar(true) }; const off = () => setSenal(false)
    window.addEventListener('online', on); window.addEventListener('offline', off)
    return () => { window.removeEventListener('online', on); window.removeEventListener('offline', off) }
  }, [])

  if (abierta) return <Auditoria id={abierta} tabla={tabla} onVolver={async (firmada) => { setAbierta(null); await leer(); if (firmada) enviar(false) }} />

  const ESTADO_LOCAL = { pendiente: ['Por hacer', 'warn'], en_curso: ['En curso', 'warn'], por_enviar: ['Firmada, sin enviar', 'err'], enviada: ['Enviada', 'ok'] }
  const porEnviar = (lista || []).filter(b => b.estado_local === 'por_enviar').length
  return (
    <div className="overlay" onClick={onClose}>
      <div className="sheet qms-sheet" onClick={e => e.stopPropagation()} role="dialog" aria-labelledby="ai-mis-t">
        <div className="sheet-head"><strong id="ai-mis-t"><Icono n="fact_check" /> Mis auditorías internas</strong>
          <button className="link" onClick={onClose}>Cerrar <Icono n="close" /></button></div>
        <div className="qms-cuerpo">
          <div className={'ai-senal ' + (senal ? 'on' : 'off')}><Icono n={senal ? 'wifi' : 'wifi_off'} />{senal ? 'Con señal' : 'Sin señal: se trabaja con lo guardado en este equipo'}</div>
          <p className="muted">Antes de salir a la finca, con señal, se abre esta pantalla: las auditorías asignadas quedan guardadas en el equipo. En la finca
            todo funciona sin señal, y cada respuesta se guarda en el acto.</p>
          {msg ? <div className={'qms-msg ' + msg.cls} role="status">{msg.t}</div> : null}
          <div className="qms-barra">
            <button className="link" onClick={actualizar}><Icono n="sync" />Actualizar la lista</button>
            {porEnviar ? <button className="primary" onClick={() => enviar(false)}><Icono n="send" />Enviar {porEnviar} firmada{porEnviar === 1 ? '' : 's'}</button> : null}
          </div>
          {lista === null ? <p className="muted">Cargando…</p> : !lista.length ? <p className="muted">No tiene auditorías internas asignadas.</p> : (
            <ul className="qms-lista">
              {lista.map(b => { const [l, c] = ESTADO_LOCAL[b.estado_local] || [b.estado_local, 'off']; const f = faltantes(b.resultados || {}); return (
                <li key={b.id} className="qms-socio">
                  <div className="qms-socio-cab"><strong>{b.socio_nombre}</strong><span className={'qms-estado ' + c}>{l}</span></div>
                  <div className="muted">{b.socio_identificacion} · planificada para el {FECHA(b.fecha_plan)} · {b.client_slug}</div>
                  {b.estado_local === 'en_curso' ? <div className="muted">{PUNTOS.length - f.sinResultado.length} de {PUNTOS.length} puntos respondidos</div> : null}
                  {b.cumplimiento ? <div className="muted">Major {PCT(b.cumplimiento.pct_major)} · Minor {PCT(b.cumplimiento.pct_minor)}</div> : null}
                  {b.error ? <div className="qms-motivo">El servidor no la aceptó: {b.error}</div> : null}
                  <div className="qms-acciones">
                    {b.estado_local === 'pendiente' || b.estado_local === 'en_curso' ? (
                      <button className="link" onClick={() => setAbierta(b.id)}><Icono n="play_arrow" />{b.estado_local === 'pendiente' ? 'Empezar' : 'Continuar'}</button>
                    ) : null}
                    {b.estado_local === 'por_enviar' && b.error ? (
                      <button className="link" onClick={() => tabla.update(b.id, { estado_local: 'en_curso', error: null }).then(() => setAbierta(b.id))}><Icono n="edit" />Corregir y volver a firmar</button>
                    ) : null}
                    {b.estado_local === 'enviada' ? <button className="link" onClick={() => tabla.delete(b.id).then(leer)}><Icono n="delete" />Quitar de este equipo</button> : null}
                  </div>
                </li>) })}
            </ul>
          )}
        </div>
      </div>
    </div>
  )
}

function Auditoria({ id, tabla, onVolver }) {
  const [b, setB] = useState(null)
  const [filtro, setFiltro] = useState('todos')
  const [firmar, setFirmar] = useState(false)
  useEffect(() => { tabla.get(id).then(setB) }, [id])
  // cada cambio se guarda en el equipo en el acto: si la batería muere a mitad de la finca, no se pierde nada
  const guardar = (nuevo) => { setB(nuevo); tabla.put(nuevo) }
  if (!b) return null

  const empezar = () => guardar({ ...b, inicio: new Date().toISOString(), estado_local: 'en_curso' })
  const poner = (code, cambios) => guardar({ ...b, resultados: { ...b.resultados, [code]: { ...(b.resultados[code] || {}), ...cambios } } })
  const f = faltantes(b.resultados)
  const falta = new Set([...f.sinResultado, ...f.sinComentario, ...f.sinPlazo])
  const visibles = PUNTOS.filter(p => filtro === 'todos' || (filtro === 'faltan' && falta.has(p.code)) || (filtro === 'nc' && (b.resultados[p.code] || {}).resultado === 'no_cumple'))

  // La hoja de firmar va FUERA de esta hoja: dentro, el panel de la hoja la encogía a 32 px de ancho.
  return (
    <>
    <div className="overlay">
      <div className="sheet qms-sheet ai-hoja" role="dialog" aria-labelledby="ai-aud-t">
        <div className="sheet-head"><strong id="ai-aud-t">{b.socio_nombre}</strong>
          <button className="link" onClick={() => onVolver(false)}><Icono n="arrow_back" />Mis auditorías</button></div>
        {!b.inicio ? (
          <div className="qms-cuerpo">
            <div className="card ai-socio">
              <h3><Icono n="agriculture" />{b.socio_nombre}</h3>
              <dl className="ai-datos">
                <dt>Cédula o RUC</dt><dd>{b.socio_identificacion}</dd>
                <dt>Dirección</dt><dd>{b.direccion || '—'}</dd>
                <dt>Productos</dt><dd>{(b.productos || []).map(p => `${p.cultivo} ${p.area_ha} ha`).join(' · ') || '—'}</dd>
                <dt>Sitios</dt><dd>{(b.sitios || []).map(s => s.nombre).join(' · ') || '—'}</dd>
                <dt>Lista</dt><dd>{FUENTE} · {PUNTOS.length} puntos</dd>
              </dl>
            </div>
            <p className="muted">Al empezar queda registrada la hora de inicio (QMS 05.02 g x). La de fin se registra al firmar.</p>
            <button id="ai-empezar" className="primary" onClick={empezar}><Icono n="play_arrow" />Empezar la auditoría</button>
          </div>
        ) : (
          <>
            <div className="ai-barra-prog">
              <div className="ai-prog"><span style={{ width: `${Math.round(100 * (PUNTOS.length - f.sinResultado.length) / PUNTOS.length)}%` }} /></div>
              <div className="ai-prog-txt">
                <b>{PUNTOS.length - f.sinResultado.length} de {PUNTOS.length}</b> · desde las {HORA(b.inicio)}
                {f.sinComentario.length ? ` · ${f.sinComentario.length} sin comentario` : ''}{f.sinPlazo.length ? ` · ${f.sinPlazo.length} sin plazo` : ''}
              </div>
              <div className="chips">
                {[['todos', 'Todos'], ['faltan', `Lo que falta (${falta.size})`], ['nc', 'No cumple']].map(([k, t]) => (
                  <button key={k} className={'chip ' + (filtro === k ? 'sel' : '')} onClick={() => setFiltro(k)}>{t}</button>))}
                <button id="ai-firmar" className="primary" disabled={f.total > 0} onClick={() => setFirmar(true)}><Icono n="draw" />Cerrar y firmar</button>
              </div>
            </div>
            <div className="qms-cuerpo ai-puntos">
              {SECCIONES.map(sec => { const ps = visibles.filter(p => p.seccion === sec); if (!ps.length) return null; return (
                <section key={sec}>
                  <h4 className="ai-sec">{sec}</h4>
                  {ps.map(p => { const x = b.resultados[p.code] || {}; return (
                    <article key={p.code} className={'ai-punto ' + (x.resultado || '') + (falta.has(p.code) && x.resultado ? ' falta' : '')}>
                      <div className="ai-punto-cab"><b>{p.code}</b><span className={'qms-estado ' + NIVEL_CLS[p.nivel]}>{p.nivel}</span></div>
                      <div className="ai-punto-txt">{p.label}</div>
                      <details><summary>Texto oficial</summary><p className="muted">{p.criterio}</p></details>
                      <div className="ai-res" role="radiogroup" aria-label={'Resultado de ' + p.code}>
                        {Object.entries(RESULTADOS).map(([k, t]) => (
                          <button key={k} role="radio" aria-checked={x.resultado === k} className={'ai-res-b ' + k + (x.resultado === k ? ' sel' : '')}
                            onClick={() => poner(p.code, { resultado: k })}>{t}</button>))}
                      </div>
                      {x.resultado && (pideComentario(p.nivel, x.resultado) || x.comentario !== undefined) ? (
                        <label className="ai-com">Comentario{pideComentario(p.nivel, x.resultado) ? ' (obligatorio)' : ''}
                          <textarea rows={2} maxLength={1000} value={x.comentario || ''} onChange={e => poner(p.code, { comentario: e.target.value })}
                            placeholder={x.resultado === 'no_aplica' ? 'Por qué no aplica' : x.resultado === 'no_cumple' ? 'Qué se encontró' : 'Qué se verificó'} />
                        </label>
                      ) : x.resultado ? <button className="link ai-mas" onClick={() => poner(p.code, { comentario: '' })}>+ Comentario</button> : null}
                      {pidePlazo(p.nivel, x.resultado) ? (
                        <label className="ai-com">Plazo para la acción correctiva (obligatorio)
                          <input type="date" min={local(new Date(b.inicio))} value={x.plazo || ''} onChange={e => poner(p.code, { plazo: e.target.value })} />
                        </label>
                      ) : null}
                    </article>) })}
                </section>) })}
              {!visibles.length ? <p className="muted">{filtro === 'faltan' ? 'No falta nada: ya se puede cerrar y firmar.' : 'Ningún punto en esta vista.'}</p> : null}
            </div>
          </>
        )}
      </div>
    </div>
    {firmar ? <Firmar b={b} onCancelar={() => setFirmar(false)} onListo={async (datos) => {
      const nuevo = { ...b, ...datos, fin: new Date().toISOString(), estado_local: 'por_enviar', error: null }
      await tabla.put(nuevo); onVolver(true)
    }} /> : null}
    </>
  )
}

function Firmar({ b, onCancelar, onListo }) {
  const [d, setD] = useState({ firmante_nombre: b.firmante_nombre || b.socio_nombre || '', firma_socio: b.firma_socio || null,
    inspector_nombre: b.inspector_nombre || '', firma_inspector: b.firma_inspector || null })
  const c = calcular(b.resultados)
  const ncs = PUNTOS.filter(p => (b.resultados[p.code] || {}).resultado === 'no_cumple')
  const listo = d.firmante_nombre.trim() && d.inspector_nombre.trim() && d.firma_socio && d.firma_inspector
  return (
    <div className="overlay" onClick={onCancelar}>
      <div className="sheet qms-sheet" onClick={e => e.stopPropagation()} role="dialog" aria-labelledby="ai-fir-t">
        <div className="sheet-head"><strong id="ai-fir-t">Cerrar y firmar</strong>
          <button className="link" onClick={onCancelar}>Volver <Icono n="close" /></button></div>
        <div className="qms-cuerpo qms-form">
          <div className="ai-calc">
            <div><b>{PCT(c.pct_major)}</b><span>Major ({c.major_aplicables - c.major_no_cumple} de {c.major_aplicables})</span></div>
            <div><b>{PCT(c.pct_minor)}</b><span>Minor ({c.minor_aplicables - c.minor_no_cumple} de {c.minor_aplicables})</span></div>
            <div><b className={c.cumple ? 'ai-ok' : 'ai-mal'}>{c.cumple ? 'Cumple' : 'No cumple'}</b><span>cálculo preliminar</span></div>
          </div>
          <p className="muted">Se exige Major 100 % y Minor 95 %. La decisión final es de calidad del grupo, con este informe.</p>
          {ncs.length ? (
            <ul className="ai-ncs">{ncs.map(p => <li key={p.code}><b>{p.code}</b> {p.label}<div className="muted">plazo: {FECHA(b.resultados[p.code].plazo)}</div></li>)}</ul>
          ) : null}
          <h4>Firma del socio o del responsable del sitio</h4>
          <label>Nombre<input id="ai-fir-socio-n" value={d.firmante_nombre} onChange={e => setD({ ...d, firmante_nombre: e.target.value })} maxLength={200} /></label>
          <FirmaPad id="ai-fir-socio" valor={d.firma_socio} onCambio={v => setD(x => ({ ...x, firma_socio: v }))} />
          <h4>Firma del auditor interno</h4>
          <label>Nombre<input id="ai-fir-insp-n" value={d.inspector_nombre} onChange={e => setD({ ...d, inspector_nombre: e.target.value })} maxLength={200} /></label>
          <FirmaPad id="ai-fir-insp" valor={d.firma_inspector} onCambio={v => setD(x => ({ ...x, firma_inspector: v }))} />
          <p className="muted">Al terminar se registra la hora de fin. El informe queda guardado en este equipo y se envía en cuanto haya señal; después ya no se edita.</p>
          <button id="ai-terminar" className="primary" disabled={!listo} onClick={() => onListo({ ...d, firmante_nombre: d.firmante_nombre.trim(), inspector_nombre: d.inspector_nombre.trim() })}>
            <Icono n="check" />Terminar y guardar</button>
        </div>
      </div>
    </div>
  )
}
