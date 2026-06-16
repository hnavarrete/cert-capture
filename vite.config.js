import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

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
        cleanupOutdatedCaches: true,
        navigateFallback: 'index.html',
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
  build: { outDir: 'dist', chunkSizeWarningLimit: 2000 }
})
