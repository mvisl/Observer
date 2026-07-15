import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  base: process.env.OBSERVER_GITHUB_PAGES === "1" ? "/Observer/" : "/",
  plugins: [react()],
  server: {
    host: "127.0.0.1",
    port: 5173,
    proxy: {
      "/api": "http://127.0.0.1:43127"
    }
  },
  build: {
    sourcemap: true,
    assetsDir: "assets"
  }
});
