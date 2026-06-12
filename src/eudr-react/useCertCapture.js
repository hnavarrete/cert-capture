// useCertCapture — hook que conecta <CertForm> con el motor offline-first y expone el estado de sync.
// El host (#07 APK / #03 ERP) arma el engine con su propia Dexie + transport y se lo pasa; este hook
// solo orquesta y suscribe al estado. Sin dependencias más que React.

import { useEffect, useState, useCallback } from 'react'

/**
 * @param {object} engine - instancia de createCertOfflineEngine (de la capa capture, agnóstica).
 * @returns {{ status, saveResponse, listResponses, verifyChain, flush }}
 */
export function useCertCapture(engine) {
  const [status, setStatus] = useState({ pending: 0, failed: 0, synced: 0, total: 0, offline: false })

  useEffect(() => {
    if (!engine || typeof engine.onStatus !== 'function') return
    const off = engine.onStatus(setStatus)
    return () => { try { off && off() } catch {} }
  }, [engine])

  const saveResponse = useCallback((args) => engine && engine.saveResponse(args), [engine])
  const listResponses = useCallback((form_key) => engine && engine.listResponses(form_key), [engine])
  const verifyChain = useCallback((form_key) => engine && engine.verifyResponseChain && engine.verifyResponseChain(form_key), [engine])
  const flush = useCallback(() => engine && engine.flush(), [engine])

  return { status, saveResponse, listResponses, verifyChain, flush }
}

/**
 * Adapter EUDR: mapea un `data` plano (seccion.campo) al `ctx.fields` normalizado que espera el
 * motor antifraude (fraud-rules-engine). El host pasa esto como hook `antifraude` al crear el engine,
 * o lo usa directo para mostrar flags en la UI. Mantiene el motor desacoplado del naming del schema.
 *
 * @param {object} record - el cert_response (data, geom, fotos, certificacion...).
 * @param {object} [externo] - { deforestacion, catastro_area_ha } (lo entrega #08/#03).
 * @returns {object} ctx listo para evaluateRules.
 */
export function buildAntifraudeCtxEUDR(record, externo = {}) {
  const d = record.data || {}
  const get = (...keys) => { for (const k of keys) { if (d[k] != null) return d[k] } return undefined }
  const num = (v) => (v == null || v === '' ? undefined : Number(v))
  return {
    certificacion: record.certificacion,
    geom: record.geom || null,
    fotos: (record.fotos || []).map(f => ({ field: f.field, lat: f.lat, lng: f.lng, timestamp: f.timestamp, photo_id: f.photo_id })),
    externo,
    fields: {
      area_declarada_ha: num(get('identificacion.area_ha', 'tierra.acreage', 'finca.area_ha', 'area_ha')),
      volumen_declarado_kg: num(get('trazabilidad.volumen_estimado', 'trazabilidad.volumen_cosechado', 'volumen_kg')),
      cultivo: (get('identificacion.cultivo', 'finca.cultivo', 'cultivo') || '').toString().toLowerCase() || undefined,
      usa_riego: get('manejo_agua.usa_riego', 'usa_riego'),
      consumo_agua_m3: num(get('manejo_agua.consumo_m3', 'consumo_agua_m3')),
      declara_sin_deforestacion: get('eudr.sin_deforestacion', 'declara_sin_deforestacion')
    }
  }
}

export default { useCertCapture, buildAntifraudeCtxEUDR }
