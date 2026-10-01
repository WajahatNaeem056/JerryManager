import { defineConfig } from 'vite';

// Hand-written scripts that index.html loads as plain modules. They live in
// ./public/assets (copied verbatim) and are injected AFTER Vite's own HTML
// processing so Vite does not bundle or rename them.
const LEGACY_SCRIPTS = ["network-status.js", "rom-status.js", "pif-status.js", "module-configs.js", "nav-swipe-anim.js", "keybox-indicator.js", "swipe-nav.js", "app-core.js", "app-targeting.js"];

const injectLegacyScripts = () => ({
  name: 'jerrymanager-inject-legacy-scripts',
  transformIndexHtml: {
    order: 'post',
    handler: () => LEGACY_SCRIPTS.map((file) => ({
      tag: 'script',
      attrs: { type: 'module', src: `./assets/${file}` },
      injectTo: 'body',
    })),
  },
});

// Output goes straight into the module's webroot. Never empty it: it also holds
// files that were never compiled (they are re-copied from ./public anyway).
export default defineConfig({
  base: './',
  publicDir: 'public',
  plugins: [injectLegacyScripts()],
  build: {
    outDir: '../../Jerry/webroot',
    emptyOutDir: false,
    assetsDir: 'assets',
  },
});
