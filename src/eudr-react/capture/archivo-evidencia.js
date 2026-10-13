// Comprobaciones del ARCHIVO de una evidencia (13-oct-2026, auditoría ASVS L1). Vanilla JS, sin dependencias:
// las usan el formulario (al adjuntar) y el transporte (antes de subir).

/* 🔴 TIPO REAL, NO EL QUE DICE EL NAVEGADOR. `file.type` sale de la extensión del nombre: un ejecutable renombrado
   a «acta.pdf» llegaba como application/pdf y se subía al depósito con ese tipo. Ahora se leen los primeros bytes
   (la «firma» del formato) y solo pasan PDF, JPEG, PNG, WEBP y HEIC. El tipo que se guarda y se manda al
   servidor es el detectado, no el declarado. */

export const TIPOS_ADMITIDOS = 'PDF, JPEG, PNG, WEBP o HEIC'

// primeros n bytes de un Blob; FileReader como respaldo para WebView viejos sin Blob.arrayBuffer
function primerosBytes(blob, n) {
  const trozo = blob.slice(0, n)
  if (typeof trozo.arrayBuffer === 'function') return trozo.arrayBuffer().then(b => new Uint8Array(b))
  return new Promise((res, rej) => {
    const r = new FileReader()
    r.onload = () => res(new Uint8Array(r.result))
    r.onerror = () => rej(r.error)
    r.readAsArrayBuffer(trozo)
  })
}

/**
 * Tipo real de un archivo por su firma. null si no es de los admitidos (o no se pudo leer).
 * @param {Blob} blob
 * @returns {Promise<{ mime: string, ext: string } | null>}
 */
export async function tipoReal(blob) {
  if (!blob || typeof blob.slice !== 'function') return null
  let b
  try { b = await primerosBytes(blob, 16) } catch { return null }
  const txt = (i, n) => String.fromCharCode(...b.slice(i, i + n))
  if (txt(0, 4) === '%PDF') return { mime: 'application/pdf', ext: 'pdf' }
  if (b[0] === 0xFF && b[1] === 0xD8 && b[2] === 0xFF) return { mime: 'image/jpeg', ext: 'jpg' }
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4E && b[3] === 0x47) return { mime: 'image/png', ext: 'png' }
  if (txt(0, 4) === 'RIFF' && txt(8, 4) === 'WEBP') return { mime: 'image/webp', ext: 'webp' }
  // HEIC (fotos del iPhone y de algunos Android): caja «ftyp» en el byte 4 y la marca en el byte 8
  if (txt(4, 4) === 'ftyp' && ['heic', 'heix', 'mif1'].includes(txt(8, 4))) return { mime: 'image/heic', ext: 'heic' }
  return null
}

/**
 * Huella sha256 (hex) del contenido. Va en la referencia de la evidencia (`fotos[].sha256`): el sello del servidor
 * cubre la RUTA del archivo, no su contenido; con la huella, cualquier sustitución del archivo se puede detectar.
 * null si el navegador no tiene WebCrypto (fuera de https): no impide respaldar (R1).
 * @param {Blob} blob
 * @returns {Promise<string|null>}
 */
export async function huellaSha256(blob) {
  try {
    const subtle = globalThis.crypto && globalThis.crypto.subtle
    if (!subtle || !blob) return null
    const datos = typeof blob.arrayBuffer === 'function' ? await blob.arrayBuffer() : await primerosBytes(blob, blob.size).then(u => u.buffer)
    const h = new Uint8Array(await subtle.digest('SHA-256', datos))
    return Array.from(h, x => x.toString(16).padStart(2, '0')).join('')
  } catch { return null }
}
