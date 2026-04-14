import {defineConfig} from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  base: "/",
  plugins: [react()],
  server: {
    port: 5173,
    // In dev, proxy API calls to vitasense_server running on 8000
    proxy: {
      "/analyze": "http://localhost:6767",
      "/health":  "http://localhost:6767",
    },
  },
  build: {
    // Output goes to app/ui/dist/ — vitasense_server.py reads from there
    outDir: "dist",
    emptyOutDir: true,
  },
});
 