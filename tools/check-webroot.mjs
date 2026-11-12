// Sanity check for the built webroot (dist/webroot). Runs as part of `npm run build`.
//   node tools/check-webroot.mjs
//
// Checks:
//   1. every script/stylesheet referenced by index.html exists
//   2. index.html links the stylesheet from assets/ (the CSS must NOT be inlined into index.html;
//      only the base64 @font-face block may live in index.html, see tools/inline-font.mjs)
//   3. every relative import('./x.js') inside assets/*.js exists
//   4. every relative url(...) inside assets/*.css exists (data: URLs are fine)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../dist/webroot');
const problems = [];
const need = (from, rel) => {
  const target = path.resolve(path.dirname(from), rel.split(/[?#]/)[0]);
  if (!fs.existsSync(target)) problems.push(`${path.relative(root, from)} -> ${rel} (missing)`);
};

const html = path.join(root, 'index.html');
const src = fs.readFileSync(html, 'utf8');

// 1. everything index.html references
for (const m of src.matchAll(/(?:src|href)="(\.\/[^"]+\.(?:js|css))"/g)) need(html, m[1]);

// 2. stylesheet must be an external file in assets/, not an inline <style> blob
const cssLinks = [...src.matchAll(/<link\b[^>]*\brel="stylesheet"[^>]*\bhref="(\.\/assets\/[^"]+\.css)"[^>]*>/g)];
if (!cssLinks.length) problems.push('index.html: no <link rel="stylesheet"> pointing to ./assets/*.css');
for (const m of src.matchAll(/<style\b[^>]*>([\s\S]*?)<\/style>/gi)) {
  const body = m[1].replace(/@font-face\s*\{[^}]*\}/g, ''); // the base64 font block is allowed in index.html
  if (body.length > 20000) {
    problems.push(`index.html: large inlined stylesheet found in a <style> block (${(body.length / 1024).toFixed(1)} KB), CSS must stay in assets/`);
  }
}

// 3. relative imports inside JS, 4. relative url() inside CSS
const assets = path.join(root, 'assets');
for (const f of fs.readdirSync(assets)) {
  const file = path.join(assets, f);
  const text = fs.readFileSync(file, 'utf8');
  if (f.endsWith('.js')) {
    for (const m of text.matchAll(/(?:import\(\s*|from\s*)['"`](\.{1,2}\/[^'"`]+\.js)['"`]/g)) need(file, m[1]);
  } else if (f.endsWith('.css')) {
    for (const m of text.matchAll(/url\(\s*(['"]?)([^'")]+)\1\s*\)/g)) {
      const u = m[2].trim();
      if (/^(data:|https?:|\/\/|#)/i.test(u)) continue;
      need(file, u);
    }
  }
}

if (problems.length) { console.error('webroot check FAILED:\n  ' + problems.join('\n  ')); process.exit(1); }
console.log('webroot check OK');
