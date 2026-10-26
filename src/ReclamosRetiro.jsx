// Reclamos, retiro de producto y balance de masas — GlobalG.A.P. opción 2 (QMS v6.0: 04, 07, 06 b), parte 3b.
// Encargo v2 de #15 (pitahaya). El servidor (cert_qms_reclamo*, cert_qms_retiro*, cert_qms_balance* de 20261026010000)
// hace cumplir las reglas; aquí se muestran a tiempo: qué falta para cerrar, si el simulacro anual o el balance vencieron.
import React, { useEffect, useState } from 'react'
import { Icono } from './eudr-react/CertForm.jsx'
import { Hoja, texto } from './Incumplimientos.jsx'

const local = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
const hoy = () => local(new Date())
const masDias = (n) => { const d = new Date(); d.setDate(d.getDate() + n); return local(d) }
const FECHA = (s) => { if (!s) return '—'; try { return new Date(s.length === 10 ? s + 'T12:00:00' : s).toLocaleDateString('es', { dateStyle: 'medium' }) } catch { return s } }
const ahoraLocal = () => { const d = new Date(); d.setSeconds(0, 0); return new Date(d - d.getTimezoneOffset() * 60e3).toISOString().slice(0, 16) }
const dias = (s) => Math.floor((new Date() - new Date(s.length === 10 ? s + 'T12:00:00' : s)) / 864e5)
const num = (v) => (v == null || v === '' ? 0 : Number(v))
const fmt = (n) => Number(n).toLocaleString('es', { maximumFractionDigits: 2 })

const ORIGEN = { cliente: 'Cliente', autoridad: 'Autoridad', socio: 'Socio', otro: 'Otro' }
const TEMA = { inocuidad: 'Inocuidad', trabajadores: 'Trabajadores', ambiente: 'Ambiente', calidad: 'Calidad', otro: 'Otro' }
const EST_REC = { recibido: ['Recibido', 'warn'], en_investigacion: ['En investigación', 'warn'], cerrado: ['Cerrado', 'ok'] }
const UNIDADES = ['kg', 'gavetas', 'cajas', 'unidades']
const CUSTODY = 'https://custody.visiongeografica.com/'

export function ReclamosRetiro({ slug, gestiona, api, socios, onOk }) {
  const [reclamos, setReclamos] = useState(null)
  const [retiros, setRetiros] = useState(null)
  const [balances, setBalances] = useState(null)
  const [hoja, setHoja] = useState(null)   // { tipo, ...datos }
  const [err, setErr] = useState('')
  useEffect(() => setErr(''), [hoja])
  const falla = (e) => setErr(texto(e))

  const cargar = () => {
    api.reclamos(slug).then(setReclamos).catch(e => { setReclamos([]); falla(e) })
    api.retiros(slug).then(setRetiros).catch(e => { setRetiros([]); falla(e) })
    api.balances(slug).then(setBalances).catch(e => { setBalances([]); falla(e) })
  }
  useEffect(cargar, [slug])
  const listo = (t) => { setHoja(null); cargar(); onOk(t) }
  const set = (k) => (e) => setHoja({ ...hoja, [k]: e.target.type === 'checkbox' ? e.target.checked : e.target.value })

  // 07 d: un ejercicio de retiro al año (uno real cerrado también cuenta)
  const ultimoRetiro = (retiros || []).filter(r => r.estado === 'cerrado').sort((a, b) => b.terminado_en.localeCompare(a.terminado_en))[0]
  const retiroVigente = ultimoRetiro && dias(ultimoRetiro.terminado_en) <= 365
  // 06 b: un balance al año por producto registrado (los productos salen del registro de socios)
  const productos = [...new Set(socios.filter(m => m.estado === 'activo').flatMap(m => (m.productos || []).map(p => (p.cultivo || '').trim().toLowerCase())).filter(Boolean))]
  const ultimoBalance = (p) => (balances || []).filter(b => b.producto.trim().toLowerCase() === p).sort((a, b) => b.hasta.localeCompare(a.hasta))[0]

  return (
    <div className="qms-form ai-crono">
      <div className="qms-metricas">
        <div><b>{(reclamos || []).filter(r => r.estado !== 'cerrado').length}</b><span>reclamos abiertos</span></div>
        <div><b>{(reclamos || []).filter(r => r.requiere_aviso && !r.aviso_cb_en).length}</b><span>reclamos sin aviso al certificador</span></div>
        <div><b className={retiroVigente ? 'ai-ok' : 'ai-mal'}>{retiroVigente ? 'Al día' : 'Vencido'}</b><span>simulacro de retiro anual</span></div>
        <div><b>{productos.filter(p => { const b = ultimoBalance(p); return !b || dias(b.hasta) > 365 }).length}</b><span>productos sin balance del año</span></div>
      </div>
      {err && !hoja ? <div className="qms-msg err" role="alert">{err}</div> : null}

      {/* ───────── reclamos (QMS 04) ───────── */}
      <h4>Reclamos (QMS 04)</h4>
      <p className="muted">Se registra cada reclamo contra el grupo o contra un socio, se investiga y se cierra con su conclusión. Los de inocuidad,
        trabajadores o ambiente se cierran con el aviso al organismo certificador (04 e).</p>
      {gestiona ? <div className="qms-barra"><button className="primary" onClick={() => setHoja({ tipo: 'reclamo', recibido_en: hoy(), origen: 'cliente', tema: 'calidad', miembro_id: '', descripcion: '' })}><Icono n="add_circle" />Registrar reclamo</button></div> : null}
      {reclamos === null ? <p className="muted">Cargando…</p> : !reclamos.length ? <p className="muted">No hay reclamos registrados.</p> : (
        <ul className="qms-lista">
          {reclamos.map(r => { const [l, c] = EST_REC[r.estado]; return (
            <li key={r.id} className="qms-socio">
              <div className="qms-socio-cab"><strong>{TEMA[r.tema]} · {r.socio_nombre || 'contra el grupo'}</strong><span className={'qms-estado ' + c}>{l}</span></div>
              <div className="muted">Recibido el {FECHA(r.recibido_en)} · {ORIGEN[r.origen]}</div>
              <div>{r.descripcion}</div>
              {r.investigacion ? <div className="muted">Investigación: {r.investigacion}</div> : null}
              {r.seguimiento ? <div className="muted">Seguimiento: {r.seguimiento}</div> : null}
              {r.requiere_aviso ? <div className={r.aviso_cb_en ? 'muted' : 'qms-motivo'}>{r.aviso_cb_en ? `Aviso al organismo certificador: ${FECHA(r.aviso_cb_en)}` : 'Exige avisar al organismo certificador (04 e)'}</div> : null}
              {r.nc_abiertas ? <div className="qms-motivo">{r.nc_abiertas} incumplimiento{r.nc_abiertas === 1 ? '' : 's'} abierto{r.nc_abiertas === 1 ? '' : 's'} por este reclamo</div> : null}
              {r.estado === 'cerrado' ? <div className="muted">Cerrado el {FECHA(r.cerrado_en)} por {r.cerrado_por_nombre}: {r.conclusion}</div> : null}
              {gestiona && r.estado !== 'cerrado' ? (
                <div className="qms-acciones">
                  <button className="link" onClick={() => setHoja({ tipo: 'investigar', r, investigacion: r.investigacion || '', seguimiento: r.seguimiento || '' })}><Icono n="search" />Investigación</button>
                  {r.requiere_aviso && !r.aviso_cb_en ? <button className="link" onClick={() => setHoja({ tipo: 'aviso', r, fecha: hoy() })}><Icono n="mail" />Anotar el aviso</button> : null}
                  <button className="link" onClick={() => setHoja({ tipo: 'nc', r, descripcion: r.descripcion, plazo: masDias(30), miembro_id: r.miembro_id || '' })}><Icono n="report" />Abrir incumplimiento</button>
                  <button className="link" onClick={() => setHoja({ tipo: 'cerrar_rec', r, conclusion: '', nombre: '' })}><Icono n="check" />Cerrar</button>
                </div>
              ) : null}
            </li>) })}
        </ul>
      )}

      {/* ───────── retiro de producto (QMS 07) ───────── */}
      <h4>Retiro de producto (QMS 07)</h4>
      <p className="muted">{ultimoRetiro ? `Último ejercicio cerrado: ${ultimoRetiro.tipo === 'real' ? 'retiro real' : 'simulacro'} del ${FECHA(ultimoRetiro.terminado_en)}. ` : 'Todavía no hay un ejercicio de retiro cerrado. '}
        {retiroVigente ? `Vigente hasta el ${FECHA(local(new Date(new Date(ultimoRetiro.terminado_en).getTime() + 365 * 864e5)))}.` : 'Toca hacer el simulacro anual (07 d).'}</p>
      {gestiona ? (
        <div className="qms-barra">
          <button className="primary" onClick={() => setHoja({ tipo: 'retiro', t: 'simulacro', iniciado_en: ahoraLocal(), producto: productos[0] || '', lotes: '', motivo: '', decide_nombre: '' })}><Icono n="play_arrow" />Iniciar simulacro</button>
          <button className="link" onClick={() => setHoja({ tipo: 'retiro', t: 'real', iniciado_en: ahoraLocal(), producto: productos[0] || '', lotes: '', motivo: '', decide_nombre: '' })}><Icono n="error" />Registrar retiro real</button>
          <a className="link" href={CUSTODY} target="_blank" rel="noopener noreferrer"><Icono n="open_in_new" />Lotes y balance en VG Custody</a>
        </div>
      ) : null}
      {retiros === null ? <p className="muted">Cargando…</p> : !retiros.length ? null : (
        <ul className="qms-lista">
          {retiros.map(r => (
            <li key={r.id} className="qms-socio">
              <div className="qms-socio-cab"><strong>{r.tipo === 'real' ? 'Retiro real' : 'Simulacro'} · {r.producto}</strong>
                <span className={'qms-estado ' + (r.estado === 'cerrado' ? 'ok' : 'warn')}>{r.estado === 'cerrado' ? 'Cerrado' : 'En curso'}</span></div>
              <div className="muted">Desde el {FECHA(r.iniciado_en)}{r.terminado_en ? ` hasta el ${FECHA(r.terminado_en)}` : ''} · decidió {r.decide_nombre}</div>
              <div>{r.motivo}</div>
              {r.lotes ? <div className="muted">Lotes: {r.lotes}</div> : null}
              {r.cantidad_afectada != null ? <div className="muted">Conciliación: {fmt(r.cantidad_localizada ?? 0)} de {fmt(r.cantidad_afectada)} {r.unidad} localizados
                ({Math.round(1000 * num(r.cantidad_localizada) / num(r.cantidad_afectada)) / 10} %)</div> : null}
              {r.clientes_avisados ? <div className="muted">Clientes avisados: {r.clientes_avisados}</div> : null}
              {r.tipo === 'real' ? <div className={r.aviso_cb_en ? 'muted' : 'qms-motivo'}>{r.aviso_cb_en ? `Aviso al organismo certificador: ${FECHA(r.aviso_cb_en)}` : 'Falta el aviso al organismo certificador'}</div> : null}
              {r.resultado ? <div className="muted">Resultado: {r.resultado}</div> : null}
              {gestiona && r.estado !== 'cerrado' ? (
                <div className="qms-acciones">
                  <button className="link" onClick={() => setHoja({ tipo: 'conciliar', r, lotes: r.lotes || '', clientes_avisados: r.clientes_avisados || '', aviso_cb_en: r.aviso_cb_en || '',
                    unidad: r.unidad || 'kg', cantidad_afectada: r.cantidad_afectada ?? '', cantidad_localizada: r.cantidad_localizada ?? '', resultado: r.resultado || '' })}><Icono n="edit" />Conciliación</button>
                  <button className="link" onClick={() => setHoja({ tipo: 'cerrar_ret', r, nombre: '' })}><Icono n="check" />Cerrar</button>
                </div>
              ) : null}
            </li>
          ))}
        </ul>
      )}

      {/* ───────── balance de masas (QMS 06 b) ───────── */}
      <h4>Balance de masas (QMS 06 b)</h4>
      <p className="muted">Uno al año por producto registrado, con lo certificado y lo no certificado por separado. Las cifras salen del balance de VG Custody.</p>
      <ul className="qms-lista">
        {productos.map(p => { const b = ultimoBalance(p); const al = b && dias(b.hasta) <= 365; return (
          <li key={p} className="qms-socio">
            <div className="qms-socio-cab"><strong>{p}</strong><span className={'qms-estado ' + (al ? 'ok' : 'err')}>{al ? 'Al día' : b ? 'Vencido' : 'Sin balance'}</span></div>
            {b ? <>
              <div className="muted">{FECHA(b.desde)} – {FECHA(b.hasta)} · {b.fuente || 'sin fuente'} · {b.hecho_por_nombre}</div>
              <div className="muted">Certificado: entró {fmt(b.entradas_cert)}, salió {fmt(b.salidas_cert)}, queda {fmt(b.existencias_cert)} {b.unidad} · diferencia {fmt(num(b.entradas_cert) - num(b.salidas_cert) - num(b.existencias_cert))}</div>
              <div className="muted">{b.conclusion}</div>
            </> : null}
            {gestiona ? <div className="qms-acciones"><button className="link" onClick={() => setHoja({ tipo: 'balance', producto: p, desde: masDias(-366), hasta: masDias(-1), unidad: 'kg',
              entradas_cert: '', entradas_no_cert: '', salidas_cert: '', salidas_no_cert: '', existencias_cert: '', existencias_no_cert: '', conclusion: '',
              fuente: 'VG Custody · balance de masas', hecho_por_nombre: '' })}><Icono n="add_circle" />Registrar balance</button></div> : null}
          </li>) })}
        {!productos.length ? <p className="muted">No hay socios activos con productos registrados.</p> : null}
      </ul>

      {/* ───────── ventanas ───────── */}
      {hoja?.tipo === 'reclamo' ? (
        <Hoja err={err} titulo="Registrar reclamo" onCerrar={() => setHoja(null)}>
          <div className="qms-2">
            <label>Recibido el<input id="rec-fecha" type="date" max={hoy()} value={hoja.recibido_en} onChange={set('recibido_en')} /></label>
            <label>De<select id="rec-origen" value={hoja.origen} onChange={set('origen')}>{Object.entries(ORIGEN).map(([k, t]) => <option key={k} value={k}>{t}</option>)}</select></label>
            <label>Tema<select id="rec-tema" value={hoja.tema} onChange={set('tema')}>{Object.entries(TEMA).map(([k, t]) => <option key={k} value={k}>{t}</option>)}</select></label>
            <label>Contra<select id="rec-socio" value={hoja.miembro_id} onChange={set('miembro_id')}><option value="">El grupo</option>
              {socios.filter(m => m.estado !== 'excluido').map(m => <option key={m.id} value={m.id}>{m.nombre}</option>)}</select></label>
          </div>
          {['inocuidad', 'trabajadores', 'ambiente'].includes(hoja.tema) ? <p className="qms-motivo">Este tema exige avisar al organismo certificador (QMS 04 e).</p> : null}
          <label>Qué dice el reclamo<textarea id="rec-desc" rows={3} maxLength={2000} value={hoja.descripcion} onChange={set('descripcion')} /></label>
          <button className="primary" disabled={hoja.descripcion.trim().length < 3}
            onClick={() => api.reclamoGuardar({ client_slug: slug, ...hoja, miembro_id: hoja.miembro_id || null }).then(() => listo('Reclamo registrado.')).catch(falla)}>Registrar</button>
        </Hoja>
      ) : null}
      {hoja?.tipo === 'investigar' ? (
        <Hoja err={err} titulo="Investigación y seguimiento" onCerrar={() => setHoja(null)}>
          <p className="muted">{hoja.r.descripcion}</p>
          <label>Investigación (qué se revisó y qué se encontró)<textarea id="rec-inv" rows={3} maxLength={2000} value={hoja.investigacion} onChange={set('investigacion')} /></label>
          <label>Seguimiento<textarea id="rec-seg" rows={2} maxLength={2000} value={hoja.seguimiento} onChange={set('seguimiento')} /></label>
          <button className="primary" onClick={() => api.reclamoGuardar({ id: hoja.r.id, investigacion: hoja.investigacion, seguimiento: hoja.seguimiento }).then(() => listo('Reclamo actualizado.')).catch(falla)}>Guardar</button>
        </Hoja>
      ) : null}
      {hoja?.tipo === 'aviso' ? (
        <Hoja err={err} titulo="Aviso al organismo certificador" onCerrar={() => setHoja(null)}>
          <label>Fecha en que se avisó<input id="rec-aviso" type="date" max={hoy()} value={hoja.fecha} onChange={set('fecha')} /></label>
          <p className="muted">Se anota una sola vez.</p>
          <button className="primary" disabled={!hoja.fecha} onClick={() => api.reclamoAviso(hoja.r.id, hoja.fecha).then(() => listo('Aviso anotado.')).catch(falla)}>Anotar el aviso</button>
        </Hoja>
      ) : null}
      {hoja?.tipo === 'nc' ? (
        <Hoja err={err} titulo="Incumplimiento desde el reclamo" onCerrar={() => setHoja(null)}>
          <label>Socio<select id="rec-nc-socio" value={hoja.miembro_id} onChange={set('miembro_id')}><option value="">Grupo (QMS)</option>
            {socios.filter(m => m.estado !== 'excluido').map(m => <option key={m.id} value={m.id}>{m.nombre}</option>)}</select></label>
          <label>Qué hay que corregir<textarea id="rec-nc-desc" rows={3} maxLength={1000} value={hoja.descripcion} onChange={set('descripcion')} /></label>
          <label>Plazo<input id="rec-nc-plazo" type="date" value={hoja.plazo} onChange={set('plazo')} /></label>
          <p className="muted">Queda en «Incumplimientos», ligado a este reclamo, para seguirlo hasta cerrarlo.</p>
          <button className="primary" disabled={hoja.descripcion.trim().length < 3 || !hoja.plazo}
            onClick={() => api.ncGuardar({ client_slug: slug, origen: 'reclamo', reclamo_id: hoja.r.id, miembro_id: hoja.miembro_id || null, descripcion: hoja.descripcion, plazo: hoja.plazo })
              .then(() => listo('Incumplimiento abierto desde el reclamo.')).catch(falla)}>Abrir incumplimiento</button>
        </Hoja>
      ) : null}
      {hoja?.tipo === 'cerrar_rec' ? (
        <Hoja err={err} titulo="Cerrar el reclamo" onCerrar={() => setHoja(null)}>
          <p className="muted">{hoja.r.descripcion}</p>
          <label>Conclusión<textarea id="rec-concl" rows={3} maxLength={2000} value={hoja.conclusion} onChange={set('conclusion')} /></label>
          <label>Su nombre<input id="rec-cierra" value={hoja.nombre} onChange={set('nombre')} maxLength={200} /></label>
          <button className="primary" disabled={!hoja.conclusion.trim() || !hoja.nombre.trim()}
            onClick={() => api.reclamoCerrar(hoja.r.id, hoja.conclusion, hoja.nombre).then(() => listo('Reclamo cerrado.')).catch(falla)}>Cerrar el reclamo</button>
        </Hoja>
      ) : null}
      {hoja?.tipo === 'retiro' ? (
        <Hoja err={err} titulo={hoja.t === 'real' ? 'Registrar retiro real' : 'Iniciar simulacro de retiro'} onCerrar={() => setHoja(null)}>
          <div className="qms-2">
            <label>Inicio<input id="ret-ini" type="datetime-local" value={hoja.iniciado_en} onChange={set('iniciado_en')} /></label>
            <label>Producto<input id="ret-prod" value={hoja.producto} onChange={set('producto')} maxLength={120} /></label>
          </div>
          <label>Evento que lo origina<textarea id="ret-motivo" rows={2} maxLength={1000} value={hoja.motivo} onChange={set('motivo')}
            placeholder={hoja.t === 'real' ? 'Ej.: reclamo de inocuidad del cliente' : 'Ej.: simulacro anual, residuo sobre el límite'} /></label>
          <label>Lotes afectados (códigos de VG Custody)<input id="ret-lotes" value={hoja.lotes} onChange={set('lotes')} maxLength={2000} /></label>
          <label>Quién decide el retiro<input id="ret-decide" value={hoja.decide_nombre} onChange={set('decide_nombre')} maxLength={200} /></label>
          <button className="primary" disabled={hoja.producto.trim().length < 2 || hoja.motivo.trim().length < 3 || hoja.decide_nombre.trim().length < 2}
            onClick={() => api.retiroGuardar({ client_slug: slug, tipo: hoja.t, iniciado_en: new Date(hoja.iniciado_en).toISOString(), producto: hoja.producto,
              lotes: hoja.lotes, motivo: hoja.motivo, decide_nombre: hoja.decide_nombre }).then(() => listo(hoja.t === 'real' ? 'Retiro registrado.' : 'Simulacro iniciado.')).catch(falla)}>
            {hoja.t === 'real' ? 'Registrar' : 'Iniciar'}</button>
        </Hoja>
      ) : null}
      {hoja?.tipo === 'conciliar' ? (
        <Hoja err={err} titulo="Conciliación del retiro" onCerrar={() => setHoja(null)}>
          <label>Lotes<input id="ret-c-lotes" value={hoja.lotes} onChange={set('lotes')} maxLength={2000} /></label>
          <div className="qms-2">
            <label>Unidad<select id="ret-unidad" value={hoja.unidad} onChange={set('unidad')}>{UNIDADES.map(u => <option key={u} value={u}>{u}</option>)}</select></label>
            <label>Cantidad afectada<input id="ret-afectada" inputMode="decimal" value={hoja.cantidad_afectada} onChange={set('cantidad_afectada')} /></label>
            <label>Cantidad localizada<input id="ret-localizada" inputMode="decimal" value={hoja.cantidad_localizada} onChange={set('cantidad_localizada')} /></label>
            {hoja.r.tipo === 'real' ? <label>Aviso al certificador<input id="ret-aviso" type="date" max={hoy()} value={hoja.aviso_cb_en} onChange={set('aviso_cb_en')} disabled={!!hoja.r.aviso_cb_en} /></label> : null}
          </div>
          {num(hoja.cantidad_afectada) > 0 ? <p className="muted">Localizado: {Math.round(1000 * num(hoja.cantidad_localizada) / num(hoja.cantidad_afectada)) / 10} %</p> : null}
          <label>Clientes avisados<input id="ret-clientes" value={hoja.clientes_avisados} onChange={set('clientes_avisados')} maxLength={1000} /></label>
          <label>Resultado y lecciones<textarea id="ret-resultado" rows={3} maxLength={2000} value={hoja.resultado} onChange={set('resultado')} /></label>
          <button className="primary" onClick={() => api.retiroGuardar({ id: hoja.r.id, ...hoja, r: undefined, tipo: undefined }).then(() => listo('Conciliación guardada.')).catch(falla)}>Guardar</button>
        </Hoja>
      ) : null}
      {hoja?.tipo === 'cerrar_ret' ? (
        <Hoja err={err} titulo="Cerrar el retiro" onCerrar={() => setHoja(null)}>
          <p className="muted">Se cierra con la conciliación, los clientes avisados, el resultado{hoja.r.tipo === 'real' ? ' y el aviso al organismo certificador' : ''}. Se anota la hora de fin.</p>
          <label>Su nombre<input id="ret-cierra" value={hoja.nombre} onChange={set('nombre')} maxLength={200} /></label>
          <button className="primary" disabled={!hoja.nombre.trim()} onClick={() => api.retiroCerrar(hoja.r.id, hoja.nombre).then(() => listo('Retiro cerrado.')).catch(falla)}>Cerrar el retiro</button>
        </Hoja>
      ) : null}
      {hoja?.tipo === 'balance' ? (
        <Hoja err={err} titulo={'Balance de masas: ' + hoja.producto} onCerrar={() => setHoja(null)}>
          <p className="muted"><a className="link" href={CUSTODY} target="_blank" rel="noopener noreferrer"><Icono n="open_in_new" />Abrir el balance en VG Custody</a> y pasar sus cifras.</p>
          <div className="qms-2">
            <label>Desde<input id="bal-desde" type="date" value={hoja.desde} onChange={set('desde')} /></label>
            <label>Hasta<input id="bal-hasta" type="date" max={hoy()} value={hoja.hasta} onChange={set('hasta')} /></label>
            <label>Unidad<select id="bal-unidad" value={hoja.unidad} onChange={set('unidad')}>{UNIDADES.map(u => <option key={u} value={u}>{u}</option>)}</select></label>
            <span />
            <label>Entró certificado<input id="bal-ec" inputMode="decimal" value={hoja.entradas_cert} onChange={set('entradas_cert')} /></label>
            <label>Entró no certificado<input id="bal-enc" inputMode="decimal" value={hoja.entradas_no_cert} onChange={set('entradas_no_cert')} /></label>
            <label>Salió certificado<input id="bal-sc" inputMode="decimal" value={hoja.salidas_cert} onChange={set('salidas_cert')} /></label>
            <label>Salió no certificado<input id="bal-snc" inputMode="decimal" value={hoja.salidas_no_cert} onChange={set('salidas_no_cert')} /></label>
            <label>Queda certificado<input id="bal-xc" inputMode="decimal" value={hoja.existencias_cert} onChange={set('existencias_cert')} /></label>
            <label>Queda no certificado<input id="bal-xnc" inputMode="decimal" value={hoja.existencias_no_cert} onChange={set('existencias_no_cert')} /></label>
          </div>
          <p className={num(hoja.entradas_cert) - num(hoja.salidas_cert) - num(hoja.existencias_cert) === 0 ? 'muted' : 'qms-motivo'}>
            Diferencia en lo certificado: {fmt(num(hoja.entradas_cert) - num(hoja.salidas_cert) - num(hoja.existencias_cert))} {hoja.unidad}
            {num(hoja.entradas_cert) - num(hoja.salidas_cert) - num(hoja.existencias_cert) < 0 ? ' · salió más certificado del que entró: hay que explicarlo' : ''}</p>
          <label>Conclusión<textarea id="bal-concl" rows={2} maxLength={2000} value={hoja.conclusion} onChange={set('conclusion')} /></label>
          <label>Fuente<input id="bal-fuente" value={hoja.fuente} onChange={set('fuente')} maxLength={300} /></label>
          <label>Su nombre<input id="bal-nombre" value={hoja.hecho_por_nombre} onChange={set('hecho_por_nombre')} maxLength={200} /></label>
          <p className="muted">Registrado, ya no se edita.</p>
          <button className="primary" disabled={hoja.entradas_cert === '' || hoja.salidas_cert === '' || hoja.conclusion.trim().length < 3 || hoja.hecho_por_nombre.trim().length < 2}
            onClick={() => api.balanceRegistrar({ client_slug: slug, ...hoja, tipo: undefined }).then(() => listo('Balance registrado.')).catch(falla)}>Registrar el balance</button>
        </Hoja>
      ) : null}
    </div>
  )
}
