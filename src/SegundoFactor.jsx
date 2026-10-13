// Segundo factor (TOTP) OBLIGATORIO antes de mostrar la app (13-oct-2026, auditoría ASVS L1).
//
// 🔴 El agujero que cierra: signInWithPassword deja una sesión `aal1` y onAuthStateChange la entregaba a la
// app en el acto. El paso del código de <VGLogin> quedaba de adorno: al llegar la sesión, la app desmontaba el
// login y entraba sin código. Y al recargar la página, la sesión `aal1` guardada entraba directo, sin pasar
// nunca por el login. Lo mismo con Google y con el enlace por correo, que no tienen paso de código.
//
// Ahora la app mira el nivel de la sesión (aal) cada vez que cambia y, si la cuenta tiene un factor
// verificado y la sesión todavía no lo usó, muestra ESTE desafío en lugar de la app.
//
// @vgsdk/auth-ui@1.0.0 no trae un desafío suelto: su paso de código solo existe dentro de <VGLogin>, después
// de una contraseña. Por eso este componente mínimo, con el mismo contrato (challenge + verify del factor TOTP
// verificado). Es UX: la garantía real la da la base exigiendo `aal2` en sus reglas.
import React, { useState } from 'react'
import { supabase } from './supabase.js'
import { clasificarError } from './engine.js'

const LARGO = 6

/** Lee el campo `aal` del token sin red (respaldo si la API falla, p. ej. sin señal al refrescar). */
function aalDelToken(token) {
  try {
    const p = String(token || '').split('.')[1].replace(/-/g, '+').replace(/_/g, '/')
    return JSON.parse(atob(p)).aal || null
  } catch { return null }
}

/**
 * ¿Falta el segundo factor en esta sesión? true si la cuenta tiene un factor verificado (nextLevel aal2) y la
 * sesión todavía es aal1. Si la API falla, se calcula igual que ella, con la sesión que ya se tiene: así no se
 * abre la app por un error (no falla «abierto») ni se encierra a nadie por estar sin señal.
 */
export async function faltaSegundoFactor(session) {
  if (!session) return false
  let actual = null, siguiente = null
  try {
    const { data, error } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel()
    if (error || !data) throw error || new Error('sin datos de nivel')
    actual = data.currentLevel; siguiente = data.nextLevel
  } catch {
    actual = aalDelToken(session.access_token)
    const verificados = (session.user?.factors || []).filter(f => f.status === 'verified')
    siguiente = verificados.length ? 'aal2' : actual
  }
  return siguiente === 'aal2' && actual !== 'aal2'
}

/**
 * Verifica un código de 6 dígitos contra el factor TOTP verificado de la cuenta. LANZA si falla (contrato R37
 * de <VGLogin>): lo usan el paso de código del login y el desafío de abajo.
 */
export async function verificarCodigoTotp(codigo) {
  const { data: factores, error: eF } = await supabase.auth.mfa.listFactors()
  if (eF) throw new Error(eF.message)
  // listFactors solo pone en `totp` los factores ya verificados: el primero es el de la aplicación del usuario
  const factor = (factores?.totp || [])[0]
  if (!factor) throw new Error('Esta cuenta no tiene configurado un código de aplicación de autenticación. Escriba a Visión Geográfica.')
  const { data: reto, error: eR } = await supabase.auth.mfa.challenge({ factorId: factor.id })
  if (eR) throw new Error(eR.message)
  const { error: eV } = await supabase.auth.mfa.verify({ factorId: factor.id, challengeId: reto.id, code: codigo })
  // un código equivocado SÍ es un fallo
  if (eV) throw new Error('El código no es válido o ya caducó.')
}

/** Pantalla del desafío. onVerificado() vuelve a mirar el nivel; onOtraCuenta() cierra la sesión (o recarga). */
export function DesafioSegundoFactor({ email, onVerificado, onOtraCuenta }) {
  const [codigo, setCodigo] = useState('')
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState(null)

  async function enviar(e) {
    e.preventDefault()
    if (codigo.length !== LARGO) { setMsg(`El código tiene ${LARGO} dígitos.`); return }
    setBusy(true); setMsg(null)
    try {
      await verificarCodigoTotp(codigo)
      if (onVerificado) await onVerificado()
    } catch (err) {
      setMsg(clasificarError(err).tipo === 'sin_red'
        ? 'Sin conexión: el código se comprueba en el servidor. Vuelva a intentarlo con señal.'
        : (err && err.message) || 'No se pudo verificar el código.')
      setCodigo('')
    } finally { setBusy(false) }
  }

  return (
    <div className="wrap"><div className="card login">
      <h1>Verificación en dos pasos</h1>
      <p className="muted">La cuenta <b>{email}</b> tiene activado el segundo factor. Escriba el código de
        {' '}{LARGO} dígitos de su aplicación de autenticación para continuar.</p>
      <form onSubmit={enviar}>
        <label>Código de {LARGO} dígitos
          <input value={codigo} autoFocus inputMode="numeric" autoComplete="one-time-code" maxLength={LARGO}
            onChange={e => setCodigo(e.target.value.replace(/\D/g, '').slice(0, LARGO))} placeholder="000000" />
        </label>
        {msg ? <div className="err">{msg}</div> : null}
        <button disabled={busy || codigo.length !== LARGO}>{busy ? 'Verificando…' : 'Verificar'}</button>
      </form>
      <button type="button" className="link" style={{ marginTop: 10 }} onClick={onOtraCuenta} disabled={busy}>Usar otra cuenta</button>
    </div></div>
  )
}
