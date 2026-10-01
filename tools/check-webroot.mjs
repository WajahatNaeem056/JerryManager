// Sanity check for webroot/: every script/stylesheet referenced by index.html and every
// relative import('./x.js') inside webroot/assets must exist. Run before packaging.
//   node tools/check-webroot.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../Jerry/webroot');
const problems = [];
const need = (from, rel) => {
  const target = path.resolve(path.dirname(from), rel);
  if (!fs.existsSync(target)) problems.push(`${path.relative(root, from)} -> ${rel} (missing)`);
};

const html = path.join(root, 'index.html');
const src = fs.readFileSync(html, 'utf8');
for (const m of src.matchAll(/(?:src|href)="(\.\/[^"]+\.(?:js|css))"/g)) need(html, m[1]);

const assets = path.join(root, 'assets');
for (const f of fs.readdirSync(assets).filter((n) => n.endsWith('.js'))) {
  const file = path.join(assets, f);
  const text = fs.readFileSync(file, 'utf8');
  for (const m of text.matchAll(/(?:import\(\s*|from\s*)['"`](\.{1,2}\/[^'"`]+\.js)['"`]/g)) need(file, m[1]);
}

if (problems.length) { console.error('webroot check FAILED:\n  ' + problems.join('\n  ')); process.exit(1); }
console.log('webroot check OK');
