import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// strictPort is load-bearing, not a preference. Vite's default on a busy port is
// to increment and print a different URL; scripts/lib.sh wait_for_service polls
// one specific port and asserts the listener descends from the PID it recorded,
// so a silent hop to 5174 becomes a 60s timeout with a log that claims success.
// Failing immediately with EADDRINUSE is what service_failed can actually report.
//
// PORT is supplied by service_env in scripts/lib.sh. The 5173 fallback keeps a
// bare `npm run dev` on the same URL as `make ui`.
export default defineConfig({
  plugins: [react()],
  server: {
    port: Number(process.env.PORT) || 5173,
    strictPort: true,
  },
})
