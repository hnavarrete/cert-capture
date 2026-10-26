// Incumplimientos y sanciones — GlobalG.A.P. opción 2 (QMS v6.0, 05.03), parte 3a. Encargo v2 de #15 (pitahaya).
// Los de la auditoría interna los crea el servidor solo, uno por cada «no cumple» del informe enviado. Aquí la directiva
// o calidad anota la acción correctiva, el responsable y el plazo, los cierra con evidencia y decide las sanciones.
// El servidor (cert_qms_nc_* y cert_qms_sancion* de 20261026000000) es quien hace cumplir las reglas.
import React, { useEffect, useState } from 'react'
import { Icono } from './eudr-react/CertForm.jsx'

const local = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
const hoy = () => local(new Date())
const masDias = (n) => { const d = new Date(); d.setDate(d.getDate() + n); return local(d) }
const FECHA = (s) => { if (!s) return '—'; try { return new Date(s.length === 10 ? s + 'T12:00:00' : s).toLocaleDateString('es', { dateStyle: 'medium' }) } catch { return s } }

const ORIGEN = { auditoria_interna: 'Auditoría interna', auditoria_externa: 'Auditoría del organismo certificador', reclamo: 'Reclamo', qms: 'Falla del QMS' }
const ESTADO_NC = { abierta: ['Abierta', 'warn'], en_curso: ['En curso', 'warn'], cerrada: ['Cerrada', 'ok'] }
const TIPO = { advertencia: 'Advertencia', suspension: 'Suspensión', cancelacion: 'Cancelación' }
const vencida = (n) => n.estado !== 'cerrada' && n.plazo < hoy()
// El error del servidor va DENTRO de la ventana abierta: detrás de ella no se ve.
const texto = (e) => { const t = String(e?.message || e || 'No se pudo completar.'); return t.charAt(0).toUpperCase() + t.slice(1) }

export function Incumplimientos({ slug, gestiona, api, socios, onSocios, onOk, onError }) {
  const [lista, setLista] = useState(null)
  const [sanciones, setSanciones] = useState(null)
  const [filtro, setFiltro] = useState('abiertas')
  const [editar, setEditar] = useState(null)    // nc (nuevo: {})
  const [cerrar, setCerrar] = useState(null)    // { n, evidencia, nombre }
  const [sancionar, setSancionar] = useState(null)
  const [aviso, setAviso] = useState(null)      // { s, fecha }
  const [levantar, setLevantar] = useState(null)
  const [err, setErr] = useState('')
  useEffect(() => setErr(''), [editar, cerrar, sancionar, aviso, levantar])
  const falla = (e) => setErr(texto(e))

  const cargar = () => {
    api.ncLista(slug).then(setLista).catch(e => { setLista([]); onError(e) })
    api.sanciones(slug).then(setSanciones).catch(e => { setSanciones([]); onError(e) })
  }
  useEffect(cargar, [slug])
  const hecho = (t) => { cargar(); onSocios(); onOk(t) }

  const n = (f) => (lista || []).filter(f).length
  const visibles = (lista || []).filter(x => filtro === 'todas' || (filtro === 'abiertas' && x.estado !== 'cerrada') ||
    (filtro === 'vencidas' && vencida(x)) || (filtro === 'cerradas' && x.estado === 'cerrada'))
  const sinAviso = (sanciones || []).filter(s => s.tipo !== 'advertencia' && !s.aviso_cb_en).length

  return (
    <div className="qms-form ai-crono">
      <div className="qms-metricas">
        <div><b>{n(x => x.estado !== 'cerrada')}</b><span>abiertos</span></div>
        <div><b>{n(vencida)}</b><span>con el plazo vencido</span></div>
        <div><b>{n(x => x.estado === 'cerrada')}</b><span>cerrados</span></div>
        <div><b>{(sanciones || []).filter(s => s.tipo === 'suspension' && !s.levantada_en).length}</b><span>suspensiones vigentes</span></div>
        <div><b>{sinAviso}</b><span>sanciones sin aviso al certificador</span></div>
      </div>
      <p className="muted">Cada «no cumple» de una auditoría interna enviada aparece aquí solo. Cada incumplimiento lleva su acción correctiva, su
        responsable y su plazo (QMS 05.03 b, c), y se cierra con la evidencia y el nombre de quien verificó.</p>

      <div className="qms-barra">
        <select id="nc-filtro" value={filtro} onChange={e => setFiltro(e.target.value)} aria-label="Filtrar incumplimientos">
          <option value="abiertas">Abiertos</option><option value="vencidas">Con el plazo vencido</option>
          <option value="cerradas">Cerrados</option><option value="todas">Todos</option>
        </select>
        {gestiona ? <button className="primary" onClick={() => setEditar({ origen: 'auditoria_externa', plazo: masDias(30) })}><Icono n="add_circle" />Registrar incumplimiento</button> : null}
      </div>

      {lista === null ? <p className="muted">Cargando…</p> : !visibles.length ? <p className="muted">Ningún incumplimiento en esta vista.</p> : (
        <ul className="qms-lista">
          {visibles.map(x => { const [l, c] = ESTADO_NC[x.estado]; return (
            <li key={x.id} className={'qms-socio nc-' + x.estado}>
              <div className="qms-socio-cab"><strong>{x.socio_nombre || 'Grupo (QMS)'}</strong><span className={'qms-estado ' + (vencida(x) ? 'err' : c)}>{vencida(x) ? 'Plazo vencido' : l}</span></div>
              <div className="muted">{ORIGEN[x.origen]}{x.code ? ` · ${x.code}` : ''}{x.gravedad ? ` · ${x.gravedad}` : ''}</div>
              <div>{x.descripcion}</div>
              <div className="muted">Acción: {x.accion_correctiva || <i>sin anotar</i>} · responsable: {x.responsable || <i>sin anotar</i>} · plazo: <b>{FECHA(x.plazo)}</b></div>
              {x.estado === 'cerrada' ? <div className="muted">Cerrado el {FECHA(x.cerrada_en)} por {x.cerrada_por_nombre}: {x.cierre_evidencia}</div> : null}
              {gestiona && x.estado !== 'cerrada' ? (
                <div className="qms-acciones">
                  <button className="link" onClick={() => setEditar({ ...x, en_curso: x.estado === 'en_curso' })}><Icono n="edit" />Acción y responsable</button>
                  <button className="link" onClick={() => setCerrar({ n: x, evidencia: '', nombre: '' })}><Icono n="check" />Cerrar</button>
                  {x.miembro_id ? <button className="link" onClick={() => setSancionar({ miembro: x.miembro_id, nc: x.id, tipo: 'advertencia', motivo: x.descripcion, nombre: '', producto: '' })}><Icono n="block" />Sancionar</button> : null}
                </div>
              ) : null}
            </li>) })}
        </ul>
      )}

      <h4>Sanciones (QMS 05.03 d–h)</h4>
      {gestiona ? (
        <div className="qms-barra">
          <button className="link" onClick={() => setSancionar({ miembro: (socios.find(m => m.estado !== 'excluido') || {}).id || '', nc: '', tipo: 'advertencia', motivo: '', nombre: '', producto: '' })}><Icono n="block" />Sancionar a un socio</button>
        </div>
      ) : null}
      {sanciones === null ? <p className="muted">Cargando…</p> : !sanciones.length ? <p className="muted">No hay sanciones.</p> : (
        <ul className="qms-lista">
          {sanciones.map(s => (
            <li key={s.id} className="qms-socio">
              <div className="qms-socio-cab"><strong>{s.socio_nombre}</strong>
                <span className={'qms-estado ' + (s.tipo === 'advertencia' ? 'warn' : s.levantada_en ? 'ok' : 'err')}>{TIPO[s.tipo]}{s.levantada_en ? ' levantada' : ''}</span></div>
              <div>{s.motivo}{s.producto ? ` · producto: ${s.producto}` : ''}</div>
              <div className="muted">Decidió {s.decidida_por_nombre} el {FECHA(s.decidida_en)}{s.nc_descripcion ? ` · incumplimiento: ${s.nc_descripcion} (${(ESTADO_NC[s.nc_estado] || [''])[0].toLowerCase()})` : ''}</div>
              {s.tipo !== 'advertencia' ? <div className={s.aviso_cb_en ? 'muted' : 'qms-motivo'}>{s.aviso_cb_en ? `Aviso al organismo certificador: ${FECHA(s.aviso_cb_en)}` : 'Falta anotar el aviso al organismo certificador (05.03 f)'}</div> : null}
              {s.levantada_en ? <div className="muted">Levantada el {FECHA(s.levantada_en)} por {s.levantada_por_nombre}: {s.levantada_motivo}</div> : null}
              {gestiona ? (
                <div className="qms-acciones">
                  {s.tipo !== 'advertencia' && !s.aviso_cb_en ? <button className="link" onClick={() => setAviso({ s, fecha: hoy() })}><Icono n="mail" />Anotar el aviso</button> : null}
                  {s.tipo === 'suspension' && !s.levantada_en ? <button className="link" onClick={() => setLevantar({ s, motivo: '', nombre: '' })}><Icono n="check" />Levantar</button> : null}
                </div>
              ) : null}
            </li>
          ))}
        </ul>
      )}

      {editar ? <EditarNc inicial={editar} slug={slug} socios={socios} api={api} onCerrar={() => setEditar(null)}
        onListo={(nuevo) => { setEditar(null); hecho(nuevo ? 'Incumplimiento registrado.' : 'Cambios guardados.') }} onError={falla} err={err} /> : null}

      {cerrar ? (
        <Hoja err={err} titulo={'Cerrar: ' + (cerrar.n.socio_nombre || 'Grupo (QMS)')} onCerrar={() => setCerrar(null)}>
          <p className="muted">{cerrar.n.descripcion}</p>
          <p className="muted">Acción: {cerrar.n.accion_correctiva || 'sin anotar'} · responsable: {cerrar.n.responsable || 'sin anotar'}</p>
          <label>Evidencia de que se corrigió (obligatoria)<textarea id="nc-evidencia" rows={3} maxLength={1000} value={cerrar.evidencia} onChange={e => setCerrar({ ...cerrar, evidencia: e.target.value })} placeholder="Qué se revisó y dónde" /></label>
          <label>Su nombre (verificó)<input id="nc-cierra-nombre" value={cerrar.nombre} onChange={e => setCerrar({ ...cerrar, nombre: e.target.value })} maxLength={200} /></label>
          <p className="muted">Cerrado, ya no se edita.</p>
          <button className="primary" disabled={!cerrar.evidencia.trim() || !cerrar.nombre.trim()}
            onClick={() => api.ncCerrar(cerrar.n.id, cerrar.evidencia, cerrar.nombre).then(() => { setCerrar(null); hecho('Incumplimiento cerrado.') }).catch(falla)}>Cerrar el incumplimiento</button>
        </Hoja>
      ) : null}

      {sancionar ? (
        <Hoja err={err} titulo="Sancionar a un socio" onCerrar={() => setSancionar(null)}>
          <label>Socio
            <select id="san-socio" value={sancionar.miembro} disabled={!!sancionar.nc} onChange={e => setSancionar({ ...sancionar, miembro: e.target.value })}>
              {socios.filter(m => m.estado !== 'excluido').map(m => <option key={m.id} value={m.id}>{m.nombre}</option>)}
            </select>
          </label>
          <div className="ai-radios" role="radiogroup" aria-label="Tipo de sanción">
            {Object.entries(TIPO).map(([k, t]) => (
              <label key={k} className="qms-check"><input type="radio" name="san-tipo" checked={sancionar.tipo === k} onChange={() => setSancionar({ ...sancionar, tipo: k })} />{t}</label>))}
          </div>
          <p className="muted">{sancionar.tipo === 'advertencia' ? 'El socio sigue activo; queda en su registro.' : sancionar.tipo === 'suspension'
            ? 'El socio pasa a «suspendido» con el producto entero (05.03 e). Se levanta cuando su incumplimiento esté cerrado.'
            : 'El socio pasa a «excluido». Hay que avisar al organismo certificador (05.03 f).'}</p>
          {sancionar.tipo === 'suspension' ? <label>Producto suspendido<input id="san-producto" value={sancionar.producto} onChange={e => setSancionar({ ...sancionar, producto: e.target.value })} placeholder="pitahaya amarilla" maxLength={120} /></label> : null}
          <label>Motivo (obligatorio)<textarea id="san-motivo" rows={3} maxLength={1000} value={sancionar.motivo} onChange={e => setSancionar({ ...sancionar, motivo: e.target.value })} /></label>
          <label>Su nombre (decide)<input id="san-nombre" value={sancionar.nombre} onChange={e => setSancionar({ ...sancionar, nombre: e.target.value })} maxLength={200} /></label>
          <button className="primary" disabled={!sancionar.miembro || sancionar.motivo.trim().length < 3 || !sancionar.nombre.trim()}
            onClick={() => api.sancionar(slug, sancionar.miembro, sancionar.tipo, sancionar.motivo.trim(), sancionar.nombre.trim(), sancionar.nc, sancionar.producto)
              .then(() => { setSancionar(null); hecho('Sanción registrada.') }).catch(falla)}>Registrar la sanción</button>
        </Hoja>
      ) : null}

      {aviso ? (
        <Hoja err={err} titulo={'Aviso al certificador: ' + aviso.s.socio_nombre} onCerrar={() => setAviso(null)}>
          <label>Fecha en que se avisó<input id="san-aviso" type="date" max={hoy()} value={aviso.fecha} onChange={e => setAviso({ ...aviso, fecha: e.target.value })} /></label>
          <p className="muted">Se anota una sola vez.</p>
          <button className="primary" disabled={!aviso.fecha} onClick={() => api.avisoCb(aviso.s.id, aviso.fecha).then(() => { setAviso(null); hecho('Aviso anotado.') }).catch(falla)}>Anotar el aviso</button>
        </Hoja>
      ) : null}

      {levantar ? (
        <Hoja err={err} titulo={'Levantar la suspensión: ' + levantar.s.socio_nombre} onCerrar={() => setLevantar(null)}>
          {levantar.s.nc_estado && levantar.s.nc_estado !== 'cerrada'
            ? <div className="qms-msg err">Su incumplimiento sigue abierto: la suspensión se levanta cuando esté cerrado (QMS 05.03 h).</div> : null}
          <label>Motivo (obligatorio)<textarea id="san-lev-motivo" rows={3} maxLength={1000} value={levantar.motivo} onChange={e => setLevantar({ ...levantar, motivo: e.target.value })} /></label>
          <label>Su nombre (decide)<input id="san-lev-nombre" value={levantar.nombre} onChange={e => setLevantar({ ...levantar, nombre: e.target.value })} maxLength={200} /></label>
          <button className="primary" disabled={!levantar.motivo.trim() || !levantar.nombre.trim()}
            onClick={() => api.levantar(levantar.s.id, levantar.motivo, levantar.nombre).then(() => { setLevantar(null); hecho('Suspensión levantada: el socio vuelve a activo.') }).catch(falla)}>Levantar la suspensión</button>
        </Hoja>
      ) : null}
    </div>
  )
}

function Hoja({ titulo, onCerrar, children, err }) {
  return (
    <div className="overlay" onClick={onCerrar}>
      <div className="sheet qms-mini" onClick={e => e.stopPropagation()} role="dialog" aria-label={titulo}>
        <div className="sheet-head"><strong>{titulo}</strong><button className="link" onClick={onCerrar}>Cerrar <Icono n="close" /></button></div>
        <div className="qms-form qms-cuerpo">{children}{err ? <div className="qms-msg err" role="alert">{err}</div> : null}</div>
      </div>
    </div>
  )
}

function EditarNc({ inicial, slug, socios, api, onCerrar, onListo, onError, err }) {
  const [f, setF] = useState({ descripcion: '', accion_correctiva: '', responsable: '', en_curso: false, miembro_id: '', ...inicial })
  const nuevo = !inicial.id
  const set = (k) => (e) => setF({ ...f, [k]: e.target.type === 'checkbox' ? e.target.checked : e.target.value })
  return (
    <Hoja err={err} titulo={nuevo ? 'Registrar incumplimiento' : 'Acción y responsable'} onCerrar={onCerrar}>
      {nuevo ? (
        <>
          <label>Origen
            <select id="nc-origen" value={f.origen} onChange={set('origen')}>
              <option value="auditoria_externa">{ORIGEN.auditoria_externa}</option><option value="reclamo">{ORIGEN.reclamo}</option><option value="qms">{ORIGEN.qms}</option>
            </select>
          </label>
          <label>Socio (vacío si es del grupo)
            <select id="nc-socio" value={f.miembro_id} onChange={set('miembro_id')}>
              <option value="">Grupo (QMS)</option>
              {socios.filter(m => m.estado !== 'excluido').map(m => <option key={m.id} value={m.id}>{m.nombre}</option>)}
            </select>
          </label>
        </>
      ) : <p className="muted">{ORIGEN[f.origen]}{f.code ? ` · ${f.code}` : ''} · {f.socio_nombre || 'Grupo (QMS)'}</p>}
      <label>Qué se encontró
        <textarea id="nc-desc" rows={3} maxLength={1000} value={f.descripcion} onChange={set('descripcion')} disabled={f.origen === 'auditoria_interna'} />
      </label>
      {f.origen === 'auditoria_interna' ? <p className="muted">Lo que encontró la auditoría interna no se reescribe.</p> : null}
      <label>Acción correctiva<textarea id="nc-accion" rows={2} maxLength={1000} value={f.accion_correctiva || ''} onChange={set('accion_correctiva')} /></label>
      <div className="qms-2">
        <label>Responsable (05.03 c)<input id="nc-resp" value={f.responsable || ''} onChange={set('responsable')} maxLength={200} /></label>
        <label>Plazo (05.03 b)<input id="nc-plazo" type="date" value={f.plazo || ''} onChange={set('plazo')} /></label>
      </div>
      <label className="qms-check"><input type="checkbox" checked={!!f.en_curso} onChange={set('en_curso')} />La acción ya está en curso</label>
      <button className="primary" disabled={!f.plazo || (nuevo && f.descripcion.trim().length < 3)}
        onClick={() => api.ncGuardar({ ...f, client_slug: slug, miembro_id: f.miembro_id || null }).then(() => onListo(nuevo)).catch(onError)}>
        {nuevo ? 'Registrar' : 'Guardar'}</button>
    </Hoja>
  )
}
