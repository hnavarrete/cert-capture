// Precios Mínimos y Primas Fairtrade: lectura de la tabla de datos (con vigencia, fuente y certeza).
// La tabla NO vive en ningún formulario. Viene del bundle (sirve sin red) y, con sesión, del servidor
// (attest.precio_referencia por public.cert_precios_referencia). Solo las filas «verificado» se usan en cálculos.

export const CERTEZA = Object.freeze({
  verificado: { texto: 'Verificado', clase: 'ok' },
  parcial: { texto: 'Parcial · no se usa en cálculos', clase: 'warn' },
  por_verificar: { texto: 'Por verificar · no se usa en cálculos', clase: 'err' }
})

export const usableEnCalculo = f => !!f && f.certeza === 'verificado'

/** ¿La fila rige en la fecha (AAAA-MM-DD)? vigente_hasta es inclusivo; sin él, sigue vigente. */
export function rigeEn(f, fecha) {
  return f.vigente_desde <= fecha && (!f.vigente_hasta || f.vigente_hasta >= fecha)
}

/** Filas que rigen en la fecha, opcionalmente de un producto. Incluye las no verificadas (se muestran marcadas). */
export function vigentes(filas, fecha, producto) {
  return (filas || []).filter(f => (!producto || f.producto === producto) && rigeEn(f, fecha))
}

/** Cambios ya anunciados: filas que empiezan a regir después de la fecha. */
export function proximos(filas, fecha, producto) {
  return (filas || []).filter(f => (!producto || f.producto === producto) && f.vigente_desde > fecha)
    .sort((a, b) => a.vigente_desde.localeCompare(b.vigente_desde))
}

const CRITERIOS = ['producto', 'forma', 'calidad', 'origen', 'pais', 'base', 'punto']

/**
 * La única fila VERIFICADA que rige en la fecha para el criterio dado. Si no hay ninguna, null: lo no verificado
 * nunca se usa para calcular. Si hay más de una, es un error de datos y se dice (no se elige una a ciegas).
 */
export function precioVigente(filas, criterio, fecha) {
  const ok = (filas || []).filter(f => usableEnCalculo(f) && rigeEn(f, fecha) &&
    CRITERIOS.every(k => criterio[k] === undefined || (f[k] ?? null) === criterio[k]))
  if (ok.length > 1) throw new Error('Más de una fila vigente para ' + JSON.stringify(criterio) + ' el ' + fecha)
  return ok[0] || null
}

/** Prima Fairtrade de una venta, con una fila verificada. Por porcentaje necesita el precio de venta. */
export function primaDeVenta(fila, cantidad, precioVenta) {
  if (!usableEnCalculo(fila)) return null
  if (fila.prima != null) return redondear(fila.prima * cantidad)
  if (fila.prima_porcentaje != null && precioVenta != null) return redondear(fila.prima_porcentaje / 100 * precioVenta * cantidad)
  return null
}

const redondear = v => Math.round(v * 100) / 100

const fmtNum = (v, dec) => new Intl.NumberFormat('es-EC', { minimumFractionDigits: dec, maximumFractionDigits: dec }).format(v)
const decimales = v => (Number.isInteger(v) ? 0 : 2)

export function textoPrecio(f) {
  if (f.precio_minimo != null) return `${f.moneda} ${fmtNum(f.precio_minimo, decimales(f.precio_minimo))} por ${f.unidad}`
  if (f.diferencial_organico != null) return `Mínimo convencional + ${f.moneda} ${fmtNum(f.diferencial_organico, decimales(f.diferencial_organico))} por ${f.unidad} (orgánico)`
  return f.precio_minimo_texto || 'Sin dato'
}

export function textoPrima(f) {
  if (f.prima != null) return `${f.moneda} ${fmtNum(f.prima, decimales(f.prima))} por ${f.unidad}`
  if (f.prima_porcentaje != null) return `${fmtNum(f.prima_porcentaje, 0)} % del ${f.prima_base}`
  return 'Sin dato'
}

const MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic']
export function textoFecha(iso) {
  if (!iso) return ''
  const [a, m, d] = iso.split('-').map(Number)
  return `${d}-${MESES[m - 1]}-${a}`
}

export function textoVigencia(f) {
  return f.vigente_hasta ? `Del ${textoFecha(f.vigente_desde)} al ${textoFecha(f.vigente_hasta)}` : `Desde el ${textoFecha(f.vigente_desde)}`
}

const FORMAS = {
  grano: 'Grano', fresco: 'Fruta fresca', salario_digno_referencia: 'Precio de referencia de salario digno',
  arabica_lavado: 'Arábica lavado', arabica_natural: 'Arábica natural', robusta_lavado: 'Robusta lavado', robusta_natural: 'Robusta natural',
  tallos: 'Tallos', ramos: 'Ramos', bouquets: 'Bouquets', plantas_en_maceta: 'Plantas en maceta', material_vegetal_joven: 'Material vegetal joven'
}
export function textoProducto(f) {
  const partes = [FORMAS[f.forma] || f.forma, f.calidad === 'organico' ? 'orgánico' : 'convencional']
  const lugar = [f.base, f.punto].filter(Boolean).join(' ')
  return partes.join(', ') + (lugar ? ' · ' + lugar : '') + (f.origen ? ' · ' + f.origen : '')
}

/** Fecha de hoy en Ecuador (AAAA-MM-DD), del reloj del equipo. */
export function hoyEcuador(d = new Date()) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Guayaquil', year: 'numeric', month: '2-digit', day: '2-digit' }).format(d)
}
