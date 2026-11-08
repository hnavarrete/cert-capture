import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { execFileSync } from 'node:child_process'

const __dirname = dirname(fileURLToPath(import.meta.url))

// R-FECHA-VERSIÓN: el pie de la app lleva «Versión N · fecha y hora». N = despliegues hechos + 1 (cada
// despliegue es un commit «deploy: …» en master), la hora es la del reloj de la máquina al construir.
function versionApp() {
  try {
    const n = execFileSync('git', ['log', '--oneline', '--grep=^deploy', 'master'], { cwd: __dirname, encoding: 'utf8' })
      .split('\n').filter(Boolean).length
    return String(n + 1)
  } catch { return 'local' }
}
const AHORA = new Intl.DateTimeFormat('es-EC', {
  timeZone: 'America/Guayaquil', weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false
}).format(new Date())

// base relativo para que funcione bajo subcarpeta en GitHub Pages.
export default defineConfig({
  plugins: [
    react(),
    // Service Worker (R3: el encuestador DEBE bootear OFFLINE — captura de campo + embebido en el APK).
    // registerType:'autoUpdate' = se actualiza solo y NO sirve bundle viejo silenciosamente (evita la
    // trampa de caché stale que pegó al resto del ecosistema): skipWaiting + clients.claim automáticos.
    VitePWA({
      registerType: 'autoUpdate',
      injectRegister: 'auto',
      workbox: {
        // precachea el app-shell + assets → la app arranca sin red (standalone y embebida en https://localhost).
        globPatterns: ['**/*.{js,css,html,json,svg,png,ico,woff2}'],
        // R-AYUDA: el índice de la ayuda se lee siempre de la red (si se precacheara, mostraría la lista vieja
        // hasta la próxima versión del SW). Los videos viven en otro origen (cert-videos.visiongeografica.com) y el SW
        // no tiene runtimeCaching: no los intercepta.
        globIgnores: ['**/ayuda/ayuda.json', '**/node_modules/**'],
        // 6-nov-2026: con los 8 formularios Fairtrade el bundle principal pasa de 1,99 a 2,43 MB, y sin la segunda página
        // de Vite (la ayuda es ahora la plantilla del kit) React ya no va en un trozo compartido. Con el tope por omisión
        // de Workbox (2 MiB) main quedaba FUERA del precache y la app no arrancaría sin red (R3). Unidas las dos ramas el
        // 8-nov-2026 (#05), se deja el tope mayor de los dos: 4 MiB.
        maximumFileSizeToCacheInBytes: 4 * 1024 * 1024,
        cleanupOutdatedCaches: true,
        navigateFallback: 'index.html',
        // /ayuda/ es su propia página: el SW nunca debe contestarla con el index.html de la app.
        navigateFallbackDenylist: [/\/ayuda(\/|$)/],
        clientsClaim: true,
        skipWaiting: true
      },
      includeAssets: ['CNAME'],
      manifest: {
        name: 'VG · Certificaciones',
        short_name: 'Certificaciones',
        description: 'Captura de certificaciones de campo (EUDR, RFA, GLOBAL G.A.P…), offline-first.',
        theme_color: '#0A1128',
        background_color: '#0A1128',
        display: 'standalone',
        start_url: '.',
        scope: '.'
      }
    })
  ],
  base: './',
  define: {
    __VG_VERSION__: JSON.stringify(versionApp()),
    __VG_BUILD__: JSON.stringify(AHORA)
  },
  build: {
    outDir: 'dist', chunkSizeWarningLimit: 2000,
    // El centro de ayuda (/ayuda/) es la plantilla común del kit, en public/ayuda/, copiada sin tocar (línea única
    // de los centros de ayuda, #17, 31-oct-2026): ya no es una segunda página de Vite.
    rollupOptions: { input: { main: resolve(__dirname, 'index.html') } }
  }
})
