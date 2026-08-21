import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Dev server proxies /api to the Laravel backend so the frontend and API
// share an origin (avoids CORS in development). In production the built
// static assets are CDN-served and point at the API base via VITE_API_BASE.
export default defineConfig({
  plugins: [react()],
  build: {
    rollupOptions: {
      input: {
        // Two entry points, one codebase: the staff console and the
        // customer portal share components, theme and i18n but ship as
        // separate documents with separate auth.
        main: "index.html",
        portal: "portal.html",
        technician: "technician.html",
        platform: "platform.html",
      },
    },
  },
  server: {
    port: 5173,
    proxy: {
      "/api": {
        target: process.env.VITE_API_TARGET || "http://localhost:8000",
        changeOrigin: true,
      },
    },
  },
});
