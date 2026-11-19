/* RKP Keyboxes page (same full-page shell as Set Custom Keybox).
   Backend: features/rkp_catalog.sh list -> "id|name|expires_at" per eligible entry.
   Exit 0 = ok (zero or more entries); any other exit = error state.
   Select a row (radio), then tap Install: features/rkp_catalog.sh install <id>. */
(function () {
  'use strict';

  var token = 0;
  var busy = false;
  var sel = null; // selected row

  function toast(m, err) { if (typeof window.jerryToast === 'function') window.jerryToast(m, err); }

  function $(id) { return document.getElementById(id); }

  function mk(tag, cls, txt) {
    var x = document.createElement(tag);
    if (cls) x.className = cls;
    if (txt != null) x.textContent = txt;
    return x;
  }

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

  // "2026-11-29" -> "29 Nov 2026" in the device locale
  function fmtDate(s) {
    var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(s);
    if (!m) return s;
    try {
      return new Date(+m[1], +m[2] - 1, +m[3])
        .toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
    } catch (e) { return s; }
  }

  // bottom Install button: idle | busy | ok | err
  function setBtn(state) {
    var b = $('rkp-install');
    if (!b) return;
    b.setAttribute('data-state', state);
    b.setAttribute('aria-busy', state === 'busy' ? 'true' : 'false');
    b.disabled = state === 'busy' || state === 'ok' || (state === 'idle' && !sel);
    b.querySelector('.rkp-btn-label').textContent =
      state === 'busy' ? 'Installing\u2026' : state === 'ok' ? 'Installed' : state === 'err' ? 'Try again' : 'Install';
    b.querySelector('.rkp-btn-icon').textContent =
      state === 'ok' ? 'check_circle' : state === 'err' ? 'refresh' : 'check';
  }

  // row subtitle: idle | busy | ok | err
  function setRow(row, state, msg) {
    var meta = row.querySelector('.rkp-meta');
    row.setAttribute('data-state', state);
    meta.textContent = '';
    if (state === 'idle') {
      meta.appendChild(document.createTextNode('Valid until '));
      meta.appendChild(mk('span', 'rkp-date', fmtDate(row._rkp.until)));
    } else {
      meta.textContent = state === 'busy' ? 'Installing\u2026' : state === 'ok' ? 'Installed' : msg;
    }
  }

  function pick(row) {
    if (busy || sel === row) return;
    if (sel) {
      clearTimeout(sel._rkpT);
      setRow(sel, 'idle');
      sel.setAttribute('aria-checked', 'false');
    }
    sel = row;
    row.setAttribute('aria-checked', 'true');
    setRow(row, 'idle');
    setBtn('idle');
  }

  async function install(entry, row) {
    var list = $('rkp-list');
    busy = true;
    if (list) list.classList.add('is-busy');
    clearTimeout(row._rkpT);
    setRow(row, 'busy');
    setBtn('busy');
    var r = await run("sh @ROOT@/features/rkp_catalog.sh install '" + entry.id + "'");
    busy = false;
    if (list) list.classList.remove('is-busy');
    var ok = r.code === 0;
    var msg = installText(r);
    setRow(row, ok ? 'ok' : 'err', msg);
    setBtn(ok ? 'ok' : 'err');
    toast(msg, !ok);
    // fall back to the idle look after a moment
    row._rkpT = setTimeout(function () {
      if (busy) return;
      setRow(row, 'idle');
      if (sel === row) setBtn('idle');
    }, ok ? 3000 : 6000);
  }

  function setState(state, message) {
    ['loading', 'empty', 'error', 'list'].forEach(function (s) {
      var el = $('rkp-' + s);
      if (el) el.style.display = s === state ? '' : 'none';
    });
    var sub = $('rkp-sub');
    if (sub) sub.style.display = state === 'list' ? '' : 'none';
    var bar = $('rkp-bar');
    if (bar) bar.style.display = state === 'list' ? '' : 'none';
    if (state === 'error') $('rkp-error-text').textContent = message || '';
  }

  function renderList(entries) {
    var box = $('rkp-list');
    box.textContent = '';
    box.classList.remove('is-busy');
    sel = null;
    entries.forEach(function (e) {
      var name = e.name || ('RKP Keybox ' + e.id.slice(0, 8));
      var row = mk('div', 'list-item rkp-item');
      row._rkp = e;
      row.setAttribute('role', 'radio');
      row.setAttribute('aria-checked', 'false');
      row.setAttribute('aria-label', name);
      row.tabIndex = 0;
      var content = mk('div', 'list-item-content');
      var meta = mk('span', 'supporting-text rkp-meta');
      var radio = mk('span', 'rkp-radio');
      meta.setAttribute('aria-live', 'polite');
      radio.setAttribute('aria-hidden', 'true');
      content.appendChild(mk('div', 'toggle-text', name));
      content.appendChild(meta);
      row.appendChild(mk('md-icon', null, 'key'));
      row.appendChild(content);
      row.appendChild(radio);
      row.appendChild(document.createElement('md-ripple'));
      row.addEventListener('click', function () { pick(row); });
      row.addEventListener('keydown', function (ev) {
        if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); pick(row); }
      });
      box.appendChild(row);
      setRow(row, 'idle');
    });
    setBtn('idle');
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
    var btn = $('rkp-install');
    if (btn) btn.addEventListener('click', function () { if (sel && !busy) install(sel._rkp, sel); });
    var retry = $('rkp-retry');
    if (retry) {
      retry.addEventListener('click', load);
      retry.addEventListener('keydown', function (ev) {
        if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); load(); }
      });
    }
  });
})();
