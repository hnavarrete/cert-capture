import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// base relativo para que funcione bajo subcarpeta en GitHub Pages.
export default defineConfig({
  plugins: [react()],
  base: './',
  build: { outDir: 'dist', chunkSizeWarningLimit: 2000 }
})
