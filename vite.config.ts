import { fileURLToPath, URL } from "node:url";

import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

import { nodePolyfills } from "vite-plugin-node-polyfills";
import rollupNodePolyfills from "rollup-plugin-polyfill-node";

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [
    nodePolyfills({
      protocolImports: true,
    }),
    react(),
  ],
  build: {
    target: "esnext",
    rollupOptions: {
      plugins: [rollupNodePolyfills()],
      output: {
        // Split React (always eager, rarely changes) into its own long-cached
        // chunk so shipping an app update doesn't re-download it. Deliberately
        // NOT chunking the wallet stack — Vite already lazy-loads the heavy
        // connector SDKs (metamask/walletconnect/coinbase) on modal-open, and
        // forcing them into a manual vendor chunk would make them eager.
        manualChunks(id) {
          if (!id.includes("node_modules")) return;
          if (/[\\/](react|react-dom|react-router|react-router-dom|scheduler)[\\/]/.test(id)) return "react-vendor";
        },
      },
    },
    commonjsOptions: {
      transformMixedEsModules: true,
    },
  },
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
    },
  },
  css: {
    preprocessorOptions: {
      scss: {
        additionalData: `
          @use "sass:math";
          @import "./src/assets/styles/_variables.scss";
          @import "./src/assets/styles/_mixins.scss";
        `,
      },
    },
  },
});
