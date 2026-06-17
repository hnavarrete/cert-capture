// Mi bóveda — estado de respaldo/sincronización de las capturas. Da confianza al
// encuestador/proveedor: muestra qué ya está respaldado en el servidor y qué sigue
// solo en el dispositivo (se subirá al volver la señal). Espejo de la "Libreta de
// Campo" del visor. Offline-first: lee de IndexedDB, sirve sin señal.
import React, { useEffect, useState } from 'react'
import { db } from './engine.js'

const FECHA = ts => { try { return new Date(ts).toLocaleString('es', { dateStyle: 'short', timeStyle: 'short' }) } catch { return '' } }
const esSync = s => s === 'synced' || s === 'ok' || s === 'sincronizado'
const esFail = s => s === 'failed' || s === 'error'

export default function Boveda({ slug, productor, finca, status, onFlush, onClose }) {
  const [rows, setRows] = useState(null)
  const [sincronizando, setSincronizando] = useState(false)
  const offline = status?.offline

  const cargar = async () => {
    const all = await db.cert_responses.toArray()
    const ctx = all.filter(r => {
      const rs = r.client_slug || r.company_id
      if (slug && rs && rs !== slug) return false
      if (productor && r.productor_id && r.productor_id !== productor) return false
      if (finca && r.finca_id && r.finca_id !== finca) return false
      return true
    }).map(r => ({ form_key: r.form_key, estado: r.sync_status || 'pending', ts: r.created_at, id: r.local_id || r._idb_id }))
    ctx.sort((a, b) => (b.ts || 0) - (a.ts || 0))
    setRows(ctx)
  }
  useEffect(() => { cargar() }, [slug, productor, finca])

  const respaldados = (rows || []).filter(r => esSync(r.estado))
  const conError = (rows || []).filter(r => esFail(r.estado))
  const enDispositivo = (rows || []).filter(r => !esSync(r.estado) && !esFail(r.estado))
  const porSubir = enDispositivo.length + conError.length
  const total = (rows || []).length

  const sincronizar = async () => {
    if (!onFlush || offline) return
    setSincronizando(true)
    try { await onFlush() } catch {}
    setTimeout(() => { cargar(); setSincronizando(false) }, 1200)
  }

  const Badge = ({ estado }) => esSync(estado)
    ? <span className="bov-badge ok">respaldado</span>
    : esFail(estado) ? <span className="bov-badge err">error al subir</span>
      : <span className="bov-badge pend">en este dispositivo</span>

  return (
    <div className="overlay" onClick={onClose}>
      <div className="sheet" onClick={e => e.stopPropagation()}>
        <div className="sheet-head">
          <strong>🔒 Mi bóveda{slug ? ` · ${slug}` : ''}</strong>
          <button className="link" onClick={onClose}>Cerrar ✕</button>
        </div>

        <div className="tablero">
          {rows === null ? <p className="muted">Abriendo tu bóveda…</p> : (
            <>
              <div style={{ padding: '12px 14px', borderRadius: 12, background: porSubir ? 'var(--warn-bg)' : 'var(--ok-bg)', marginBottom: 14 }}>
                <p style={{ margin: 0, fontWeight: 700, color: porSubir ? 'var(--warn-ink)' : 'var(--ok-ink)' }}>
                  {total === 0 ? 'Tu bóveda está lista'
                    : porSubir === 0 ? '✓ Todo tu trabajo está respaldado en el servidor'
                      : `${porSubir} ${porSubir === 1 ? 'registro' : 'registros'} aún en tu dispositivo`}
                </p>
                <p className="muted" style={{ margin: '4px 0 0', color: porSubir ? 'var(--warn-ink)' : 'var(--ok-ink)' }}>
                  {total === 0
                    ? 'Cada captura se guarda primero en tu dispositivo (aunque no haya señal) y se respalda en el servidor al sincronizar. Nada se pierde.'
                    : porSubir === 0
                      ? 'Hiciste tu parte: todo lo capturado está a salvo en el servidor.'
                      : 'Tu trabajo NO se pierde: está guardado en este dispositivo y se subirá solo al volver la señal.'}
                </p>
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: 10, marginBottom: 14 }}>
                <Metric label="Respaldados" value={respaldados.length} color="var(--ok-ink)" />
                <Metric label="En el dispositivo" value={enDispositivo.length} color="var(--warn-ink)" />
                <Metric label="Con error" value={conError.length} color={conError.length ? 'var(--err-ink)' : 'var(--muted)'} />
              </div>

              {porSubir > 0 ? (
                <button type="button" className="primary" style={{ width: '100%', marginBottom: 14 }} onClick={sincronizar} disabled={offline || sincronizando}>
                  {offline ? 'Sin conexión — se subirá al volver la señal' : sincronizando ? 'Sincronizando…' : `Sincronizar ahora (${porSubir})`}
                </button>
              ) : null}

              {total === 0 ? <p className="muted">Aún no has capturado registros en este contexto.</p> : (
                <div className="bov-list">
                  {[...conError, ...enDispositivo, ...respaldados].slice(0, 40).map((r, i) => (
                    <div key={r.id || i} className="bov-row">
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div className="bov-form">{r.form_key}</div>
                        <div className="muted" style={{ fontSize: 12 }}>{FECHA(r.ts)}</div>
                      </div>
                      <Badge estado={r.estado} />
                    </div>
                  ))}
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  )
}

function Metric({ label, value, color }) {
  return (
    <div style={{ background: 'var(--bg)', borderRadius: 11, padding: '10px 12px', textAlign: 'center' }}>
      <div style={{ fontSize: 22, fontWeight: 800, color }}>{value}</div>
      <div className="muted" style={{ margin: 0, fontSize: 12 }}>{label}</div>
    </div>
  )
}
