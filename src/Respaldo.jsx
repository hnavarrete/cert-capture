// El respaldo, A LA VISTA (6-oct-2026). Una clienta cargó semanas y nada llegó al servidor: el fallo solo se
// escribía en la consola. Este aviso va fijo debajo de la barra superior, sin abrir nada: cuántas versiones están
// respaldadas en el servidor, cuántas esperan en el equipo y, si algo falla, la causa en lenguaje llano y qué hacer.
// Y el registro encadenado del formulario, verificado contra el servidor (cert_verificar_cadena).
import React, { useEffect, useState } from 'react'
import { Icono } from './eudr-react/CertForm.jsx'
import { verificarCadena } from './engine.js'

const WHATSAPP_VG = '593967216547'
const vers = n => (n === 1 ? 'versión' : 'versiones')

/**
 * Qué decir del respaldo. Función pura: la usan la barra y «Mi bóveda».
 * @param {object} p - { status (del motor), conSesion, demo, slug, email }
 * @returns {{ nivel:'ok'|'info'|'warn'|'err', icono, titulo, detalle, accion:null|'login'|'flush'|'finca', whatsapp?:string }}
 */
export function estadoRespaldo({ status = {}, conSesion, demo, slug, email }) {
  const pend = (status.pending || 0) + (status.failed || 0)
  const ok = status.synced || 0
  const e = status.lastError || null
  const enEquipo = pend ? `${pend} ${vers(pend)} solo en este equipo.` : ''
  if (!conSesion) {
    return {
      nivel: 'warn', icono: 'lock', accion: 'login',
      titulo: demo ? 'Modo demo: lo que guarde queda solo en este equipo' : 'Inicie sesión para respaldar en el servidor',
      detalle: (demo ? 'Inicie sesión para respaldar en el servidor. ' : '') + (enEquipo || 'Nada se envía al servidor sin una cuenta.')
    }
  }
  if (status.offline || (e && e.tipo === 'sin_red')) {
    return {
      nivel: pend ? 'warn' : 'info', icono: 'hourglass_top', accion: status.offline ? null : 'flush',
      titulo: 'Sin conexión: se respaldará al volver',
      detalle: pend ? `${pend} ${vers(pend)} ${pend === 1 ? 'espera' : 'esperan'} en este equipo; no se ${pend === 1 ? 'pierde' : 'pierden'}.` : 'Lo que guarde se respaldará al volver la señal.'
    }
  }
  if (!slug || (e && e.tipo === 'sin_finca')) {
    return {
      nivel: 'warn', icono: 'report_problem', accion: 'finca',
      titulo: 'Elija su finca para respaldar',
      detalle: 'Arriba, en «Contexto del levantamiento». ' + (enEquipo || 'Sin finca no hay a dónde respaldar.')
    }
  }
  if (e && e.tipo === 'sin_permiso') {
    const msg = `Hola, soy ${email || 'un usuario de Certificaciones'}. Mi cuenta no tiene permiso de escritura en la finca ${slug}: no puedo respaldar en el servidor.`
    return {
      nivel: 'err', icono: 'report_problem', accion: 'flush',
      titulo: 'Su cuenta no tiene permiso de escritura en esta finca: avise a Visión Geográfica',
      detalle: (enEquipo || '') + ' Lo guardado no se pierde mientras tanto.',
      whatsapp: `https://wa.me/${WHATSAPP_VG}?text=${encodeURIComponent(msg)}`
    }
  }
  if (e && e.tipo === 'sin_sesion') {
    return {
      nivel: 'err', icono: 'lock', accion: 'login',
      titulo: 'Su sesión venció: vuelva a iniciar sesión para respaldar',
      detalle: enEquipo || 'Lo guardado sigue en este equipo.'
    }
  }
  if (e && pend) {
    return {
      nivel: 'err', icono: 'report_problem', accion: 'flush',
      titulo: 'No se pudo respaldar en el servidor',
      detalle: `Motivo: ${e.mensaje || 'sin detalle'}. ${enEquipo} Se vuelve a intentar sola; también puede tocar «Respaldar ahora».`
    }
  }
  if (pend) {
    return {
      nivel: 'info', icono: 'hourglass_top', accion: 'flush',
      titulo: `${pend} ${vers(pend)} por respaldar`,
      detalle: 'Se suben solas al servidor, con sus evidencias.'
    }
  }
  return {
    nivel: 'ok', icono: 'cloud_done', accion: null,
    titulo: ok ? 'Todo respaldado en el servidor' : 'Listo para respaldar',
    detalle: ok ? 'Lo que guarde se sube solo al servidor, con sus evidencias.' : 'Cada guardado se sube solo al servidor, con sus evidencias.'
  }
}

/** La barra de respaldo, fija debajo de la barra superior. */
export function RespaldoAviso({ status = {}, conSesion, demo, slug, email, onFlush, onLogin, onElegirFinca }) {
  const [respaldando, setRespaldando] = useState(false)
  const s = estadoRespaldo({ status, conSesion, demo, slug, email })
  const pend = (status.pending || 0) + (status.failed || 0)
  const ok = status.synced || 0
  const respaldar = async () => {
    if (!onFlush) return
    setRespaldando(true)
    try { await onFlush() } catch {} finally { setRespaldando(false) }
  }
  return (
    <div className={'respaldo ' + s.nivel} role={s.nivel === 'err' || s.nivel === 'warn' ? 'alert' : 'status'} aria-live="polite" data-respaldo={s.nivel}>
      <Icono n={s.icono} className="respaldo-ic" />
      <div className="respaldo-txt">
        <strong>{s.titulo}</strong>
        <span>{s.detalle}</span>
      </div>
      <div className="respaldo-cifras" aria-label="Estado del respaldo">
        <span className="cifra ok" title="Versiones respaldadas en el servidor">{ok} {ok === 1 ? 'respaldada' : 'respaldadas'}</span>
        <span className={'cifra ' + (pend ? 'pend' : 'cero')} title="Versiones que esperan en este equipo">{pend} {pend === 1 ? 'pendiente' : 'pendientes'}</span>
      </div>
      <div className="respaldo-acc">
        {s.accion === 'login' ? <button type="button" className="respaldo-btn" onClick={onLogin}>Iniciar sesión</button> : null}
        {s.accion === 'finca' && onElegirFinca ? <button type="button" className="respaldo-btn" onClick={onElegirFinca}>Elegir finca</button> : null}
        {s.whatsapp ? <a className="respaldo-btn sec" href={s.whatsapp} target="_blank" rel="noopener noreferrer">Avisar por WhatsApp</a> : null}
        {s.accion === 'flush' ? (
          <button type="button" className="respaldo-btn" onClick={respaldar} disabled={respaldando}>
            {respaldando ? 'Respaldando…' : 'Respaldar ahora'}
          </button>
        ) : null}
      </div>
    </div>
  )
}

/**
 * Integridad del registro encadenado de un formulario, verificada en el servidor.
 * 🔴 Frase permitida: «registro encadenado propio, verificable contra sí mismo». Nunca «inalterable», «a prueba de
 * fraude» ni «certificado»: la cadena prueba que lo guardado no cambió después, no que sea verdad.
 */
export function IntegridadCadena({ formKey, refrescar }) {
  const [r, setR] = useState(null)
  useEffect(() => {
    let on = true
    if (!formKey) return
    verificarCadena(formKey).then(x => { if (on) setR(x) }).catch(() => { if (on) setR(null) })
    return () => { on = false }
  }, [formKey, refrescar])
  if (!r || r.motivo || r.error) return null
  if (!r.total) {
    return (
      <div className="cadena vacia" data-cadena="vacia">
        <Icono n="link" />
        <span>Registro encadenado: este formulario aún no tiene versiones en el servidor.</span>
      </div>
    )
  }
  if (r.ok) {
    return (
      <div className="cadena ok" data-cadena="ok">
        <Icono n="verified" />
        <span><strong>Registro encadenado: íntegro ({r.total} {vers(r.total)})</strong>
          <small>Registro encadenado propio, verificable contra sí mismo.</small></span>
      </div>
    )
  }
  return (
    <div className="cadena roto" role="alert" data-cadena="roto">
      <Icono n="report_problem" />
      <span><strong>Registro encadenado: no cuadra a partir de una versión ({String(r.broken_at || '').slice(0, 8)}) de {r.total}</strong>
        <small>Registro encadenado propio, verificable contra sí mismo: una versión guardada no coincide con su sello. Avise a Visión Geográfica.</small></span>
    </div>
  )
}
