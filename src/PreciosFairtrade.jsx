import React, { useEffect, useMemo, useState } from 'react'
import { Icono } from './eudr-react/CertForm.jsx'
import { supabase } from './supabase.js'
import {
  CERTEZA, vigentes, proximos, hoyEcuador, textoPrecio, textoPrima, textoProducto, textoVigencia, textoFecha
} from './fairtrade-precios.js'

const PRODUCTOS = [
  { key: 'cacao', label: 'Cacao' }, { key: 'cafe', label: 'Café' },
  { key: 'banano', label: 'Banano' }, { key: 'flores', label: 'Flores' }
]
const NOTA = {
  cacao: 'Ecuador entra en «Mundial (excepto Costa de Marfil y Ghana)». Precio FOB por tonelada métrica de cacao en grano.',
  cafe: 'Precio FOB por libra. El nuevo Precio Mínimo rige para contratos firmados desde el 1-dic-2026.',
  banano: 'Precio por caja de 18,14 kg en Ecuador. La Prima es 1 USD por caja. Desde 2027 el precio FOB depende de la provincia y del puerto.',
  flores: 'Las flores no tienen Precio Mínimo: el precio se negocia y la Prima es un porcentaje.'
}

/* Precios Mínimos y Primas Fairtrade: datos con vigencia, fuente y certeza. No es parte de ningún formulario:
   se consulta aquí y, con sesión, se lee del servidor (attest.precio_referencia); sin sesión o sin red, del bundle. */
export default function PreciosFairtrade({ referencia, conSesion }) {
  const [producto, setProducto] = useState('cacao')
  const [fecha, setFecha] = useState(hoyEcuador())
  const [delServidor, setDelServidor] = useState(null)

  useEffect(() => {
    if (!conSesion) { setDelServidor(null); return }
    let on = true
    supabase.rpc('cert_precios_referencia', { p_programa: 'fairtrade' })
      .then(({ data, error }) => { if (on) setDelServidor(!error && Array.isArray(data) && data.length ? data : null) })
      .catch(() => { if (on) setDelServidor(null) })
    return () => { on = false }
  }, [conSesion])

  const filas = delServidor || referencia?.filas || []
  const ahora = useMemo(() => vigentes(filas, fecha, producto), [filas, fecha, producto])
  const luego = useMemo(() => proximos(filas, fecha, producto), [filas, fecha, producto])
  const fuente = referencia?.fuente_principal

  if (!filas.length) return null
  return (
    <div className="card ft-precios">
      <h3><Icono n="payments" />Precios Mínimos y Primas Fairtrade</h3>
      <p className="muted">Datos de la tabla oficial de Fairtrade International, con su vigencia, fuente y nivel de certeza.
        No forman parte de los formularios. Solo lo verificado se usa para calcular.</p>
      <div className="chips">
        {PRODUCTOS.map(p => (
          <button key={p.key} type="button" className={'chip ' + (producto === p.key ? 'sel' : '')} onClick={() => setProducto(p.key)}>{p.label}</button>
        ))}
      </div>
      <label className="ft-fecha">Vigentes el día
        <input type="date" value={fecha} onChange={e => setFecha(e.target.value || hoyEcuador())} />
      </label>
      <p className="muted ft-nota">{NOTA[producto]}</p>

      <ul className="ft-lista" aria-label="Precios vigentes">
        {ahora.length ? ahora.map(f => <FilaPrecio key={f.id} f={f} />) : <li className="muted">No hay precios vigentes en esa fecha.</li>}
      </ul>

      {luego.length ? (
        <details className="ft-proximos">
          <summary><Icono n="event" />Cambios ya anunciados · {luego.length}</summary>
          <ul className="ft-lista">{luego.map(f => <FilaPrecio key={f.id} f={f} />)}</ul>
        </details>
      ) : null}

      <p className="muted ft-fuente">
        Fuente: {fuente ? <a href={fuente.url} target="_blank" rel="noopener">{fuente.documento} <Icono n="open_in_new" /></a> : 'tabla oficial'}
        {fuente ? <> · consultada el {textoFecha(fuente.consultado_el)}</> : null}
        {' · '}{delServidor ? 'leída del servidor' : 'copia en la app'}.
        {' '}El Precio Mínimo es un piso: si el mercado paga más, rige el de mercado; la Prima se paga aparte.
      </p>
    </div>
  )
}

function FilaPrecio({ f }) {
  const c = CERTEZA[f.certeza] || CERTEZA.por_verificar
  return (
    <li className={'ft-fila ' + (f.certeza !== 'verificado' ? 'no-calculo' : '')}>
      <div className="ft-que">{textoProducto(f)}</div>
      <div className="ft-cifras">
        <span><small>Precio Mínimo</small>{textoPrecio(f)}</span>
        <span><small>Prima Fairtrade</small>{textoPrima(f)}</span>
      </div>
      <div className="ft-meta">
        <span className={'ft-certeza ' + c.clase}>{c.texto}</span>
        <span>{textoVigencia(f)}</span>
        <a href={f.fuente_url} target="_blank" rel="noopener">{f.fuente_documento}</a>
      </div>
      {f.notas ? <div className="muted ft-notas">{f.notas}</div> : null}
    </li>
  )
}
