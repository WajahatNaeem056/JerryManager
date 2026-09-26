import { defineConfig } from 'vite';
import { resolve } from 'path';

export default defineConfig({
  root: 'src/webroot',
  base: './',
  publicDir: resolve(__dirname, 'src/webroot-public'),
  build: {
    outDir: resolve(__dirname, 'Module/webroot'),
    emptyOutDir: false,
    rollupOptions: {
      input: {
        main: resolve(__dirname, 'src/webroot/index.html'),
      },
    },
  },
});
