/* RKP Keyboxes page (same full-page shell as Set Custom Keybox).
   Backend: features/rkp_catalog.sh list -> "id|name|expires_at" per eligible entry.
   Exit 0 = ok (zero or more entries); any other exit = error state.
   Tap a row once to install its keybox: features/rkp_catalog.sh install <id>. */
(function () {
  'use strict';

  var token = 0;
  var busy = false;

  function toast(m, err) { if (typeof window.jerryToast === 'function') window.jerryToast(m, err); }

  function $(id) { return document.getElementById(id); }

  async function run(cmd) {
    if (typeof window.jerryRun !== 'function') return { code: -1, stdout: '', stderr: 'no bridge' };
    var timer;
    var timeout = new Promise(function (resolve) {
      timer = setTimeout(function () {
        resolve({ code: -1, stdout: '', stderr: 'Timed out' });
      }, 30000);
    });
    try { return await Promise.race([window.jerryRun(cmd), timeout]); }
    finally { clearTimeout(timer); }
  }

  // "id|name|expires_at" lines -> entries; malformed lines are dropped
  function parse(stdout) {
    var out = [];
    String(stdout || '').split('\n').forEach(function (line) {
      var p = line.trim().split('|');
      if (p.length !== 3 || !/^[A-Za-z0-9._-]{1,64}$/.test(p[0]) || !/^\d{4}-\d{2}-\d{2}/.test(p[2])) return;
      out.push({ id: p[0], name: p[1], until: p[2].slice(0, 10) });
    });
    return out;
  }

  function errorText(r) {
    if (r.code === 10) return 'The RKP catalog source is not available yet.';
    if (r.code === 11) return 'Could not reach the RKP catalog. Check your connection.';
    if (r.code === 12) return 'The RKP catalog is invalid.';
    return 'Could not load the RKP catalog (exit ' + r.code + ').';
  }

  function installText(r) {
    if (r.code === 0) return 'RKP keybox installed';
    if (r.code === 11) return 'Could not reach the RKP catalog';
    if (r.code === 20) return 'This RKP keybox is no longer available';
    if (r.code === 21) return 'Keybox download failed';
    if (r.code === 22) return 'The keybox file is invalid';
    if (r.code === 23) return 'Keybox install failed';
    if (r.code === 24) return 'No keystore found';
    return 'Install failed (exit ' + r.code + ')';
  }

  async function install(e, hint) {
    busy = true;
    hint.textContent = 'Installing...';
    toast('Installing...', false);
    var r = await run("sh @ROOT@/features/rkp_catalog.sh install '" + e.id + "'");
    busy = false;
    hint.textContent = 'Tap to install';
    toast(installText(r), r.code !== 0);
  }

  function onRowTap(e, hint) {
    if (busy) return;
    install(e, hint);
  }

  function setState(state, message) {
    ['loading', 'empty', 'error', 'list'].forEach(function (s) {
      var el = $('rkp-' + s);
      if (el) el.style.display = s === state ? '' : 'none';
    });
    if (state === 'error') $('rkp-error-text').textContent = message || '';
  }

  function renderList(entries) {
    var box = $('rkp-list');
    box.textContent = '';
    entries.forEach(function (e) {
      var row = document.createElement('div');
      row.className = 'list-item';
      var icon = document.createElement('md-icon');
      icon.textContent = 'key';
      var content = document.createElement('div');
      content.className = 'list-item-content';
      var title = document.createElement('div');
      title.className = 'toggle-text';
      title.textContent = e.name || ('RKP Keybox ' + e.id.slice(0, 8));
      var sub = document.createElement('span');
      sub.className = 'supporting-text';
      sub.textContent = 'Valid until ' + e.until;
      var hint = document.createElement('span');
      hint.className = 'rkp-hint supporting-text';
      hint.style.display = 'block';
      hint.textContent = 'Tap to install';
      content.appendChild(title);
      content.appendChild(sub);
      content.appendChild(hint);
      row.style.cursor = 'pointer';
      row.addEventListener('click', function () { onRowTap(e, hint); });
      row.appendChild(icon);
      row.appendChild(content);
      box.appendChild(row);
    });
  }

  async function load() {
    var mine = ++token;
    setState('loading');
    var r = await run('sh @ROOT@/features/rkp_catalog.sh list');
    if (mine !== token) return; // a newer load (Retry) owns the screen
    if (r.code !== 0) { setState('error', errorText(r)); return; }
    var entries = parse(r.stdout);
    if (!entries.length) { setState('empty'); return; }
    renderList(entries);
    setState('list');
  }

  function paintBehind(panel, open) {
    [document.documentElement, document.body].forEach(function (el) {
      if (!el) return;
      if (open) el.style.setProperty('background', getComputedStyle(panel).background, 'important');
      else el.style.removeProperty('background');
    });
  }

  function setPanel(open) {
    var panel = $('rkp-panel');
    if (!panel) return;
    panel.style.display = open ? 'flex' : 'none';
    paintBehind(panel, open);
    var main = document.querySelector('main');
    if (main) main.style.overflow = open ? 'hidden' : '';
  }

  window.openRkpPanel = function () { setPanel(true); load(); };
  window.closeRkpPanel = function () { token++; setPanel(false); };
  window.__rkpPanel = { parse: parse, load: load, errorText: errorText };

  document.addEventListener('DOMContentLoaded', function () {
    var retry = $('rkp-retry');
    if (retry) retry.addEventListener('click', load);
  });
})();
