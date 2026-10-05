import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))

// La página de ayuda NO registra el service worker ni enlaza el manifest: vite-plugin-pwa los inyecta con rutas
// relativas (./registerSW.js, ./manifest.webmanifest) que desde /ayuda/ apuntarían a archivos inexistentes.
// El SW de la app (alcance /) ya cubre /ayuda/ cuando el usuario abrió la app antes.
const ayudaSinPwa = {
  name: 'ayuda-sin-pwa', apply: 'build', enforce: 'post',
  generateBundle(_, bundle) {
    const h = bundle['ayuda/index.html']
    if (!h) return
    h.source = String(h.source)
      .replace(/<link rel="manifest"[^>]*>/g, '')
      .replace(/<script[^>]*registerSW\.js[^>]*><\/script>/g, '')
  }
}

// base relativo para que funcione bajo subcarpeta en GitHub Pages.
export default defineConfig({
  plugins: [
    react(),
    ayudaSinPwa,
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
        // hasta la próxima versión del SW). Los videos viven en otro origen (vg-cert-videos.pages.dev) y el SW
        // no tiene runtimeCaching: no los intercepta.
        globIgnores: ['**/ayuda/ayuda.json', '**/node_modules/**'],
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
  build: {
    outDir: 'dist', chunkSizeWarningLimit: 2000,
    // dos páginas: la app (/) y el centro de ayuda en video (/ayuda/), que GitHub Pages sirve como archivo real
    rollupOptions: { input: { main: resolve(__dirname, 'index.html'), ayuda: resolve(__dirname, 'ayuda/index.html') } }
  }
})
