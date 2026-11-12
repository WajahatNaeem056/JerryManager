// Runs after `vite build`. The CSS stays a separate file in assets/ (linked from index.html),
// but the base64 icon font (@font-face with a data: URL) is moved out of it into a small
// <style> block in index.html, so the font is available as soon as index.html is parsed.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../dist/webroot');
const assets = path.join(root, 'assets');
const cssName = fs.readdirSync(assets).find((f) => /^index-[\w-]+\.css$/.test(f));
if (!cssName) { console.error('inline-font: no index css found in assets/'); process.exit(1); }

const cssPath = path.join(assets, cssName);
const css = fs.readFileSync(cssPath, 'utf8');
const blocks = css.match(/@font-face\s*\{[^}]*data:font\/[^}]*\}/g) || [];
if (!blocks.length) { console.error('inline-font: no base64 @font-face found in ' + cssName); process.exit(1); }

const fontCss = blocks.join('');
if (/<\/style/i.test(fontCss)) { console.error('inline-font: font css contains </style>, refusing to inline'); process.exit(1); }

const htmlPath = path.join(root, 'index.html');
const html = fs.readFileSync(htmlPath, 'utf8');
const link = /<link rel="stylesheet"[^>]*href="\.\/assets\/index-[\w-]+\.css"[^>]*>/;
if (!link.test(html)) { console.error('inline-font: stylesheet link not found in index.html'); process.exit(1); }

let rest = css;
for (const b of blocks) rest = rest.split(b).join('');
fs.writeFileSync(cssPath, rest);
fs.writeFileSync(htmlPath, html.replace(link, (m) => `<style>${fontCss}</style>${m}`));
console.log(`inline-font: moved ${blocks.length} @font-face (${(fontCss.length / 1024).toFixed(1)} KB) into index.html; CSS stays in assets/${cssName}`);
