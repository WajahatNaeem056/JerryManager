// Removes stale Vite output (hashed index-*.js/css and leftover compiled chunks)
// from Jerry/webroot/assets before a rebuild. Hand-written files are re-copied from
// webui-src/project/public by the build, so they are never touched here.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../Jerry/webroot/assets');
const stale = /^(index-[\w-]+\.(js|css)|bridge-[\w-]+\.js|rolldown-runtime-[\w-]+\.js)$/;
if (fs.existsSync(dir)) {
  for (const f of fs.readdirSync(dir)) {
    if (stale.test(f)) { fs.rmSync(path.join(dir, f)); console.log('removed stale', f); }
  }
}
