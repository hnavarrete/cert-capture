// Mi grupo — gestión de grupo de GlobalG.A.P. opción 2 (QMS v6.0), parte 1: registro interno de miembros (4.1.2.2),
// productores excluidos (4.1.2.2 b) y auditor externo en solo lectura. Encargo v2 de #15 (cadena de la pitahaya).
// El servidor es la fuente de verdad (funciones cert_qms_* de la migración 20261023000000); la pantalla solo ofrece lo
// que el nivel permite. En modo demo trabaja con una asociación sintética en memoria que aplica las MISMAS reglas.
import React, { useEffect, useMemo, useState } from 'react'
import { supabase } from './supabase.js'
import { Icono } from './eudr-react/CertForm.jsx'
import { CronogramaGrupo } from './AuditoriaInterna.jsx'
import { Incumplimientos } from './Incumplimientos.jsx'
import { ReclamosRetiro } from './ReclamosRetiro.jsx'
import { PUNTOS, calcular, faltantes, pidePlazo } from './qms-auditoria.js'

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
    revocar: (id) => rpc('cert_qms_revocar_auditor', { p_id: id }),
    // parte 2: auditoría interna de finca (migración 20261025000000)
    cronograma: (slug) => rpc('cert_qms_cronograma', { p_slug: slug }),
    planificar: (slug, miembro, fecha, inspector) => rpc('cert_qms_planificar', { p_slug: slug, p_miembro: miembro, p_fecha: fecha, p_inspector: inspector }),
    cancelar: (id, motivo) => rpc('cert_qms_cancelar_inspeccion', { p_id: id, p_motivo: motivo }),
    misInspecciones: () => rpc('cert_qms_mis_inspecciones'),
    enviar: (p) => rpc('cert_qms_enviar_inspeccion', { p }),
    informe: (id) => rpc('cert_qms_informe', { p_id: id }).then(f => (f || [])[0] || null),
    decidir: (id, decision, nombre, comentario) => rpc('cert_qms_decidir', { p_id: id, p_decision: decision, p_nombre: nombre, p_comentario: comentario || null }),
    // parte 3a: incumplimientos y sanciones (migración 20261026000000)
    ncLista: (slug) => rpc('cert_qms_nc_lista', { p_slug: slug }),
    ncGuardar: (p) => rpc('cert_qms_nc_guardar', { p }),
    ncCerrar: (id, evidencia, nombre) => rpc('cert_qms_nc_cerrar', { p_id: id, p_evidencia: evidencia, p_nombre: nombre }),
    sanciones: (slug) => rpc('cert_qms_sanciones', { p_slug: slug }),
    sancionar: (slug, miembro, tipo, motivo, nombre, nc, producto) => rpc('cert_qms_sancionar',
      { p_slug: slug, p_miembro: miembro, p_tipo: tipo, p_motivo: motivo, p_nombre: nombre, p_nc: nc || null, p_producto: producto || null }),
    avisoCb: (id, fecha) => rpc('cert_qms_sancion_aviso_cb', { p_id: id, p_fecha: fecha }),
    levantar: (id, motivo, nombre) => rpc('cert_qms_sancion_levantar', { p_id: id, p_motivo: motivo, p_nombre: nombre }),
    // parte 3b: reclamos, retiro y balance de masas (migración 20261026010000)
    reclamos: (slug) => rpc('cert_qms_reclamos', { p_slug: slug }),
    reclamoGuardar: (p) => rpc('cert_qms_reclamo_guardar', { p }),
    reclamoAviso: (id, fecha) => rpc('cert_qms_reclamo_aviso_cb', { p_id: id, p_fecha: fecha }),
    reclamoCerrar: (id, conclusion, nombre) => rpc('cert_qms_reclamo_cerrar', { p_id: id, p_conclusion: conclusion, p_nombre: nombre }),
    retiros: (slug) => rpc('cert_qms_retiros', { p_slug: slug }),
    retiroGuardar: (p) => rpc('cert_qms_retiro_guardar', { p }),
    retiroCerrar: (id, nombre) => rpc('cert_qms_retiro_cerrar', { p_id: id, p_nombre: nombre }),
    balances: (slug) => rpc('cert_qms_balances', { p_slug: slug }),
    balanceRegistrar: (p) => rpc('cert_qms_balance_registrar', { p })
  }
}
/** La misma API para la pantalla del auditor interno (Mis auditorías), fuera de «Mi grupo». */
export const apiQms = (demo) => (demo ? apiDemo() : apiServidor())

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
    auditores: [{ id: 'demo-aud-1', client_slug: 'demo-pitahaya', correo: 'auditora@certificador.demo', organismo: 'Organismo certificador demo', vence: masDias(60), otorgado_en: new Date().toISOString(), revocado_en: null }],
    ...incumplimientosDemo(s, inspeccionesDemo(s))
  }
}

// Como el disparador del servidor (_qms_nc_desde_informe): un incumplimiento por cada «no cumple» del informe enviado.
function ncsDesde(i) {
  return (i.resultados || []).filter(x => x.resultado === 'no_cumple').map(x => ({
    id: `demo-nc-${i.id}-${x.code}`, client_slug: i.client_slug, miembro_id: i.miembro_id, socio_nombre: i.socio_nombre, nivel: 'socio',
    origen: 'auditoria_interna', inspeccion_id: i.id, code: x.code, gravedad: (PUNTOS.find(p => p.code === x.code) || {}).nivel,
    descripcion: (x.comentario || '').trim() || 'No cumple ' + x.code, accion_correctiva: null, responsable: null, plazo: x.plazo,
    estado: 'abierta', creada_en: i.enviada_en || new Date().toISOString() }))
}
function incumplimientosDemo(socios, inspecciones) {
  const nc = inspecciones.filter(i => i.estado !== 'planificada').flatMap(ncsDesde)
  // la de hace 200 días ya se cerró; de la reciente, una ya está en curso
  Object.assign(nc[0], { estado: 'cerrada', accion_correctiva: 'Registro diario de capacitaciones', responsable: 'Técnico del grupo (demo)',
    cierre_evidencia: 'Registro de 30 días revisado en la finca (demo)', cerrada_por_nombre: 'Responsable de calidad (demo)',
    cerrada_en: new Date(Date.now() - 170 * 864e5).toISOString() })
  Object.assign(nc[1], { estado: 'en_curso', accion_correctiva: 'Capacitar al personal de cosecha', responsable: 'Técnico del grupo (demo)' })
  const s5 = socios[4], s6 = socios[5]
  nc.push({ id: 'demo-nc-ext', client_slug: 'demo-pitahaya', miembro_id: null, socio_nombre: null, nivel: 'qms', origen: 'auditoria_externa',
    inspeccion_id: null, code: null, gravedad: null, descripcion: 'El procedimiento de retiro de producto no se probó este año (demo)',
    accion_correctiva: null, responsable: null, plazo: masDias(-3), estado: 'abierta', creada_en: new Date(Date.now() - 20 * 864e5).toISOString() })
  nc.push({ id: 'demo-nc-s5', client_slug: 'demo-pitahaya', miembro_id: s5.id, socio_nombre: s5.nombre, nivel: 'socio', origen: 'qms',
    inspeccion_id: null, code: null, gravedad: null, descripcion: s5.estado_motivo, accion_correctiva: 'Completar el registro de aplicaciones del año',
    responsable: s5.nombre, plazo: masDias(10), estado: 'en_curso', creada_en: new Date(Date.now() - 12 * 864e5).toISOString() })
  const sanciones = [
    { id: 'demo-san-1', client_slug: 'demo-pitahaya', miembro_id: s5.id, socio_nombre: s5.nombre, nc_id: 'demo-nc-s5', tipo: 'suspension',
      producto: 'pitahaya amarilla', motivo: s5.estado_motivo, decidida_por_nombre: 'Responsable de calidad (demo)',
      decidida_en: new Date(Date.now() - 12 * 864e5).toISOString(), aviso_cb_en: masDias(-11), levantada_en: null },
    { id: 'demo-san-2', client_slug: 'demo-pitahaya', miembro_id: s6.id, socio_nombre: s6.nombre, nc_id: null, tipo: 'cancelacion',
      producto: null, motivo: s6.estado_motivo, decidida_por_nombre: 'Directiva (demo)', decidida_en: s6.excluido_en, aviso_cb_en: '2026-06-03', levantada_en: null }
  ]
  const hace = (d) => new Date(Date.now() - d * 864e5).toISOString()
  const reclamos = [
    { id: 'demo-rec-1', recibido_en: masDias(-40), origen: 'cliente', miembro_id: s6.id, socio_nombre: s6.nombre, tema: 'inocuidad',
      descripcion: 'Residuo de plaguicida sobre el límite en un embarque (demo)', investigacion: 'Se revisó el registro de aplicaciones del lote (demo)',
      seguimiento: 'Análisis de residuos repetido (demo)', estado: 'cerrado', aviso_cb_en: masDias(-39), requiere_aviso: true,
      conclusion: 'Producto no autorizado en la finca: socio cancelado y lote retirado (demo)', cerrado_por_nombre: 'Responsable de calidad (demo)', cerrado_en: hace(30) },
    { id: 'demo-rec-2', recibido_en: masDias(-4), origen: 'cliente', miembro_id: null, socio_nombre: null, tema: 'calidad',
      descripcion: 'Fruta con calibre menor al pedido (demo)', investigacion: null, seguimiento: null, estado: 'recibido', aviso_cb_en: null,
      requiere_aviso: false, conclusion: null, cerrado_por_nombre: null, cerrado_en: null }
  ]
  const retiros = [
    { id: 'demo-ret-1', tipo: 'simulacro', iniciado_en: hace(300), terminado_en: new Date(Date.now() - 300 * 864e5 + 160 * 60e3).toISOString(),
      producto: 'pitahaya amarilla', lotes: 'L-DEMO-041, L-DEMO-042', motivo: 'Simulacro anual: residuo sobre el límite (demo)',
      decide_nombre: 'Responsable de calidad (demo)', clientes_avisados: 'Exportadora demo (correo)', aviso_cb_en: null, unidad: 'kg',
      cantidad_afectada: 1200, cantidad_localizada: 1176, resultado: '98 % localizado en 2 h 40 min (demo)', estado: 'cerrado', cerrado_por_nombre: 'Responsable de calidad (demo)' }
  ]
  const balances = [
    { id: 'demo-bal-1', producto: 'pitahaya amarilla', desde: masDias(-400), hasta: masDias(-36), unidad: 'kg', entradas_cert: 152000, entradas_no_cert: 8000,
      salidas_cert: 149500, salidas_no_cert: 8000, existencias_cert: 2500, existencias_no_cert: 0, conclusion: 'Cuadra (demo)',
      fuente: 'VG Custody · balance de masas', hecho_por_nombre: 'Responsable de calidad (demo)', hecho_en: hace(35) }
  ]
  return { inspecciones, nc, sanciones, reclamos, retiros, balances }
}

// Firma sintética para la demo (un trazo dibujado; nunca la de una persona real).
function firmaDemo(semilla) {
  try {
    const c = document.createElement('canvas'); c.width = 360; c.height = 120
    const g = c.getContext('2d'); g.strokeStyle = '#0A1128'; g.lineWidth = 2.4; g.lineCap = 'round'; g.beginPath()
    for (let x = 20; x <= 330; x += 6) { const y = 64 + Math.sin(x / (14 + semilla)) * 22 * Math.sin(x / 90); if (x === 20) g.moveTo(x, y); else g.lineTo(x, y) }
    g.stroke(); return c.toDataURL('image/png')
  } catch { return null }
}
// Resultados sintéticos con la lista oficial: `nc` puntos Minor no cumplen (con plazo); el resto cumple.
function resultadosDemo(nc, fecha) {
  let k = 0
  return PUNTOS.map(p => {
    const falla = p.nivel === 'Minor' && k++ < nc
    return { code: p.code, resultado: falla ? 'no_cumple' : 'cumple',
      comentario: falla ? 'Registro incompleto en la visita (demo)' : p.nivel === 'Major' ? 'Verificado en la finca (demo)' : null,
      plazo: falla ? fecha : null }
  })
}
const comoMapa = (arr) => Object.fromEntries((arr || []).map(x => [x.code, x]))
// La demo se porta como el servidor también sin señal: lo que va al servidor falla y queda en el equipo.
const sinSenal = () => typeof navigator !== 'undefined' && navigator.onLine === false
function inspeccionesDemo(socios) {
  const base = (m, extra) => ({ client_slug: 'demo-pitahaya', miembro_id: m.id, checklist: 'globalgap_fv_smart', socio_identificacion: m.identificacion,
    socio_nombre: m.nombre, productos: m.productos, sitios: m.sitios, decision: null, cancelada_motivo: null, ...extra })
  const hecha = (m, id, dias, nc, inspector, extra) => {
    const ini = new Date(Date.now() - dias * 864e5); ini.setHours(9, 10, 0, 0); const fin = new Date(ini.getTime() + 95 * 60e3)
    const resultados = resultadosDemo(nc, local(new Date(ini.getTime() + 30 * 864e5)))
    return base(m, { id, fecha_plan: local(ini), inspector_correo: inspector, inspector_nombre: 'Técnico de campo (demo)', estado: 'enviada',
      inicio: ini.toISOString(), fin: fin.toISOString(), firmante_nombre: m.nombre, firma_socio: firmaDemo(3), firma_inspector: firmaDemo(7),
      resultados, cumplimiento: calcular(comoMapa(resultados)), enviada_en: fin.toISOString(), ...extra })
  }
  return [
    hecha(socios[0], 'demo-ai-1', 200, 1, 'tecnico@demo', { estado: 'decidida', decision: 'conforme', decidida_por_nombre: 'Responsable de calidad (demo)', decidida_en: new Date(Date.now() - 198 * 864e5).toISOString() }),
    hecha(socios[2], 'demo-ai-2', 2, 3, 'tecnico@demo'),
    base(socios[1], { id: 'demo-ai-3', fecha_plan: hoy(), inspector_correo: 'demo@vg.local', estado: 'planificada' })
  ]
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
    revocar: (id) => { DEMO.auditores.find(a => a.id === id).revocado_en = new Date().toISOString(); return pausa(null) },
    // parte 2: las MISMAS reglas que el servidor (cert_qms_* de 20261025000000)
    cronograma: () => pausa(DEMO.inspecciones.map(i => ({ ...i, socio_estado: (DEMO.miembros.find(m => m.id === i.miembro_id) || {}).estado }))
      .sort((a, b) => (a.estado === 'cancelada') - (b.estado === 'cancelada') || b.fecha_plan.localeCompare(a.fecha_plan))),
    planificar: (slug, miembro, fecha, inspector) => {
      const m = DEMO.miembros.find(x => x.id === miembro)
      if (!m) return Promise.reject(new Error('ese socio no es de este grupo'))
      if (m.estado === 'excluido') return Promise.reject(new Error('un socio excluido no se audita; primero se readmite'))
      if (!fecha) return Promise.reject(new Error('la auditoría necesita una fecha dentro del próximo año'))
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test((inspector || '').trim())) return Promise.reject(new Error('falta el correo del auditor interno'))
      if (DEMO.inspecciones.some(i => i.miembro_id === miembro && i.estado === 'planificada')) return Promise.reject(new Error('qms_insp_una_abierta'))
      const id = 'demo-ai-' + Date.now()
      DEMO.inspecciones.push({ id, client_slug: slug, miembro_id: m.id, checklist: 'globalgap_fv_smart', fecha_plan: fecha,
        inspector_correo: inspector.trim().toLowerCase(), estado: 'planificada', socio_nombre: m.nombre })
      return pausa(id)
    },
    cancelar: (id, motivo) => {
      const i = DEMO.inspecciones.find(x => x.id === id)
      if (i.estado !== 'planificada') return Promise.reject(new Error('solo se cancela una auditoría que todavía no se hizo'))
      if (!(motivo || '').trim()) return Promise.reject(new Error('cancelar una auditoría exige el motivo'))
      Object.assign(i, { estado: 'cancelada', cancelada_motivo: motivo.trim() }); return pausa(null)
    },
    misInspecciones: () => sinSenal() ? Promise.reject(new Error('Failed to fetch')) : pausa(DEMO.inspecciones.filter(i => i.estado === 'planificada' && i.inspector_correo === 'demo@vg.local').map(i => {
      const m = DEMO.miembros.find(x => x.id === i.miembro_id)
      return { id: i.id, client_slug: i.client_slug, checklist: i.checklist, fecha_plan: i.fecha_plan, socio_identificacion: m.identificacion,
        socio_nombre: m.nombre, direccion: m.direccion, productos: m.productos, sitios: m.sitios }
    })),
    enviar: (p) => {
      if (sinSenal()) return Promise.reject(new Error('Failed to fetch'))   // como el servidor: sin señal no llega
      const i = DEMO.inspecciones.find(x => x.id === p.id)
      if (!i) return Promise.reject(new Error('esa auditoría no existe'))
      if (i.estado === 'cancelada') return Promise.reject(new Error('esta auditoría ya no está abierta (cancelada)'))
      if (i.estado !== 'planificada') return pausa(i.cumplimiento)
      const mapa = comoMapa(p.resultados); const f = faltantes(mapa)
      if (f.sinResultado.length) return Promise.reject(new Error(`QMS: faltan ${f.sinResultado.length} puntos de control sin resultado`))
      if (f.sinComentario.length) return Promise.reject(new Error(`QMS: ${f.sinComentario.length} puntos necesitan comentario`))
      if (f.sinPlazo.length) return Promise.reject(new Error(`QMS: ${f.sinPlazo.length} incumplimientos sin plazo para la acción correctiva`))
      if (!p.firma_socio || !p.firma_inspector) return Promise.reject(new Error('faltan las firmas del socio y del auditor'))
      const m = DEMO.miembros.find(x => x.id === i.miembro_id)
      Object.assign(i, { ...p, estado: 'enviada', socio_identificacion: m.identificacion, socio_nombre: m.nombre, productos: m.productos,
        sitios: m.sitios, cumplimiento: calcular(mapa), enviada_en: new Date().toISOString() })
      DEMO.nc.push(...ncsDesde(i))   // como el disparador del servidor
      return pausa(i.cumplimiento)
    },
    informe: (id) => pausa({ ...DEMO.inspecciones.find(x => x.id === id) }),
    decidir: (id, decision, nombre, comentario) => {
      const i = DEMO.inspecciones.find(x => x.id === id)
      if (i.estado !== 'enviada') return Promise.reject(new Error('esta auditoría no espera decisión'))
      if (i.inspector_correo === 'demo@vg.local') return Promise.reject(new Error('quien hizo la auditoría no la aprueba (QMS 12.5 a)'))
      if (!(nombre || '').trim()) return Promise.reject(new Error('falta el nombre de quien aprueba (05.02 g xi)'))
      if (decision === 'conforme' && !i.cumplimiento.cumple) return Promise.reject(new Error('no se puede declarar conforme: el cálculo no cumple'))
      if (decision === 'no_conforme' && !(comentario || '').trim()) return Promise.reject(new Error('declarar no conforme exige el motivo'))
      Object.assign(i, { estado: 'decidida', decision, decidida_por_nombre: nombre.trim(), decision_comentario: (comentario || '').trim() || null, decidida_en: new Date().toISOString() })
      const m = DEMO.miembros.find(x => x.id === i.miembro_id); const d = local(new Date(i.inicio))
      if (!m.ultima_auditoria_interna || m.ultima_auditoria_interna < d) m.ultima_auditoria_interna = d
      return pausa(null)
    },
    // parte 3a: las MISMAS reglas que el servidor (cert_qms_nc_* y cert_qms_sancion* de 20261026000000)
    ncLista: () => pausa([...DEMO.nc].sort((a, b) => (a.estado === 'cerrada') - (b.estado === 'cerrada') || a.plazo.localeCompare(b.plazo))),
    ncGuardar: (p) => {
      if (!p.plazo) return Promise.reject(new Error('el incumplimiento necesita un plazo para la acción correctiva (05.03 b)'))
      if (!p.id) {
        if (p.origen === 'auditoria_interna') return Promise.reject(new Error('los de la auditoría interna los crea el informe, no se cargan a mano'))
        const m = DEMO.miembros.find(x => x.id === p.miembro_id)
        DEMO.nc.push({ id: 'demo-nc-' + Date.now(), client_slug: 'demo-pitahaya', miembro_id: m ? m.id : null, socio_nombre: m ? m.nombre : null,
          nivel: m ? 'socio' : 'qms', origen: p.reclamo_id ? 'reclamo' : p.origen, reclamo_id: p.reclamo_id || null, inspeccion_id: null, code: null, gravedad: null, descripcion: (p.descripcion || '').trim(),
          accion_correctiva: (p.accion_correctiva || '').trim() || null, responsable: (p.responsable || '').trim() || null, plazo: p.plazo,
          estado: p.en_curso ? 'en_curso' : 'abierta', creada_en: new Date().toISOString() })
        return pausa('ok')
      }
      const n = DEMO.nc.find(x => x.id === p.id)
      if (n.estado === 'cerrada') return Promise.reject(new Error('QMS: este incumplimiento ya está cerrado'))
      Object.assign(n, { accion_correctiva: (p.accion_correctiva || '').trim() || null, responsable: (p.responsable || '').trim() || null, plazo: p.plazo,
        estado: p.en_curso ? 'en_curso' : n.estado, descripcion: n.origen === 'auditoria_interna' ? n.descripcion : ((p.descripcion || '').trim() || n.descripcion) })
      return pausa(n.id)
    },
    ncCerrar: (id, evidencia, nombre) => {
      const n = DEMO.nc.find(x => x.id === id)
      if (!(n.accion_correctiva || '').trim() || !(n.responsable || '').trim()) return Promise.reject(new Error('antes de cerrar, anote la acción correctiva y su responsable (05.03 c)'))
      if (!(evidencia || '').trim() || !(nombre || '').trim()) return Promise.reject(new Error('cerrar exige la evidencia y el nombre de quien verificó'))
      Object.assign(n, { estado: 'cerrada', cierre_evidencia: evidencia.trim(), cerrada_por_nombre: nombre.trim(), cerrada_en: new Date().toISOString() })
      return pausa(null)
    },
    sanciones: () => pausa(DEMO.sanciones.map(s => { const n = DEMO.nc.find(x => x.id === s.nc_id); return { ...s, nc_descripcion: n?.descripcion, nc_estado: n?.estado } })
      .sort((a, b) => b.decidida_en.localeCompare(a.decidida_en))),
    sancionar: (slug, miembro, tipo, motivo, nombre, nc, producto) => {
      const m = DEMO.miembros.find(x => x.id === miembro)
      if (m.estado === 'excluido') return Promise.reject(new Error('ese socio ya está excluido'))
      if (tipo === 'suspension' && m.estado === 'suspendido') return Promise.reject(new Error('ese socio ya está suspendido'))
      if (!(motivo || '').trim() || !(nombre || '').trim()) return Promise.reject(new Error('la sanción necesita el motivo y el nombre de quien decide'))
      DEMO.sanciones.push({ id: 'demo-san-' + Date.now(), client_slug: slug, miembro_id: m.id, socio_nombre: m.nombre, nc_id: nc || null, tipo,
        producto: (producto || '').trim() || null, motivo: motivo.trim(), decidida_por_nombre: nombre.trim(), decidida_en: new Date().toISOString(),
        aviso_cb_en: null, levantada_en: null })
      if (tipo !== 'advertencia') {
        const de = m.estado; Object.assign(m, { estado: tipo === 'suspension' ? 'suspendido' : 'excluido', estado_motivo: motivo.trim(),
          excluido_en: tipo === 'cancelacion' ? new Date().toISOString() : null }); hist(m, de, m.estado)
      }
      return pausa('ok')
    },
    avisoCb: (id, fecha) => {
      if (!fecha || fecha > hoy()) return Promise.reject(new Error('la fecha del aviso no puede estar en el futuro'))
      DEMO.sanciones.find(x => x.id === id).aviso_cb_en = fecha; return pausa(null)
    },
    levantar: (id, motivo, nombre) => {
      const s = DEMO.sanciones.find(x => x.id === id); const n = DEMO.nc.find(x => x.id === s.nc_id)
      if (n && n.estado !== 'cerrada') return Promise.reject(new Error('la suspensión se levanta cuando su incumplimiento está cerrado (05.03 h)'))
      if (!(motivo || '').trim() || !(nombre || '').trim()) return Promise.reject(new Error('levantar exige el motivo y el nombre de quien decide'))
      Object.assign(s, { levantada_en: new Date().toISOString(), levantada_motivo: motivo.trim(), levantada_por_nombre: nombre.trim() })
      const m = DEMO.miembros.find(x => x.id === s.miembro_id)
      if (m.estado === 'suspendido') { Object.assign(m, { estado: 'activo', estado_motivo: motivo.trim() }); hist(m, 'suspendido', 'activo') }
      return pausa(null)
    },
    // parte 3b: las MISMAS reglas que el servidor (cert_qms_reclamo*, cert_qms_retiro*, cert_qms_balance* de 20261026010000)
    reclamos: () => pausa(DEMO.reclamos.map(r => ({ ...r, nc_abiertas: DEMO.nc.filter(n => n.reclamo_id === r.id && n.estado !== 'cerrada').length }))
      .sort((a, b) => (a.estado === 'cerrado') - (b.estado === 'cerrado') || b.recibido_en.localeCompare(a.recibido_en))),
    reclamoGuardar: (p) => {
      if (!p.id) {
        if (!p.recibido_en || p.recibido_en > hoy()) return Promise.reject(new Error('el reclamo necesita la fecha en que se recibió (no futura)'))
        const m = DEMO.miembros.find(x => x.id === p.miembro_id); const inv = (p.investigacion || '').trim()
        DEMO.reclamos.push({ id: 'demo-rec-' + Date.now(), recibido_en: p.recibido_en, origen: p.origen, miembro_id: m ? m.id : null, socio_nombre: m ? m.nombre : null,
          tema: p.tema, descripcion: (p.descripcion || '').trim(), investigacion: inv || null, seguimiento: (p.seguimiento || '').trim() || null,
          estado: inv ? 'en_investigacion' : 'recibido', aviso_cb_en: null, requiere_aviso: ['inocuidad', 'trabajadores', 'ambiente'].includes(p.tema),
          conclusion: null, cerrado_por_nombre: null, cerrado_en: null })
        return pausa('ok')
      }
      const r = DEMO.reclamos.find(x => x.id === p.id)
      if (r.estado === 'cerrado') return Promise.reject(new Error('QMS: este registro ya está cerrado'))
      const inv = (p.investigacion || '').trim()
      Object.assign(r, { investigacion: inv || null, seguimiento: (p.seguimiento || '').trim() || null, estado: inv ? 'en_investigacion' : 'recibido' })
      return pausa(r.id)
    },
    reclamoAviso: (id, fecha) => {
      const r = DEMO.reclamos.find(x => x.id === id)
      if (r.aviso_cb_en) return Promise.reject(new Error('el aviso de este reclamo ya está anotado'))
      if (!fecha || fecha > hoy()) return Promise.reject(new Error('la fecha del aviso no puede estar en el futuro'))
      r.aviso_cb_en = fecha; return pausa(null)
    },
    reclamoCerrar: (id, conclusion, nombre) => {
      const r = DEMO.reclamos.find(x => x.id === id)
      if (!(r.investigacion || '').trim()) return Promise.reject(new Error('antes de cerrar, anote la investigación (QMS 04 b)'))
      if (r.requiere_aviso && !r.aviso_cb_en) return Promise.reject(new Error('un reclamo de inocuidad, trabajadores o ambiente se cierra con el aviso al organismo certificador (QMS 04 e)'))
      if (!(conclusion || '').trim() || !(nombre || '').trim()) return Promise.reject(new Error('cerrar exige la conclusión y el nombre de quien cierra'))
      Object.assign(r, { estado: 'cerrado', conclusion: conclusion.trim(), cerrado_por_nombre: nombre.trim(), cerrado_en: new Date().toISOString() })
      return pausa(null)
    },
    retiros: () => pausa([...DEMO.retiros].sort((a, b) => (a.estado === 'cerrado') - (b.estado === 'cerrado') || b.iniciado_en.localeCompare(a.iniciado_en))),
    retiroGuardar: (p) => {
      if (p.aviso_cb_en && p.aviso_cb_en > hoy()) return Promise.reject(new Error('la fecha del aviso no puede estar en el futuro'))
      const num = (v) => (v === '' || v == null ? null : Number(v))
      if (!p.id) {
        if (!p.iniciado_en || new Date(p.iniciado_en) > new Date(Date.now() + 15 * 60e3)) return Promise.reject(new Error('el retiro necesita su fecha y hora de inicio (no futura)'))
        DEMO.retiros.push({ id: 'demo-ret-' + Date.now(), tipo: p.tipo, iniciado_en: new Date(p.iniciado_en).toISOString(), terminado_en: null,
          producto: (p.producto || '').trim(), lotes: (p.lotes || '').trim() || null, motivo: (p.motivo || '').trim(), decide_nombre: (p.decide_nombre || '').trim(),
          clientes_avisados: null, aviso_cb_en: null, unidad: null, cantidad_afectada: null, cantidad_localizada: null, resultado: null, estado: 'en_curso' })
        return pausa('ok')
      }
      const r = DEMO.retiros.find(x => x.id === p.id)
      if (r.estado === 'cerrado') return Promise.reject(new Error('QMS: este registro ya está cerrado'))
      Object.assign(r, { lotes: (p.lotes || '').trim() || null, clientes_avisados: (p.clientes_avisados || '').trim() || null, aviso_cb_en: r.aviso_cb_en || p.aviso_cb_en || null,
        unidad: p.unidad || null, cantidad_afectada: num(p.cantidad_afectada), cantidad_localizada: num(p.cantidad_localizada), resultado: (p.resultado || '').trim() || null })
      return pausa(r.id)
    },
    retiroCerrar: (id, nombre) => {
      const r = DEMO.retiros.find(x => x.id === id)
      if (!r.unidad || r.cantidad_afectada == null || r.cantidad_localizada == null) return Promise.reject(new Error('antes de cerrar, anote la conciliación: cantidad afectada y cantidad localizada (QMS 07 b)'))
      if (!(r.clientes_avisados || '').trim()) return Promise.reject(new Error('antes de cerrar, anote a qué clientes se avisó (QMS 07 b)'))
      if (r.tipo === 'real' && !r.aviso_cb_en) return Promise.reject(new Error('un retiro real se cierra con el aviso al organismo certificador (QMS 07 b)'))
      if (!(r.resultado || '').trim() || !(nombre || '').trim()) return Promise.reject(new Error('cerrar exige el resultado y el nombre de quien cierra'))
      Object.assign(r, { estado: 'cerrado', terminado_en: new Date().toISOString(), cerrado_por_nombre: nombre.trim() }); return pausa(null)
    },
    balances: () => pausa([...DEMO.balances]),
    balanceRegistrar: (p) => {
      if (!p.desde || !p.hasta || p.hasta < p.desde || p.hasta > hoy()) return Promise.reject(new Error('el balance necesita un periodo válido que ya terminó'))
      DEMO.balances.unshift({ ...p, id: 'demo-bal-' + Date.now(), hecho_en: new Date().toISOString() }); return pausa('ok')
    }
  }
}

// Mensajes del servidor → texto para la persona (sin códigos).
export function mensaje(e) {
  const t = String(e?.message || e || '')
  if (/qms_insp_una_abierta/i.test(t)) return 'Ese socio ya tiene una auditoría interna planificada. Para planificar otra, primero se cancela esa.'
  if (/quien hizo la auditoría/i.test(t)) return 'Usted hizo esta auditoría: la aprueba otra persona de calidad o el responsable del QMS (QMS 12.5 a).'
  if (/unique|duplicate|ya está registrada/i.test(t)) return 'Esa cédula o RUC ya está registrada en el grupo.'
  if (/qms_auditores_vence_max_un_anio|un año como máximo/i.test(t)) return 'El permiso de un auditor vence en un año como máximo.'
  if (/qms_miembros_identificacion_check/i.test(t)) return 'La cédula debe tener 10 dígitos, o 13 si es RUC.'
  if (/ggn_check/i.test(t)) return 'El GGN tiene 13 dígitos.'
  if (/sin acceso|solo la directiva|sin permiso|el cronograma lo ven|los incumplimientos los ven|las sanciones las ven|los reclamos los ven|los retiros los ven|los balances los ven/i.test(t)) return 'Su rol no permite esta acción en el grupo.'
  if (/Failed to fetch|NetworkError/i.test(t)) return 'Sin conexión: «Mi grupo» necesita señal para guardar. La auditoría en la finca, en cambio, se hace sin señal.'
  return t || 'No se pudo completar.'
}

// CSV para entregar el registro al auditor (4.1.2.2). Una celda que empieza con = + - @, tabulador o retorno —también
// después de espacios: Excel los salta— se neutraliza con un apóstrofo (inyección de fórmulas en Excel).
function csvRegistro(socios) {
  const celda = (v) => { let s = v == null ? '' : String(v); if (/^[\s]*[=+\-@\t\r]/.test(s)) s = "'" + s; return '"' + s.replace(/"/g, '""') + '"' }
  const cab = ['Cédula/RUC', 'Socio', 'Teléfono', 'Correo', 'Dirección', 'Productos', 'Área total (ha)', 'Sitios', 'Certificador', 'GGN',
    'Estado interno', 'Motivo del estado', 'Fecha de ingreso', 'Contrato', 'Última auditoría interna']
  const filas = socios.map(m => [m.identificacion, m.nombre, m.telefono, m.correo, m.direccion,
    (m.productos || []).map(p => `${p.cultivo} ${p.area_ha} ha`).join('; '), areaTotal(m).toFixed(2),
    (m.sitios || []).map(s => `${s.nombre} ${s.area_ha} ha${s.certificado ? ' (certificado)' : ' (no certificado)'}`).join('; '),
    m.certificador, m.ggn, (ESTADOS[m.estado] || {}).label || m.estado, m.estado_motivo, m.fecha_ingreso,
    [m.contrato_fecha, m.contrato_ref].filter(Boolean).join(' · '), m.ultima_auditoria_interna])
  return '﻿' + [cab, ...filas].map(f => f.map(celda).join(';')).join('\r\n')
}

export default function Grupo({ demo = false, onClose, pantallaCompleta = false, email = null }) {
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
            <button role="tab" aria-selected={tab === 'auditorias'} className={'chip ' + (tab === 'auditorias' ? 'sel' : '')} onClick={() => setTab('auditorias')}><Icono n="fact_check" className="ic" />Auditorías internas</button>
            <button role="tab" aria-selected={tab === 'incumplimientos'} className={'chip ' + (tab === 'incumplimientos' ? 'sel' : '')} onClick={() => setTab('incumplimientos')}><Icono n="report" className="ic" />Incumplimientos</button>
            <button role="tab" aria-selected={tab === 'reclamos'} className={'chip ' + (tab === 'reclamos' ? 'sel' : '')} onClick={() => setTab('reclamos')}><Icono n="inventory_2" className="ic" />Reclamos y retiro</button>
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
          ) : tab === 'reclamos' ? (
            <ReclamosRetiro slug={slug} gestiona={gestiona} api={api} socios={socios || []} onOk={ok} />
          ) : tab === 'incumplimientos' ? (
            <Incumplimientos slug={slug} gestiona={gestiona} api={api} socios={socios || []}
              onSocios={cargarSocios} onOk={ok} onError={e => setError(mensaje(e))} />
          ) : tab === 'auditorias' ? (
            <CronogramaGrupo slug={slug} gestiona={gestiona} api={api} socios={socios || []} email={email}
              onSocios={cargarSocios} onOk={ok} onError={e => setError(mensaje(e))} />
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
