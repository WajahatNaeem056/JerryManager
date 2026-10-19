/* PIF Settings page: spoof toggles, device picker, terminal (backend: features/pif_config.sh) */
(function () {
  'use strict';

  var ROOT = '/data/adb/modules/JerryManager';
  var FETCH_LOG = '/data/local/tmp/jerry_pif_fetch.log';
  var SPOOF_KEYS = ['spoofBuild', 'spoofVendingBuild', 'spoofProps', 'spoofProvider', 'spoofSignature', 'spoofVendingSdk'];
  var LABELS = { 'pif-fetch': 'Fetch', 'pif-view': 'View pif.prop' };

  // Fallback for previews without a device; on a device the list comes from `pif_config.sh devices`
  var DEVICES = [
    ['Random', 'random'],
    ['Pixel 6', 'oriole_beta'], ['Pixel 6 Pro', 'raven_beta'], ['Pixel 6a', 'bluejay_beta'],
    ['Pixel 7', 'panther_beta'], ['Pixel 7 Pro', 'cheetah_beta'], ['Pixel 7a', 'lynx_beta'],
    ['Pixel Fold', 'felix_beta'], ['Pixel Tablet', 'tangorpro_beta'],
    ['Pixel 8', 'shiba_beta'], ['Pixel 8 Pro', 'husky_beta'], ['Pixel 8a', 'akita_beta'],
    ['Pixel 9', 'tokay_beta'], ['Pixel 9 Pro', 'caiman_beta'], ['Pixel 9 Pro XL', 'komodo_beta'],
    ['Pixel 9 Pro Fold', 'comet_beta'], ['Pixel 9a', 'tegu_beta'],
    ['Pixel 10', 'frankel_beta'], ['Pixel 10 Pro', 'blazer_beta'], ['Pixel 10 Pro XL', 'mustang_beta'],
    ['Pixel 10 Pro Fold', 'rango_beta'], ['Pixel 10a', 'stallion_beta'],
    ['Pixel 11', 'cubs_beta'], ['Pixel 11 Pro', 'grizzly_beta'], ['Pixel 11 Pro XL', 'kodiak_beta'],
    ['Pixel 11 Pro Fold', 'yogi_beta']
  ];

  var busy = false;
  var devicesLoaded = false;
  var pickedDevice = 'random';
  var lastOnce = '';

  function $(id) { return document.getElementById(id); }

  function hasBridge() {
    return !!(window.ksu && typeof window.ksu.exec === 'function');
  }

  // Runs a shell command through JerryBridge (same channel as the rest of the app).
  // "@ROOT@" in cmd is replaced with the module directory.
  async function run(cmd) {
    var bridge = window.JerryBridge;
    try {
      if (bridge && typeof bridge.exec === 'function') {
        await bridge.initBridge();
        if (typeof bridge.getModuleDir === 'function' && bridge.getModuleDir()) ROOT = bridge.getModuleDir();
        var r = await bridge.exec(cmd.split('@ROOT@').join(ROOT));
        return { code: typeof r.code === 'number' ? r.code : 0, stdout: r.stdout || '', stderr: r.stderr || '' };
      }
      if (typeof window.shAsync === 'function') {
        var s = await window.shAsync(cmd.split('@ROOT@').join(ROOT));
        return { code: s.code, stdout: s.stdout || '', stderr: s.stderr || '' };
      }
    } catch (e) {
      return { code: -1, stdout: '', stderr: String((e && e.message) || e) };
    }
    return { code: -1, stdout: '', stderr: 'no bridge' };
  }

  function cfg(args) { return 'sh @ROOT@/features/pif_config.sh ' + args; }
  function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }

  /* ---------- terminal ---------- */

  function termLog(text, kind) {
    var el = $('pif-console');
    if (!el) return null;
    var line = document.createElement('div');
    line.className = 'pif-line' + (kind ? ' ' + kind : '');
    line.textContent = text;
    el.appendChild(line);
    el.scrollTop = el.scrollHeight;
    return line;
  }

  function classify(text) {
    if (/error|fail|could not|no such file|not active|invalid|unavailable|warning/i.test(text)) return 'err';
    if (/done|finish|saved|selected device|=true|=false/i.test(text)) return 'ok';
    return '';
  }

  function show(text) {
    String(text).split('\n').forEach(function (l) { if (l.trim()) termLog(l, classify(l)); });
  }

  function cmdLine(text) { termLog('$ ' + text, 'cmd'); }

  // Same message repeated (e.g. on every page open) is logged once
  function logOnce(text, kind) {
    if (text === lastOnce) return;
    lastOnce = text;
    termLog(text, kind);
  }

  function clearTerm() {
    var el = $('pif-console');
    if (el) el.textContent = '';
    lastOnce = '';
  }

  function report(res, fallback) {
    if (/No such file/.test(res.stderr)) {
      termLog('PIF backend not active yet. Reboot after flashing, then try again.', 'err');
      return;
    }
    show((res.stdout + '\n' + res.stderr).trim() || fallback || '');
  }

  /* ---------- toggles ---------- */

  function switches() { return document.querySelectorAll('#pif-panel md-switch'); }

  function updateBadge() {
    var on = 0;
    switches().forEach(function (sw) { if (sw.selected) on++; });
    var badge = $('pif-badge-spoof');
    if (badge) badge.textContent = on + '/' + SPOOF_KEYS.length;
  }

  function parseState(out) {
    var start = out.indexOf('{"spoofBuild"');
    var end = out.indexOf('}', start);
    if (start < 0 || end < 0) return null;
    try { return JSON.parse(out.slice(start, end + 1)); } catch (e) { return null; }
  }

  async function refresh() {
    if (!hasBridge()) {
      logOnce('Preview mode: no device connected, changes are not saved.', 'muted');
      updateBadge();
      return;
    }
    var res = await run(cfg('get'));
    var state = parseState(res.stdout);
    if (!state) {
      logOnce(/No such file/.test(res.stderr)
        ? 'PIF backend not active yet. Reboot after flashing, then open this page again.'
        : 'Could not read PIF state (code ' + res.code + ')', 'err');
      return;
    }
    switches().forEach(function (sw) { sw.selected = !!state[sw.getAttribute('data-pif')]; });
    updateBadge();
  }

  function bindSwitches() {
    switches().forEach(function (sw) {
      sw.addEventListener('change', async function () {
        updateBadge();
        if (!hasBridge()) return;
        var key = sw.getAttribute('data-pif');
        var value = sw.selected ? 'true' : 'false';
        var row = sw.closest('.pif-row');
        if (row) row.classList.add('pif-busy');
        cmdLine('set ' + key + '=' + value);
        var res = await run(cfg('set ' + key + ' ' + (sw.selected ? 1 : 0)));
        if (row) row.classList.remove('pif-busy');
        report(res, key + '=' + value);
        if (res.code !== 0) refresh();
      });
    });
  }

  /* ---------- buttons ---------- */

  function setBtn(id, on) {
    var btn = $(id);
    if (!btn) return;
    btn.disabled = !!on;
    var label = btn.querySelector('.pif-btn-label');
    if (label) label.textContent = on ? (id === 'pif-fetch' ? 'Fetching…' : 'Loading…') : LABELS[id];
  }

  async function doView() {
    if (busy) return;
    setBtn('pif-view', true);
    cmdLine('cat /data/adb/pif.prop');
    if (hasBridge()) {
      report(await run(cfg('view')), 'empty');
    } else {
      show('FINGERPRINT=google/…\nMODEL=Pixel 6a\nspoofBuild=true\n(preview)');
    }
    setBtn('pif-view', false);
  }

  // The fetch can outlast the bridge timeout, so it runs detached and its log is polled
  async function doFetch(device, source) {
    if (busy) return;
    busy = true;
    setBtn('pif-fetch', true);
    cmdLine('pif fetch ' + device + ' --' + source);

    if (!hasBridge()) {
      termLog('Preview mode: no device connected.', 'muted');
      await sleep(800);
    } else {
      var pending = termLog('Fetching…', 'muted');
      await run('rm -f ' + FETCH_LOG + '; (sh @ROOT@/features/pif_config.sh fetch ' + device + ' ' + source +
        ' > ' + FETCH_LOG + ' 2>&1; echo "__END__$?" >> ' + FETCH_LOG + ') >/dev/null 2>&1 &');

      var out = '';
      for (var i = 0; i < 45 && out.indexOf('__END__') < 0; i++) {
        await sleep(2000);
        out = (await run('cat ' + FETCH_LOG + ' 2>/dev/null')).stdout;
      }
      run('rm -f ' + FETCH_LOG);

      var exit = /__END__(\d*)/.exec(out);
      var ok = !!exit && exit[1] === '0';
      var text = out.replace(/__END__\d*\s*$/, '').trim();
      if (pending && pending.parentNode) pending.parentNode.removeChild(pending);
      if (/No such file/.test(text)) {
        termLog('PIF backend not active yet. Reboot after flashing, then try again.', 'err');
      } else {
        show(text || 'No output (timed out)');
        termLog(ok ? 'Done' : 'Failed (check internet)', ok ? 'ok' : 'err');
      }
    }

    setBtn('pif-fetch', false);
    busy = false;
    refresh();
  }

  /* ---------- device picker ---------- */

  async function loadDevices() {
    if (devicesLoaded || !hasBridge()) return;
    var res = await run(cfg('devices'));
    var list = res.stdout.split('\n').map(function (l) { return l.trim().split('|'); })
      .filter(function (p) { return p.length === 2 && /_beta$/.test(p[1]); });
    if (!list.length) return;
    DEVICES = [['Random', 'random']].concat(list);
    devicesLoaded = true;
    $('pif-picker-list').textContent = '';
  }

  function buildPicker() {
    var list = $('pif-picker-list');
    if (!list || list.childNodes.length) return;
    DEVICES.forEach(function (d) {
      var row = document.createElement('div');
      row.className = 'pif-dev' + (d[1] === pickedDevice ? ' sel' : '');
      row.setAttribute('data-dev', d[1]);
      var name = document.createElement('span');
      name.textContent = d[0];
      var radio = document.createElement('span');
      radio.className = 'pif-radio';
      row.appendChild(name);
      row.appendChild(radio);
      row.addEventListener('click', function () {
        pickedDevice = d[1];
        list.querySelectorAll('.pif-dev').forEach(function (r) {
          r.classList.toggle('sel', r.getAttribute('data-dev') === pickedDevice);
        });
      });
      list.appendChild(row);
    });
  }

  async function openPicker() {
    if (busy) return;
    await loadDevices();
    buildPicker();
    $('pif-picker').hidden = false;
    var selected = document.querySelector('#pif-picker-list .pif-dev.sel');
    if (selected && selected.scrollIntoView) selected.scrollIntoView({ block: 'center' });
  }

  function closePicker() { $('pif-picker').hidden = true; }

  function startFetch(source) {
    closePicker();
    doFetch(pickedDevice, source);
  }

  /* ---------- page ---------- */

  window.openPifSettings = function () {
    var panel = $('pif-settings-panel');
    if (!panel) return;
    panel.style.display = 'flex';
    var main = document.querySelector('main');
    if (main) main.style.overflow = 'hidden';
    refresh();
  };

  window.closePifSettings = function () {
    var panel = $('pif-settings-panel');
    if (!panel) return;
    closePicker();
    panel.style.display = 'none';
    var main = document.querySelector('main');
    if (main) main.style.overflow = '';
  };

  document.addEventListener('DOMContentLoaded', function () {
    if (!$('pif-panel')) return;
    bindSwitches();
    updateBadge();
    termLog('JerryManager PIF ready.', 'muted');

    $('pif-fetch').addEventListener('click', openPicker);
    $('pif-view').addEventListener('click', doView);
    $('pif-term-clear').addEventListener('click', clearTerm);
    $('pif-pick-cancel').addEventListener('click', closePicker);
    $('pif-pick-github').addEventListener('click', function () { startFetch('github'); });
    $('pif-pick-autopif').addEventListener('click', function () { startFetch('autopif'); });
    $('pif-picker').addEventListener('click', function (e) { if (e.target === this) closePicker(); });
  });
})();
