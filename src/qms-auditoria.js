// Auditoría interna de finca (GlobalG.A.P. QMS v6.0, 05.02): la lista oficial de puntos, el cálculo del cumplimiento
// y el almacén del equipo para trabajar SIN SEÑAL. El servidor (migración 20261025000000) repite las mismas reglas con su
// propia copia de los niveles y es quien decide; aquí se calculan para avisar en la finca, antes de enviar.
import Dexie from 'dexie'
import bundle from './schemas.bundle.json'

export const CHECKLIST = 'globalgap_fv_smart'
const schema = bundle.schemas.find(s => s.form_key === CHECKLIST)
export const FUENTE = schema.fuente_normativa
// [{ code, nivel, label, criterio, seccion }] en el orden oficial
export const PUNTOS = schema.secciones.flatMap(sec => sec.campos.filter(c => c.tipo === 'control_point')
  .map(c => ({ code: c.code, nivel: c.nivel, label: c.label, criterio: c.criterio, seccion: sec.titulo })))
export const SECCIONES = [...new Set(PUNTOS.map(p => p.seccion))]
const NIVEL = Object.fromEntries(PUNTOS.map(p => [p.code, p.nivel]))

export const RESULTADOS = { cumple: 'Cumple', no_cumple: 'No cumple', no_aplica: 'No aplica' }

// 05.02 g vii: comentario en los Major siempre, y en los Minor que no cumplen o no aplican. Las recomendaciones, no.
export const pideComentario = (nivel, resultado) => !!resultado && (nivel === 'Major' || (nivel === 'Minor' && resultado !== 'cumple'))
// 05.02 g viii: todo incumplimiento (salvo una recomendación) lleva plazo para la acción correctiva.
export const pidePlazo = (nivel, resultado) => resultado === 'no_cumple' && nivel !== 'Recommendation'

/** Lo que le falta al informe para poder enviarse. r = { [code]: { resultado, comentario, plazo } } */
export function faltantes(r) {
  const f = { sinResultado: [], sinComentario: [], sinPlazo: [] }
  for (const p of PUNTOS) {
    const x = r[p.code] || {}
    if (!x.resultado) f.sinResultado.push(p.code)
    else {
      if (pideComentario(p.nivel, x.resultado) && !(x.comentario || '').trim()) f.sinComentario.push(p.code)
      if (pidePlazo(p.nivel, x.resultado) && !x.plazo) f.sinPlazo.push(p.code)
    }
  }
  f.total = f.sinResultado.length + f.sinComentario.length + f.sinPlazo.length
  return f
}

/** Mismo cálculo que compliance.fn_qms_cumplimiento: Major 100 % y Minor ≥ 95 % de los aplicables. */
export function calcular(r) {
  const c = { major_aplicables: 0, major_no_cumple: 0, minor_aplicables: 0, minor_no_cumple: 0, recom_aplicables: 0, recom_no_cumple: 0, no_aplica: 0 }
  for (const p of PUNTOS) {
    const res = (r[p.code] || {}).resultado
    if (!res) continue
    if (res === 'no_aplica') { c.no_aplica++; continue }
    const k = p.nivel === 'Major' ? 'major' : p.nivel === 'Minor' ? 'minor' : 'recom'
    c[k + '_aplicables']++
    if (res === 'no_cumple') c[k + '_no_cumple']++
  }
  const pct = (ap, nc) => (ap === 0 ? 100 : Math.round(1000 * (ap - nc) / ap) / 10)
  c.pct_major = pct(c.major_aplicables, c.major_no_cumple)
  c.pct_minor = pct(c.minor_aplicables, c.minor_no_cumple)
  c.cumple = c.major_no_cumple === 0 && c.pct_minor >= 95
  return c
}

/** Lo que se manda al servidor (cert_qms_enviar_inspeccion). */
export function payload(b) {
  return {
    id: b.id, inicio: b.inicio, fin: b.fin, firmante_nombre: b.firmante_nombre, firma_socio: b.firma_socio,
    inspector_nombre: b.inspector_nombre, firma_inspector: b.firma_inspector,
    resultados: PUNTOS.map(p => {
      const x = b.resultados[p.code] || {}
      return { code: p.code, resultado: x.resultado, comentario: (x.comentario || '').trim() || null, plazo: pidePlazo(p.nivel, x.resultado) ? x.plazo || null : null }
    })
  }
}
export const nivelDe = (code) => NIVEL[code]

// ───────── almacén del equipo (IndexedDB) ─────────
// Una base aparte de la de captura: así no se toca su versión. La demo usa la suya, para no mezclar con lo real.
// 🔴 Una base POR CUENTA (su id): en un equipo compartido, otra cuenta que entra no ve las auditorías, los datos del
// socio ni las firmas de la anterior. Lo firmado y no enviado de una cuenta espera en SU base hasta que vuelva a entrar.
// estado_local: pendiente (descargada) · en_curso · por_enviar (firmada, espera señal) · enviada
const bases = {}
export function almacen(demo, cuenta) {
  if (!demo && !cuenta) throw new Error('sin cuenta: las auditorías del equipo son de cada cuenta')
  const nombre = demo ? 'vg-cert-qms-demo' : 'vg-cert-qms-' + cuenta
  if (!bases[nombre]) {
    const db = new Dexie(nombre)
    db.version(1).stores({ auditorias: 'id,estado_local,fecha_plan' })
    bases[nombre] = db
  }
  return bases[nombre].auditorias
}

/** La v21 (25-oct, unos minutos en el aire) usó una sola base para todas las cuentas. No llegó a tener auditorías reales
 *  (0 en el servidor en todo ese tiempo), así que se borra sin migrar nada. */
export async function borrarBaseCompartidaV21() { try { await Dexie.delete('vg-cert-qms') } catch { /* sin IndexedDB: nada que borrar */ } }

const SIETE_DIAS = 7 * 864e5
/** Trae las asignadas del servidor sin pisar lo que ya se empezó en el equipo. Devuelve cuántas nuevas llegaron.
 *  Lo ya enviado queda en el equipo 7 días, como constancia, y después se quita: el original vive en el servidor. */
export async function descargar(api, demo, cuenta) {
  const tabla = almacen(demo, cuenta)
  const asignadas = await api.misInspecciones()
  const ids = new Set(asignadas.map(a => a.id))
  let nuevas = 0
  for (const a of asignadas) {
    const ya = await tabla.get(a.id)
    if (!ya) { await tabla.put({ ...a, estado_local: 'pendiente', resultados: {}, descargada_en: new Date().toISOString() }); nuevas++ }
    else await tabla.update(a.id, { socio_nombre: a.socio_nombre, direccion: a.direccion, productos: a.productos, sitios: a.sitios, fecha_plan: a.fecha_plan })
  }
  // Lo que el servidor ya no asigna (cancelada o reasignada) se quita solo si nadie la empezó en este equipo.
  for (const b of await tabla.toArray()) {
    if (!ids.has(b.id) && b.estado_local === 'pendiente') await tabla.delete(b.id)
    else if (b.estado_local === 'enviada' && Date.now() - new Date(b.enviada_en || 0) > SIETE_DIAS) await tabla.delete(b.id)
  }
  return nuevas
}

const esRed = (e) => /failed to fetch|networkerror|load failed|network request failed|fetch failed|timed? ?out/i.test(String(e?.message || e)) ||
  (typeof navigator !== 'undefined' && navigator.onLine === false)

/** Envía lo firmado que espera señal. Sin señal no hace nada y lo deja para la próxima. */
export async function enviarPendientes(api, demo, cuenta) {
  const tabla = almacen(demo, cuenta)
  const r = { enviadas: 0, sinRed: false, errores: 0 }
  for (const b of await tabla.where('estado_local').equals('por_enviar').toArray()) {
    try {
      const cumplimiento = await api.enviar(payload(b))
      await tabla.update(b.id, { estado_local: 'enviada', cumplimiento, enviada_en: new Date().toISOString(), error: null })
      r.enviadas++
    } catch (e) {
      if (esRed(e)) { r.sinRed = true; break }
      await tabla.update(b.id, { error: String(e?.message || e) }); r.errores++
    }
  }
  return r
}
