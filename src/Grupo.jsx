// Mi grupo — gestión de grupo de GlobalG.A.P. opción 2 (QMS v6.0), parte 1: registro interno de miembros (4.1.2.2),
// productores excluidos (4.1.2.2 b) y auditor externo en solo lectura. Encargo v2 de #15 (cadena de la pitahaya).
// El servidor es la fuente de verdad (funciones cert_qms_* de la migración 20261023000000); la pantalla solo ofrece lo
// que el nivel permite. En modo demo trabaja con una asociación sintética en memoria que aplica las MISMAS reglas.
import React, { useEffect, useMemo, useState } from 'react'
import { supabase } from './supabase.js'
import { Icono } from './eudr-react/CertForm.jsx'

const ESTADOS = {
  aspirante: { label: 'Aspirante', cls: 'warn' },
  activo: { label: 'Activo', cls: 'ok' },
  suspendido: { label: 'Suspendido', cls: 'err' },
  excluido: { label: 'Excluido', cls: 'off' }
}
// Qué se puede hacer desde cada estado. Suspender y excluir piden el motivo (lo exige también el servidor).
const ACCIONES = {
  aspirante: [['activo', 'Activar'], ['excluido', 'Excluir']],
  activo: [['suspendido', 'Suspender'], ['excluido', 'Excluir']],
  suspendido: [['activo', 'Reactivar'], ['excluido', 'Excluir']],
  excluido: [['aspirante', 'Readmitir como aspirante']]
}
const PIDE_MOTIVO = new Set(['suspendido', 'excluido'])
const NIVEL_LABEL = { admin: 'Administración VG', gestion: 'Directiva o calidad', captura: 'Técnico o socio', lectura: 'Solo lectura', auditor: 'Auditor externo' }

// Fecha LOCAL (no toISOString, que es UTC: en Ecuador, desde las 19:00 ya daría el día siguiente y el tope del auditor
// quedaría un día por encima del que acepta el servidor, que cuenta en hora de Guayaquil).
const local = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
const hoy = () => local(new Date())
const masDias = (n) => { const d = new Date(); d.setDate(d.getDate() + n); return local(d) }
const FECHA = (s) => { if (!s) return '—'; try { return new Date(s.length === 10 ? s + 'T12:00:00' : s).toLocaleDateString('es', { dateStyle: 'medium' }) } catch { return s } }
const areaTotal = (m) => (m.productos || []).reduce((t, p) => t + (Number(p.area_ha) || 0), 0)
const cedulaValida = (c) => /^[0-9]{10}([0-9]{3})?$/.test(c || '')

// ───────── acceso a datos ─────────
function apiServidor() {
  const rpc = async (fn, args) => {
    const { data, error } = await supabase.rpc(fn, args)
    if (error) throw new Error(error.message || 'No se pudo completar')
    return data
  }
  return {
    misGrupos: () => rpc('cert_qms_mis_grupos'),
    miembros: (slug) => rpc('cert_qms_miembros', { p_slug: slug }),
    historial: (id) => rpc('cert_qms_historial', { p_miembro: id }),
    guardar: (p) => rpc('cert_qms_guardar_miembro', { p }),
    cambiarEstado: (id, estado, motivo) => rpc('cert_qms_cambiar_estado', { p_miembro: id, p_estado: estado, p_motivo: motivo || null }),
    auditores: (slug) => rpc('cert_qms_auditores', { p_slug: slug }),
    autorizar: (slug, correo, organismo, vence) => rpc('cert_qms_autorizar_auditor', { p_slug: slug, p_correo: correo, p_organismo: organismo, p_vence: vence }),
    revocar: (id) => rpc('cert_qms_revocar_auditor', { p_id: id })
  }
}

// Asociación SINTÉTICA para el modo demo y los videos de ayuda (R-AYUDA: nunca datos de clientes).
let DEMO = null
function demoInicial() {
  const socio = (i, nombre, prod, estado, extra = {}) => ({
    id: 'demo-' + i, client_slug: 'demo-pitahaya', identificacion: String(1599999900 + i), nombre,
    telefono: '0990000' + String(100 + i), correo: null, direccion: 'Sector demo ' + i,
    productos: prod, sitios: [{ nombre: 'Finca demo ' + i, area_ha: prod.reduce((t, p) => t + p.area_ha, 0), certificado: estado === 'activo' }],
    certificador: 'Organismo certificador demo', ggn: null, estado, fecha_ingreso: '2024-0' + (1 + (i % 8)) + '-15',
    contrato_fecha: '2024-0' + (1 + (i % 8)) + '-15', contrato_ref: 'Contrato demo ' + i, ultima_auditoria_interna: estado === 'activo' ? '2026-0' + (3 + (i % 6)) + '-10' : null,
    estado_motivo: null, excluido_en: null, ...extra
  })
  const s = [
    socio(1, 'Productora demo A', [{ cultivo: 'pitahaya amarilla', area_ha: 2.1 }], 'activo'),
    socio(2, 'Productor demo B', [{ cultivo: 'pitahaya amarilla', area_ha: 1.8 }], 'activo'),
    socio(3, 'Productora demo C', [{ cultivo: 'pitahaya amarilla', area_ha: 2.4 }, { cultivo: 'pitahaya roja', area_ha: 0.5 }], 'activo'),
    socio(4, 'Productor demo D', [{ cultivo: 'pitahaya amarilla', area_ha: 1.2 }], 'aspirante'),
    socio(5, 'Productora demo E', [{ cultivo: 'pitahaya amarilla', area_ha: 2.0 }], 'suspendido', { estado_motivo: 'Registro de aplicaciones incompleto (demo)' }),
    socio(6, 'Productor demo F', [{ cultivo: 'pitahaya amarilla', area_ha: 1.5 }], 'excluido', { estado_motivo: 'Producto no autorizado (demo)', excluido_en: '2026-06-02T10:00:00Z' })
  ]
  return {
    miembros: s,
    historial: s.flatMap(m => [{ id: m.id + '-h0', miembro_id: m.id, de: null, a: 'aspirante', motivo: null, por_correo: 'directiva@demo', en: m.fecha_ingreso + 'T09:00:00Z' }]
      .concat(m.estado !== 'aspirante' ? [{ id: m.id + '-h1', miembro_id: m.id, de: 'aspirante', a: m.estado, motivo: m.estado_motivo, por_correo: 'directiva@demo', en: m.fecha_ingreso + 'T15:00:00Z' }] : [])),
    auditores: [{ id: 'demo-aud-1', client_slug: 'demo-pitahaya', correo: 'auditora@certificador.demo', organismo: 'Organismo certificador demo', vence: masDias(60), otorgado_en: new Date().toISOString(), revocado_en: null }]
  }
}
function apiDemo() {
  if (!DEMO) DEMO = demoInicial()
  const pausa = (v) => new Promise(r => setTimeout(() => r(v), 150))
  const hist = (m, de, a) => DEMO.historial.push({ id: 'h' + Date.now() + Math.random(), miembro_id: m.id, de, a, motivo: m.estado_motivo, por_correo: 'usted (demo)', en: new Date().toISOString() })
  return {
    misGrupos: () => pausa([{ client_slug: 'demo-pitahaya', nivel: 'gestion', vence: null }]),
    miembros: () => pausa([...DEMO.miembros].sort((a, b) => (a.estado === 'excluido') - (b.estado === 'excluido') || a.nombre.localeCompare(b.nombre))),
    historial: (id) => pausa(DEMO.historial.filter(h => h.miembro_id === id).sort((a, b) => a.en.localeCompare(b.en))),
    guardar: (p) => {
      if (p.id) { const m = DEMO.miembros.find(x => x.id === p.id); Object.assign(m, { ...p, identificacion: m.identificacion, estado: m.estado }); return pausa(m.id) }
      if (DEMO.miembros.some(m => m.identificacion === p.identificacion)) return Promise.reject(new Error('Esa cédula o RUC ya está registrada en el grupo'))
      const m = { ...p, id: 'demo-' + Date.now(), estado: 'aspirante', estado_motivo: null, excluido_en: null }
      DEMO.miembros.push(m); hist(m, null, 'aspirante'); return pausa(m.id)
    },
    cambiarEstado: (id, estado, motivo) => {
      if (PIDE_MOTIVO.has(estado) && !(motivo || '').trim()) return Promise.reject(new Error('suspender o excluir a un socio exige el motivo'))
      const m = DEMO.miembros.find(x => x.id === id); const de = m.estado
      Object.assign(m, { estado, estado_motivo: (motivo || '').trim() || null, excluido_en: estado === 'excluido' ? new Date().toISOString() : null })
      hist(m, de, estado); return pausa(null)
    },
    auditores: () => pausa([...DEMO.auditores]),
    autorizar: (slug, correo, organismo, vence) => {
      if (!vence || vence < hoy()) return Promise.reject(new Error('el permiso del auditor necesita una fecha de vencimiento futura'))
      if (vence > masDias(366)) return Promise.reject(new Error('el permiso de un auditor vence en un año como máximo'))
      DEMO.auditores.unshift({ id: 'demo-aud-' + Date.now(), client_slug: slug, correo: correo.toLowerCase(), organismo, vence, otorgado_en: new Date().toISOString(), revocado_en: null })
      return pausa('ok')
    },
    revocar: (id) => { DEMO.auditores.find(a => a.id === id).revocado_en = new Date().toISOString(); return pausa(null) }
  }
}

// Mensajes del servidor → texto para la persona (sin códigos).
function mensaje(e) {
  const t = String(e?.message || e || '')
  if (/unique|duplicate|ya está registrada/i.test(t)) return 'Esa cédula o RUC ya está registrada en el grupo.'
  if (/qms_auditores_vence_max_un_anio|un año como máximo/i.test(t)) return 'El permiso de un auditor vence en un año como máximo.'
  if (/qms_miembros_identificacion_check/i.test(t)) return 'La cédula debe tener 10 dígitos, o 13 si es RUC.'
  if (/ggn_check/i.test(t)) return 'El GGN tiene 13 dígitos.'
  if (/sin acceso|solo la directiva|sin permiso/i.test(t)) return 'Su rol no permite esta acción en el grupo.'
  if (/Failed to fetch|NetworkError/i.test(t)) return 'Sin conexión: el registro de socios necesita señal para guardar.'
  return t || 'No se pudo completar.'
}

// CSV para entregar el registro al auditor (4.1.2.2). Una celda que empieza con = + - @ se neutraliza (inyección en Excel).
function csvRegistro(socios) {
  const celda = (v) => { let s = v == null ? '' : String(v); if (/^[=+\-@]/.test(s)) s = "'" + s; return '"' + s.replace(/"/g, '""') + '"' }
  const cab = ['Cédula/RUC', 'Socio', 'Teléfono', 'Correo', 'Dirección', 'Productos', 'Área total (ha)', 'Sitios', 'Certificador', 'GGN',
    'Estado interno', 'Motivo del estado', 'Fecha de ingreso', 'Contrato', 'Última auditoría interna']
  const filas = socios.map(m => [m.identificacion, m.nombre, m.telefono, m.correo, m.direccion,
    (m.productos || []).map(p => `${p.cultivo} ${p.area_ha} ha`).join('; '), areaTotal(m).toFixed(2),
    (m.sitios || []).map(s => `${s.nombre} ${s.area_ha} ha${s.certificado ? ' (certificado)' : ' (no certificado)'}`).join('; '),
    m.certificador, m.ggn, (ESTADOS[m.estado] || {}).label || m.estado, m.estado_motivo, m.fecha_ingreso,
    [m.contrato_fecha, m.contrato_ref].filter(Boolean).join(' · '), m.ultima_auditoria_interna])
  return '﻿' + [cab, ...filas].map(f => f.map(celda).join(';')).join('\r\n')
}

export default function Grupo({ demo = false, onClose, pantallaCompleta = false }) {
  const api = useMemo(() => (demo ? apiDemo() : apiServidor()), [demo])
  const [grupos, setGrupos] = useState(null)
  const [slug, setSlug] = useState('')
  const [tab, setTab] = useState('socios')
  const [socios, setSocios] = useState(null)
  const [filtro, setFiltro] = useState('todos')
  const [busca, setBusca] = useState('')
  const [editando, setEditando] = useState(null)
  const [accion, setAccion] = useState(null)   // { m, estado, label }
  const [historial, setHistorial] = useState(null)  // { m, filas }
  const [auditores, setAuditores] = useState(null)
  const [error, setError] = useState('')
  const [aviso, setAviso] = useState('')

  const nivel = (grupos || []).find(g => g.client_slug === slug)?.nivel || null
  const gestiona = nivel === 'gestion' || nivel === 'admin'

  useEffect(() => {
    api.misGrupos().then(g => { setGrupos(g || []); if (g && g.length) setSlug(g[0].client_slug) })
      .catch(e => { setGrupos([]); setError(mensaje(e)) })
  }, [api])
  const cargarSocios = () => { if (!slug) return; setSocios(null); api.miembros(slug).then(setSocios).catch(e => { setSocios([]); setError(mensaje(e)) }) }
  const cargarAuditores = () => { if (!slug || !gestiona) return; setAuditores(null); api.auditores(slug).then(setAuditores).catch(e => { setAuditores([]); setError(mensaje(e)) }) }
  useEffect(cargarSocios, [slug])
  useEffect(() => { if (tab === 'auditores') cargarAuditores() }, [tab, slug, gestiona])

  const visibles = (socios || []).filter(m => (filtro === 'todos' || m.estado === filtro) &&
    (!busca || (m.nombre + ' ' + m.identificacion).toLowerCase().includes(busca.toLowerCase())))
  const cuenta = (e) => (socios || []).filter(m => m.estado === e).length
  const areaActiva = (socios || []).filter(m => m.estado === 'activo').reduce((t, m) => t + areaTotal(m), 0)

  const ok = (t) => { setAviso(t); setError(''); setTimeout(() => setAviso(''), 3500) }
  const descargar = () => {
    const blob = new Blob([csvRegistro(socios || [])], { type: 'text/csv;charset=utf-8' })
    const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = `registro_interno_miembros_${slug}_${hoy()}.csv`; a.click()
    setTimeout(() => URL.revokeObjectURL(a.href), 2000)
  }

  const cuerpo = (
    <>
      <div className="qms-cab">
        {grupos && grupos.length > 1 ? (
          <label>Grupo
            <select id="qms-grupo" value={slug} onChange={e => setSlug(e.target.value)}>
              {grupos.map(g => <option key={g.client_slug} value={g.client_slug}>{g.client_slug}</option>)}
            </select>
          </label>
        ) : slug ? <strong className="qms-slug">{slug}</strong> : null}
        {nivel ? <span className={'rolbadge ' + (gestiona ? 'gestion' : 'lectura')}>{NIVEL_LABEL[nivel] || nivel}</span> : null}
      </div>
      {nivel === 'auditor' ? (
        <div className="rol-aviso lectura"><Icono n="visibility" />Acceso de auditor externo, en solo lectura{(grupos.find(g => g.client_slug === slug) || {}).vence ? `, hasta el ${FECHA(grupos.find(g => g.client_slug === slug).vence)}` : ''}.</div>
      ) : null}
      {error ? <div className="qms-msg err" role="alert">{error}</div> : null}
      {aviso ? <div className="qms-msg ok" role="status">{aviso}</div> : null}

      {grupos && !grupos.length ? (
        <div className="card"><h3><Icono n="hub" />Sin grupo</h3>
          <p className="muted">Su cuenta no administra ni audita un grupo de productores. La gestión de grupo (GlobalG.A.P. opción 2) se activa para
            la directiva de una asociación; el auditor entra cuando la directiva lo autoriza.</p></div>
      ) : null}

      {slug ? (
        <>
          <div className="chips qms-tabs" role="tablist">
            <button role="tab" aria-selected={tab === 'socios'} className={'chip ' + (tab === 'socios' ? 'sel' : '')} onClick={() => setTab('socios')}><Icono n="hub" className="ic" />Registro de socios</button>
            {gestiona ? <button role="tab" aria-selected={tab === 'auditores'} className={'chip ' + (tab === 'auditores' ? 'sel' : '')} onClick={() => setTab('auditores')}><Icono n="verified" className="ic" />Auditores</button> : null}
          </div>

          {tab === 'socios' ? (
            <>
              <div className="qms-metricas">
                <div><b>{cuenta('activo')}</b><span>activos</span></div>
                <div><b>{cuenta('aspirante')}</b><span>aspirantes</span></div>
                <div><b>{cuenta('suspendido')}</b><span>suspendidos</span></div>
                <div><b>{cuenta('excluido')}</b><span>excluidos</span></div>
                <div><b>{areaActiva.toFixed(1)}</b><span>ha de socios activos</span></div>
              </div>
              <div className="qms-barra">
                <input id="qms-busca" placeholder="Buscar por nombre o cédula" value={busca} onChange={e => setBusca(e.target.value)} />
                <select id="qms-filtro" value={filtro} onChange={e => setFiltro(e.target.value)} aria-label="Filtrar por estado">
                  <option value="todos">Todos los estados</option>
                  {Object.entries(ESTADOS).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
                </select>
                {gestiona ? <button className="primary" onClick={() => setEditando({ productos: [{ cultivo: '', area_ha: '' }], sitios: [{ nombre: '', area_ha: '', certificado: false }] })}>Registrar socio</button> : null}
                <button className="link" disabled={!socios || !socios.length} onClick={descargar}>Descargar registro</button>
              </div>
              {socios === null ? <p className="muted">Cargando socios…</p> : !visibles.length ? (
                <p className="muted">{socios.length ? 'Ningún socio coincide con el filtro.' : 'Todavía no hay socios registrados.'}</p>
              ) : (
                <ul className="qms-lista">
                  {visibles.map(m => (
                    <li key={m.id} className={'qms-socio ' + m.estado}>
                      <div className="qms-socio-cab">
                        <strong>{m.nombre}</strong>
                        <span className={'qms-estado ' + (ESTADOS[m.estado] || {}).cls}>{(ESTADOS[m.estado] || {}).label || m.estado}</span>
                      </div>
                      <div className="muted">{m.identificacion} · {(m.productos || []).map(p => `${p.cultivo} ${p.area_ha} ha`).join(' · ') || 'sin productos'}</div>
                      <div className="muted">Última auditoría interna: {FECHA(m.ultima_auditoria_interna)}{m.certificador ? ' · ' + m.certificador : ''}</div>
                      {m.estado_motivo && m.estado !== 'activo' ? <div className="qms-motivo">Motivo: {m.estado_motivo}</div> : null}
                      <div className="qms-acciones">
                        <button className="link" onClick={() => api.historial(m.id).then(f => setHistorial({ m, filas: f })).catch(e => setError(mensaje(e)))}><Icono n="history" />Historial</button>
                        {gestiona ? <button className="link" onClick={() => setEditando({ ...m })}>Editar</button> : null}
                        {gestiona ? (ACCIONES[m.estado] || []).map(([e, l]) => (
                          <button key={e} className="link" onClick={() => setAccion({ m, estado: e, label: l, motivo: '' })}>{l}</button>
                        )) : null}
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </>
          ) : (
            <Auditores lista={auditores} slug={slug} api={api} onCambio={cargarAuditores} onOk={ok} onError={e => setError(mensaje(e))} />
          )}
        </>
      ) : null}

      {editando ? <FormSocio inicial={editando} slug={slug} api={api} onCerrar={() => setEditando(null)}
        onGuardado={(nuevo) => { setEditando(null); cargarSocios(); ok(nuevo ? 'Socio registrado como aspirante.' : 'Cambios guardados.') }} /> : null}

      {accion ? (
        <div className="overlay" onClick={() => setAccion(null)}>
          <div className="sheet qms-mini" onClick={e => e.stopPropagation()} role="dialog" aria-labelledby="qms-accion-t">
            <div className="sheet-head"><strong id="qms-accion-t">{accion.label}: {accion.m.nombre}</strong>
              <button className="link" onClick={() => setAccion(null)}>Cerrar <Icono n="close" /></button></div>
            <div className="qms-form">
              <label>Motivo {PIDE_MOTIVO.has(accion.estado) ? '(obligatorio)' : '(opcional)'}
                <textarea id="qms-motivo" rows={3} maxLength={500} value={accion.motivo} onChange={e => setAccion({ ...accion, motivo: e.target.value })}
                  placeholder={accion.estado === 'excluido' ? 'Ej.: uso de un producto no autorizado' : ''} />
              </label>
              <p className="muted">El cambio queda en el historial del socio con su fecha y quién lo hizo. No se puede borrar.</p>
              <button className="primary" disabled={PIDE_MOTIVO.has(accion.estado) && !accion.motivo.trim()}
                onClick={() => api.cambiarEstado(accion.m.id, accion.estado, accion.motivo)
                  .then(() => { setAccion(null); cargarSocios(); ok(`${accion.m.nombre}: ${(ESTADOS[accion.estado] || {}).label.toLowerCase()}.`) })
                  .catch(e => setError(mensaje(e)))}>Confirmar</button>
            </div>
          </div>
        </div>
      ) : null}

      {historial ? (
        <div className="overlay" onClick={() => setHistorial(null)}>
          <div className="sheet qms-mini" onClick={e => e.stopPropagation()} role="dialog" aria-labelledby="qms-hist-t">
            <div className="sheet-head"><strong id="qms-hist-t">Historial: {historial.m.nombre}</strong>
              <button className="link" onClick={() => setHistorial(null)}>Cerrar <Icono n="close" /></button></div>
            <ol className="qms-hist">
              {historial.filas.map(h => (
                <li key={h.id}><b>{FECHA(h.en)}</b> · {h.de ? `${(ESTADOS[h.de] || {}).label || h.de} → ` : 'Alta como '}{(ESTADOS[h.a] || {}).label || h.a}
                  {h.motivo ? <div className="muted">Motivo: {h.motivo}</div> : null}
                  {h.por_correo ? <div className="muted">Por: {h.por_correo}</div> : null}</li>
              ))}
            </ol>
          </div>
        </div>
      ) : null}
    </>
  )

  if (pantallaCompleta) return <div className="qms-pantalla">{cuerpo}</div>
  return (
    <div className="overlay" onClick={onClose}>
      <div className="sheet qms-sheet" onClick={e => e.stopPropagation()} role="dialog" aria-labelledby="qms-titulo">
        <div className="sheet-head"><strong id="qms-titulo"><Icono n="hub" /> Mi grupo · GlobalG.A.P. opción 2</strong>
          <button className="link" onClick={onClose}>Cerrar <Icono n="close" /></button></div>
        <div className="qms-cuerpo">{cuerpo}</div>
      </div>
    </div>
  )
}

function FormSocio({ inicial, slug, api, onCerrar, onGuardado }) {
  const [f, setF] = useState({ ...inicial, productos: (inicial.productos || []).length ? inicial.productos : [{ cultivo: '', area_ha: '' }],
    sitios: (inicial.sitios || []).length ? inicial.sitios : [{ nombre: '', area_ha: '', certificado: false }] })
  const [error, setError] = useState('')
  const [guardando, setGuardando] = useState(false)
  const nuevo = !inicial.id
  const set = (k) => (e) => setF({ ...f, [k]: e.target.type === 'checkbox' ? e.target.checked : e.target.value })
  const setFila = (lista, i, k) => (e) => {
    const v = e.target.type === 'checkbox' ? e.target.checked : e.target.value
    setF({ ...f, [lista]: f[lista].map((r, j) => (j === i ? { ...r, [k]: v } : r)) })
  }
  const agregar = (lista, vacio) => setF({ ...f, [lista]: [...f[lista], vacio] })
  const quitar = (lista, i) => setF({ ...f, [lista]: f[lista].filter((_, j) => j !== i) })

  const guardar = async () => {
    const productos = f.productos.filter(p => (p.cultivo || '').trim()).map(p => ({ cultivo: p.cultivo.trim(), area_ha: Number(p.area_ha) || 0 }))
    const sitios = f.sitios.filter(s => (s.nombre || '').trim()).map(s => ({ nombre: s.nombre.trim(), area_ha: Number(s.area_ha) || 0, certificado: !!s.certificado }))
    if (nuevo && !cedulaValida((f.identificacion || '').trim())) return setError('La cédula debe tener 10 dígitos, o 13 si es RUC.')
    if (!(f.nombre || '').trim()) return setError('Falta el nombre del socio.')
    if (f.ggn && !/^[0-9]{13}$/.test(f.ggn.trim())) return setError('El GGN tiene 13 dígitos.')
    if (!productos.length) return setError('Anote al menos un producto con su área (4.1.2.2).')
    if ([...productos, ...sitios].some(x => x.area_ha < 0 || x.area_ha > 10000)) return setError('Revise las áreas: van en hectáreas.')
    setGuardando(true); setError('')
    try {
      await api.guardar({ ...f, client_slug: slug, identificacion: (f.identificacion || '').trim(), productos, sitios })
      onGuardado(nuevo)
    } catch (e) { setError(mensaje(e)); setGuardando(false) }
  }

  return (
    <div className="overlay" onClick={onCerrar}>
      <div className="sheet qms-sheet" onClick={e => e.stopPropagation()} role="dialog" aria-labelledby="qms-form-t">
        <div className="sheet-head"><strong id="qms-form-t">{nuevo ? 'Registrar socio' : 'Editar socio'}</strong>
          <button className="link" onClick={onCerrar}>Cerrar <Icono n="close" /></button></div>
        <div className="qms-cuerpo qms-form">
          <div className="qms-2">
            <label>Cédula o RUC
              <input id="qms-ced" inputMode="numeric" value={f.identificacion || ''} onChange={set('identificacion')} disabled={!nuevo} maxLength={13} />
            </label>
            <label>Nombre del socio<input id="qms-nombre" value={f.nombre || ''} onChange={set('nombre')} maxLength={200} /></label>
            <label>Teléfono<input id="qms-tel" inputMode="tel" value={f.telefono || ''} onChange={set('telefono')} maxLength={40} /></label>
            <label>Correo<input id="qms-correo" type="email" value={f.correo || ''} onChange={set('correo')} maxLength={200} /></label>
          </div>
          <label>Dirección<input id="qms-dir" value={f.direccion || ''} onChange={set('direccion')} maxLength={300} /></label>

          <h4>Productos y área</h4>
          {f.productos.map((p, i) => (
            <div key={i} className="qms-fila">
              <input aria-label="Cultivo" placeholder="Cultivo (ej. pitahaya amarilla)" value={p.cultivo} onChange={setFila('productos', i, 'cultivo')} />
              <input aria-label="Hectáreas" inputMode="decimal" placeholder="ha" value={p.area_ha} onChange={setFila('productos', i, 'area_ha')} />
              {f.productos.length > 1 ? <button className="link" aria-label="Quitar producto" onClick={() => quitar('productos', i)}><Icono n="close" /></button> : null}
            </div>
          ))}
          <button className="link" onClick={() => agregar('productos', { cultivo: '', area_ha: '' })}>+ Otro producto</button>

          <h4>Sitios (certificados y no certificados)</h4>
          {f.sitios.map((s, i) => (
            <div key={i} className="qms-fila">
              <input aria-label="Nombre del sitio" placeholder="Nombre del sitio" value={s.nombre} onChange={setFila('sitios', i, 'nombre')} />
              <input aria-label="Hectáreas del sitio" inputMode="decimal" placeholder="ha" value={s.area_ha} onChange={setFila('sitios', i, 'area_ha')} />
              <label className="qms-check"><input type="checkbox" checked={!!s.certificado} onChange={setFila('sitios', i, 'certificado')} />Certificado</label>
              {f.sitios.length > 1 ? <button className="link" aria-label="Quitar sitio" onClick={() => quitar('sitios', i)}><Icono n="close" /></button> : null}
            </div>
          ))}
          <button className="link" onClick={() => agregar('sitios', { nombre: '', area_ha: '', certificado: false })}>+ Otro sitio</button>

          <h4>Certificación y contrato</h4>
          <div className="qms-2">
            <label>Organismo certificador<input id="qms-cert" value={f.certificador || ''} onChange={set('certificador')} maxLength={120} /></label>
            <label>GGN (si lo tiene)<input id="qms-ggn" inputMode="numeric" value={f.ggn || ''} onChange={set('ggn')} maxLength={13} /></label>
            <label>Fecha de ingreso<input id="qms-ingreso" type="date" value={f.fecha_ingreso || ''} onChange={set('fecha_ingreso')} /></label>
            <label>Última auditoría interna<input id="qms-ultima" type="date" value={f.ultima_auditoria_interna || ''} onChange={set('ultima_auditoria_interna')} /></label>
            <label>Fecha del contrato (4.1.1.1)<input id="qms-contrato-f" type="date" value={f.contrato_fecha || ''} onChange={set('contrato_fecha')} /></label>
            <label>Referencia del contrato<input id="qms-contrato-r" value={f.contrato_ref || ''} onChange={set('contrato_ref')} maxLength={200} /></label>
          </div>
          {error ? <div className="qms-msg err" role="alert">{error}</div> : null}
          <button className="primary" disabled={guardando} onClick={guardar}>{guardando ? 'Guardando…' : nuevo ? 'Registrar como aspirante' : 'Guardar cambios'}</button>
          {nuevo ? <p className="muted">Un socio nuevo entra como aspirante. Se activa después de su auditoría interna (QMS 4.5).</p> : null}
        </div>
      </div>
    </div>
  )
}

function Auditores({ lista, slug, api, onCambio, onOk, onError }) {
  const [correo, setCorreo] = useState('')
  const [organismo, setOrganismo] = useState('')
  const [vence, setVence] = useState(masDias(90))
  const estado = (a) => a.revocado_en ? ['Revocado', 'off'] : a.vence < hoy() ? ['Vencido', 'err'] : ['Vigente', 'ok']
  const autorizar = () => {
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(correo.trim())) return onError(new Error('Escriba un correo válido.'))
    api.autorizar(slug, correo.trim(), organismo.trim(), vence).then(() => { setCorreo(''); setOrganismo(''); onCambio(); onOk('Auditor autorizado.') }).catch(onError)
  }
  return (
    <div className="qms-form">
      <p className="muted">El auditor del organismo certificador entra en <b>solo lectura</b> a este grupo, hasta la fecha que usted ponga
        (un año como máximo). Visión Geográfica activa su cuenta con el rol de auditor.</p>
      <div className="qms-2">
        <label>Correo del auditor<input id="qms-aud-correo" type="email" value={correo} onChange={e => setCorreo(e.target.value)} maxLength={200} /></label>
        <label>Organismo certificador<input id="qms-aud-org" value={organismo} onChange={e => setOrganismo(e.target.value)} maxLength={160} /></label>
        <label>Vence el<input id="qms-aud-vence" type="date" min={hoy()} max={masDias(366)} value={vence} onChange={e => setVence(e.target.value)} /></label>
      </div>
      <button className="primary" onClick={autorizar}><Icono n="verified" />Autorizar auditor</button>
      {lista === null ? <p className="muted">Cargando…</p> : !lista.length ? <p className="muted">No hay auditores autorizados.</p> : (
        <ul className="qms-lista">
          {lista.map(a => { const [l, c] = estado(a); return (
            <li key={a.id} className="qms-socio">
              <div className="qms-socio-cab"><strong>{a.correo}</strong><span className={'qms-estado ' + c}>{l}</span></div>
              <div className="muted">{a.organismo || 'Sin organismo'} · hasta el {FECHA(a.vence)}</div>
              {!a.revocado_en ? <div className="qms-acciones"><button className="link" onClick={() => api.revocar(a.id).then(() => { onCambio(); onOk('Permiso revocado.') }).catch(onError)}><Icono n="close" />Revocar</button></div> : null}
            </li>) })}
        </ul>
      )}
    </div>
  )
}
