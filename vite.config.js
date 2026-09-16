import { defineConfig } from 'vite';

export default defineConfig({
  root: '.',
  build: {
    outDir: 'Jerry/webroot/assets',
    emptyOutDir: false, // preserve app-core.js, module-configs.js, etc.
    rollupOptions: {
      input: {
        material: 'src/material-entry.js',
      },
    },
  },
});
