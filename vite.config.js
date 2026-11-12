import { defineConfig } from 'vite';
import { fileURLToPath } from 'node:url';
import { basename } from 'node:path';

const here = (p) => fileURLToPath(new URL(p, import.meta.url));

// WebUI source lives in webui-src/project. One entry (src/index.js) pulls in the app and
// the hand-written UI layer (src/ui), so the build emits a single assets/index-<hash>.js
// and a single assets/index-<hash>.css. The icon font is inlined as base64 (assetsInlineLimit);
// tools/inline-font.mjs then moves that @font-face block into index.html, while the rest of the
// CSS stays a separate file in assets/ linked with <link rel="stylesheet">. public/ holds the files copied
// verbatim: config.json, lang/, json/ and common/.
//
// Output goes to dist/webroot (git-ignored, emptied on every build); tools/package.sh
// copies it into the zip as webroot/.
// The hand-written scripts in src/ui used to load as separate <script type="module"> tags, so one throwing
// did not stop the rest. Bundled into one file a single top-level error would kill every script after it
// (tab switching, toggles...). Each one is wrapped so a failure only logs to the console and the others still run.
const isolateUiScripts = {
  name: 'isolate-ui-scripts',
  enforce: 'pre',
  transform(code, id) {
    const file = id.split('?')[0].replace(/\\/g, '/');
    if (!/\/src\/ui\/[^/]+\.js$/.test(file) || file.endsWith('/ui/index.js')) return null;
    const imports = [], body = [];
    for (const line of code.split('\n')) (/^import\s.+from\s.+;?\s*$/.test(line) ? imports : body).push(line);
    return `${imports.join('\n')}\ntry {\n${body.join('\n')}\n} catch (e) { console.warn(${JSON.stringify(basename(file))}, e); }\n`;
  },
};

export default defineConfig({
  plugins: [isolateUiScripts],
  root: here('webui-src/project'),
  base: './',
  publicDir: 'public',
  build: {
    outDir: here('dist/webroot'),
    emptyOutDir: true,
    assetsDir: 'assets',
    assetsInlineLimit: 100000,
    rollupOptions: { output: { inlineDynamicImports: true } },
  },
});
