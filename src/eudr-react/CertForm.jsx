// <CertForm> — render dinámico de un form-schema de certificación VG, offline-first.
// Lo consumen el APK VG Suite (#07) y el ERP (#03): le pasan un schema (de @vgsdk/cert-schemas) y
// un engine (createCertOfflineEngine) y obtienen la pantalla de captura completa sin construirla.
//
// Reglas VG aplicadas:
//  - R1/R2 offline-safe: al guardar se LEE DEL DOM (blur + value), no del state de React, para evitar
//    el race del IME en Android (el buffer no llega al state hasta blur). Cada input lleva [data-field].
//  - R22: el campo gps_polygon ofrece CONECTAR el polígono del visor (no recapturar) vía onConnectPolygon.
//  - Antifraude: si el engine devuelve flags/nivel, se muestran (la UI no miente sobre el estado del dato).

import React, { useRef, useState, useCallback, useEffect } from 'react'

const TIPOS_TEXTO = new Set(['text', 'email', 'tel', 'number', 'decimal', 'date'])

function fieldKey(seccionKey, campoKey) { return `${seccionKey}.${campoKey}` }

// Progreso de completitud del formulario (gamificación seria): cuenta campos respondidos vs total.
// Distingue Major Must / Minor Must (control_points por nivel) para el umbral vendible del marketplace
// (100% Major + ≥95% Minor — ver export-policy / marco antifraude).
function progresoDe(schema, data) {
  let total = 0, hechas = 0, major = 0, majorOk = 0, minor = 0, minorOk = 0
  for (const sec of (schema.secciones || [])) {
    for (const c of (sec.campos || [])) {
      const tipo = c.tipo || 'text'
      if (tipo === 'nota' || tipo === 'info') continue
      const base = fieldKey(sec.key, c.key)
      const v = tipo === 'control_point' ? data[base + '.estado'] : data[base]
      const lleno = v != null && v !== '' && !(Array.isArray(v) && v.length === 0)
      total++; if (lleno) hechas++
      if (tipo === 'control_point') {
        const niv = (c.nivel || '').toString().toLowerCase()
        if (/major|mayor|obligaci.n mayor/.test(niv)) { major++; if (lleno) majorOk++ }
        else if (/minor|menor|obligaci.n menor/.test(niv)) { minor++; if (lleno) minorOk++ }
      }
    }
  }
  const pct = total ? Math.round((100 * hechas) / total) : 0
  const majorPct = major ? Math.round((100 * majorOk) / major) : 100
  const minorPct = minor ? Math.round((100 * minorOk) / minor) : 100
  // umbral vendible/certificable: 100% Major + >=95% Minor
  const vendible = majorPct >= 100 && minorPct >= 95
  return { total, hechas, pct, major, majorOk, majorPct, minor, minorOk, minorPct, vendible }
}

// --- evaluación mínima de show_if (soporta { campo, igual_a } o null) ---
function visible(showIf, data) {
  if (!showIf) return true
  if (typeof showIf === 'function') { try { return !!showIf(data) } catch { return true } }
  if (showIf.campo) {
    const v = data[showIf.campo]
    if ('igual_a' in showIf) return v === showIf.igual_a
    if ('distinto_de' in showIf) return v !== showIf.distinto_de
    return !!v
  }
  return true
}

// Campo de polígono. Delega al host vía onConnectPolygon(field) → el shell abre el mapa del VISOR
// (MapView + editor de geometría, vía el bridge SSO de #07/#11) y devuelve el geoshape. El polígono se
// REUSA del visor (no se recaptura, no hay otro mapa embebido ni cache de tiles propio). El host puede
// devolver un GeoJSON/geoshape directo o { geoshape, origen }. Se guarda el geoshape + poligono_origen.
function CampoPoligono({ campo, dataField, valor, onConnectPolygon }) {
  const [geo, setGeo] = useState(valor ? (typeof valor === 'string' ? valor : JSON.stringify(valor)) : '')
  const [origen, setOrigen] = useState('')
  const [busy, setBusy] = useState(false)
  async function conectar() {
    if (!onConnectPolygon) return
    setBusy(true)
    try {
      const res = await onConnectPolygon(dataField)
      if (res) {
        const gj = res.geoshape ?? res.geojson ?? res.geom ?? res
        setGeo(typeof gj === 'string' ? gj : JSON.stringify(gj))
        setOrigen(res.origen || 'visor_existente')
      }
    } finally { setBusy(false) }
  }
  return (
    <div className="vg-field vg-poly">
      <label>{campo.label}{campo.required ? ' *' : ''}</label>
      <button type="button" onClick={conectar} disabled={busy}>
        {busy ? 'Abriendo el mapa…' : (geo ? '🗺️ Polígono listo · cambiar' : '🗺️ Conectar polígono del visor')}
      </button>
      <input type="hidden" data-field={dataField} id={dataField} value={geo} readOnly />
      <input type="hidden" data-field={`${dataField}__origen`} value={origen} readOnly />
      {geo
        ? <small className="vg-poly-ok">✓ Polígono {origen === 'capturado_aqui' ? 'dibujado en campo' : 'conectado del visor'}.</small>
        : <small>Si la finca ya está digitalizada en el visor, se reutiliza el polígono (no se recaptura).</small>}
    </div>
  )
}

// Captura de foto/evidencia OFFLINE-FIRST. Abre la cámara o el explorador de archivos (input file con
// capture), muestra una vista previa, y registra el blob vía addFoto(fieldKey, file). El blob se persiste
// en IDB al guardar (el engine ya lo soporta). En el campo va un input hidden con el nombre del archivo
// para que readFormFromContainer registre que hay evidencia.
function FotoEvidencia({ fieldKey: fk, label, addFoto, compacto }) {
  const inputRef = useRef(null)
  const [preview, setPreview] = useState(null)
  const [nombre, setNombre] = useState('')
  function onPick(e) {
    const file = e.target.files && e.target.files[0]
    if (!file) return
    setNombre(file.name)
    if (addFoto) addFoto(fk, file)
    try { const r = new FileReader(); r.onload = () => setPreview(r.result); r.readAsDataURL(file) } catch {}
  }
  return (
    <div className="vg-foto-box">
      <input ref={inputRef} type="file" accept="image/*" capture="environment" style={{ display: 'none' }} onChange={onPick} />
      <input type="hidden" data-field={fk} value={nombre} readOnly />
      <button type="button" className="vg-foto" onClick={() => inputRef.current && inputRef.current.click()}>
        📷 {preview ? 'Cambiar foto' : (compacto ? 'Tomar / cargar evidencia' : (label ? 'Tomar / cargar: ' + label : 'Tomar foto o cargar archivo'))}
      </button>
      {preview ? <img className="vg-foto-prev" src={preview} alt="evidencia" /> : null}
      {nombre ? <span className="vg-foto-name">✓ {nombre}</span> : null}
    </div>
  )
}

function Campo({ seccionKey, campo, valor, addFoto, onConnectPolygon }) {
  const dataField = fieldKey(seccionKey, campo.key)
  const tipo = campo.tipo || 'text'
  const common = { 'data-field': dataField, id: dataField, defaultValue: valor ?? '' }

  if (tipo === 'control_point') {
    return (
      <div className="vg-cp">
        <div className="vg-cp-criterio"><strong>{campo.key}</strong> · {campo.label}
          {campo.nivel ? <span className="vg-cp-nivel"> [{campo.nivel}]</span> : null}</div>
        {campo.criterio ? (
          <details className="vg-cp-oficial"><summary>Ver texto oficial de la norma (referencia)</summary>
            <div className="vg-cp-texto">{campo.criterio}</div></details>
        ) : null}
        <select data-field={`${dataField}.estado`} id={`${dataField}.estado`} defaultValue={(valor && valor.estado) || ''}>
          <option value="">— sin responder —</option>
          <option value="cumple">Cumple</option>
          <option value="no_cumple">No cumple</option>
          <option value="na">No aplica</option>
        </select>
        {campo.requiere_evidencia ? (
          <FotoEvidencia fieldKey={`${dataField}__evidencia`} addFoto={addFoto} compacto />
        ) : null}
      </div>
    )
  }

  if (tipo === 'gps_polygon') {
    return <CampoPoligono campo={campo} dataField={dataField} valor={valor} onConnectPolygon={onConnectPolygon} />
  }

  if (tipo === 'photo') {
    return (
      <div className="vg-field">
        <label>{campo.label}{campo.required ? ' *' : ''}</label>
        <FotoEvidencia fieldKey={dataField} label={campo.label} addFoto={addFoto} />
        {campo.help ? <small>{campo.help}</small> : null}
      </div>
    )
  }

  if (tipo === 'signature') {
    return (
      <div className="vg-field">
        <label htmlFor={dataField}>{campo.label}</label>
        <input data-field={dataField} id={dataField} placeholder="Firma (nombre o canvas en el host)" defaultValue={valor ?? ''} />
      </div>
    )
  }

  if (tipo === 'textarea') {
    return (
      <div className="vg-field">
        <label htmlFor={dataField}>{campo.label}{campo.required ? ' *' : ''}</label>
        <textarea {...common} rows={3} />
        {campo.help ? <small>{campo.help}</small> : null}
      </div>
    )
  }

  if (tipo === 'select') {
    return (
      <div className="vg-field">
        <label htmlFor={dataField}>{campo.label}{campo.required ? ' *' : ''}</label>
        <select data-field={dataField} id={dataField} defaultValue={valor ?? ''}>
          <option value="">— seleccionar —</option>
          {(campo.opciones || []).map(o => <option key={o.valor} value={o.valor}>{o.label}</option>)}
        </select>
        {campo.help ? <small>{campo.help}</small> : null}
      </div>
    )
  }

  if (tipo === 'multiselect') {
    return (
      <fieldset className="vg-field vg-multi" data-field={dataField} data-multiselect="1">
        <legend>{campo.label}{campo.required ? ' *' : ''}</legend>
        {(campo.opciones || []).map(o => (
          <label key={o.valor} className="vg-check">
            <input type="checkbox" data-opt={o.valor} defaultChecked={Array.isArray(valor) && valor.includes(o.valor)} />
            {o.label}
          </label>
        ))}
        {campo.help ? <small>{campo.help}</small> : null}
      </fieldset>
    )
  }

  if (tipo === 'boolean') {
    return (
      <label className="vg-field vg-check">
        <input type="checkbox" data-field={dataField} id={dataField} data-bool="1" defaultChecked={!!valor} />
        {campo.label}
      </label>
    )
  }

  // text / decimal / date / number / email / tel
  return (
    <div className="vg-field">
      <label htmlFor={dataField}>{campo.label}{campo.required ? ' *' : ''}</label>
      <input type={tipo === 'decimal' || tipo === 'number' ? 'number' : (TIPOS_TEXTO.has(tipo) ? tipo : 'text')}
        step={tipo === 'decimal' ? 'any' : undefined} {...common} />
      {campo.unidad ? <span className="vg-unidad">{campo.unidad}</span> : null}
      {campo.help ? <small>{campo.help}</small> : null}
    </div>
  )
}

/**
 * Lee TODO el formulario desde el DOM (R2 offline-safe) en un objeto data plano por seccion.campo.
 * Maneja checkbox (boolean), multiselect (array de data-opt marcados) y el resto por value.
 */
export function readFormFromContainer(containerEl) {
  const data = {}
  if (!containerEl) return data
  // multiselects
  containerEl.querySelectorAll('[data-multiselect="1"]').forEach(fs => {
    const field = fs.getAttribute('data-field')
    const vals = []
    fs.querySelectorAll('input[type=checkbox][data-opt]').forEach(cb => { if (cb.checked) vals.push(cb.getAttribute('data-opt')) })
    data[field] = vals
  })
  // resto de inputs con data-field
  containerEl.querySelectorAll('[data-field]:not([data-multiselect])').forEach(el => {
    const field = el.getAttribute('data-field')
    if (data[field] !== undefined) return
    try { el.blur && el.blur() } catch {}
    if (el.getAttribute('data-bool') === '1' || el.type === 'checkbox') data[field] = !!el.checked
    else data[field] = el.value != null ? el.value : (el.textContent || '')
  })
  return data
}

/**
 * <CertForm schema engine value onSaved onConnectPolygon onPhoto readonly />
 * - schema: un form-schema de @vgsdk/cert-schemas.
 * - engine: instancia de createCertOfflineEngine (offline-first). Si falta, usa onSave(data).
 * - onSaved(result): callback tras guardar (result trae local_id, sync_status, antifraude...).
 */
export default function CertForm({ schema, engine, value = {}, onSave, onSaved, onConnectPolygon, onPhoto, productor_id, finca_id, readonly = false }) {
  const containerRef = useRef(null)
  const fotosRef = useRef({})
  const [saving, setSaving] = useState(false)
  const [status, setStatus] = useState(null)

  // registra el blob de una foto/evidencia por campo (offline-first; se persiste en IDB al guardar)
  const addFoto = useCallback((field, file) => {
    fotosRef.current[field] = { field, blob: file, mime: file.type || 'image/jpeg', name: file.name }
  }, [])

  // progreso de completitud en vivo (gamificación)
  const [prog, setProg] = useState({ total: 0, hechas: 0, pct: 0, vendible: false, major: 0, majorPct: 100, minorPct: 100 })
  const recalc = useCallback(() => {
    if (!containerRef.current) return
    try { setProg(progresoDe(schema, readFormFromContainer(containerRef.current))) } catch {}
  }, [schema])
  useEffect(() => { recalc() }, [recalc])

  const handleSave = useCallback(async () => {
    if (!containerRef.current) return
    setSaving(true)
    try {
      const data = readFormFromContainer(containerRef.current)
      const fotos = Object.values(fotosRef.current).map(f => ({ field: f.field, blob: f.blob, mime: f.mime }))
      let result
      if (engine && typeof engine.saveResponse === 'function') {
        result = await engine.saveResponse({
          form_key: schema.form_key, certificacion: schema.certificacion,
          data, fotos, productor_id, finca_id
        })
      } else if (onSave) {
        result = await onSave(data, fotos)
      }
      setStatus(result || { ok: true })
      if (onSaved) onSaved(result, data)
    } catch (e) {
      setStatus({ error: e.message })
    } finally { setSaving(false) }
  }, [engine, schema, onSave, onSaved, productor_id, finca_id])

  if (!schema) return null

  return (
    <form ref={containerRef} className="vg-certform" onInput={recalc} onChange={recalc} onSubmit={e => { e.preventDefault(); handleSave() }}>
      <header className="vg-certform-head">
        <h2>{schema.titulo}</h2>
        {schema.descripcion ? <p>{schema.descripcion}</p> : null}
        <span className="vg-cert-tag">{schema.certificacion}</span>
        <div className="vg-progreso">
          <div className="vg-prog-bar"><span className={prog.vendible ? 'ok' : ''} style={{ width: prog.pct + '%' }} /></div>
          <div className="vg-prog-info">
            <strong>{prog.pct}% completo</strong> · {prog.hechas}/{prog.total} preguntas
            {prog.major ? <span> · obligaciones mayores {prog.majorPct}%</span> : null}
            {prog.vendible
              ? <span className="vg-prog-badge ok">✓ Listo para certificar</span>
              : <span className="vg-prog-badge">Complétalo para certificar y poder compartir</span>}
          </div>
        </div>
      </header>

      {(schema.secciones || []).map(sec => {
        if (!visible(sec.show_if, value)) return null
        return (
          <section key={sec.key} className="vg-seccion">
            <h3>{sec.titulo}</h3>
            {sec.descripcion ? <p className="vg-seccion-desc">{sec.descripcion}</p> : null}
            {(sec.campos || []).map(campo => (
              <Campo key={campo.key} seccionKey={sec.key} campo={campo}
                valor={value[fieldKey(sec.key, campo.key)]}
                addFoto={addFoto} onConnectPolygon={onConnectPolygon} />
            ))}
          </section>
        )
      })}

      {!readonly ? (
        <footer className="vg-certform-foot">
          <button type="submit" disabled={saving}>{saving ? 'Guardando…' : 'Guardar (offline)'}</button>
          {status && status.sync_status ? <span className="vg-sync">estado: {status.sync_status}</span> : null}
          {status && status.antifraude && status.antifraude.flags && status.antifraude.flags.length ? (
            <span className="vg-flags">⚠ {status.antifraude.flags.length} alerta(s) · riesgo {status.antifraude.nivel_riesgo}</span>
          ) : null}
          {status && status.error ? <span className="vg-error">Error: {status.error}</span> : null}
        </footer>
      ) : null}
    </form>
  )
}
