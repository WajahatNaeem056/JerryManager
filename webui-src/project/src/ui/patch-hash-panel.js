/* Set Security Patch and Set Verified Boot Hash pages (backend: features/security_patch.sh, features/boot_hash.sh).
   Boot keeps writing both automatically; these pages apply a value by hand after boot. */
(function () {
  'use strict';

  var DATE_RE = /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;
  var HASH_RE = /^[0-9a-f]{64}$/;
  var PATCH = 'sh @ROOT@/features/security_patch.sh';
  var HASH = 'sh @ROOT@/features/boot_hash.sh';

  var busy = false;

  function $(id) { return document.getElementById(id); }

  function tr(key, fallback) {
    return (typeof window.__jerryGetTranslation === 'function' && window.__jerryGetTranslation(key)) || fallback;
  }

  function toast(message, isError, plain) {
    if (typeof window.jerryToast === 'function') window.jerryToast(message, isError, plain);
  }

  async function run(cmd) {
    if (typeof window.jerryRun !== 'function') return { code: -1, stdout: '', stderr: 'no bridge' };
    // The shared bridge has no timeout: a hung script would leave the page busy forever with no message
    var timer;
    var timeout = new Promise(function (resolve) {
      timer = setTimeout(function () {
        resolve({ code: -1, stdout: '', stderr: tr('ph_timeout', 'Timed out, check the logs') });
      }, 45000);
    });
    try {
      return await Promise.race([window.jerryRun(cmd), timeout]);
    } finally {
      clearTimeout(timer);
    }
  }

  // Backend scripts print "KEY=value" lines next to their normal log lines
  function field(out, name) {
    var m = new RegExp('^' + name + '=(.*)$', 'm').exec(out || '');
    return m ? m[1].trim() : '';
  }

  // die() logs "[ERROR] message" to stdout
  function errorOf(res) {
    var m = /\[ERROR\] (.*)$/m.exec(res.stdout || '');
    return m ? m[1].trim() : ((res.stderr || '').trim() || tr('ph_failed', 'Failed'));
  }


  // Keep the page behind the panel the same colour as the panel, so a stale WebView
  // height (e.g. after the keyboard closes) can never show a white strip underneath
  function paintBehind(panel, open) {
    var els = [document.documentElement, document.body];
    els.forEach(function (el) {
      if (!el) return;
      if (open) {
        el.style.setProperty('background', getComputedStyle(panel).background, 'important');
      } else {
        el.style.removeProperty('background');
      }
    });
  }

  function setPanel(id, open) {
    var panel = $(id);
    if (!panel) return;
    panel.style.display = open ? 'flex' : 'none';
    paintBehind(panel, open);
    if (!open && document.activeElement && document.activeElement.blur) document.activeElement.blur();
    var main = document.querySelector('main');
    if (main) main.style.overflow = open ? 'hidden' : '';
  }

  // Runs one action with a row spinner (or a disabled button) and blocks other actions meanwhile
  async function withBusy(el, task) {
    if (busy) return;
    busy = true;
    var spinner = el.querySelector('.action-spinner');
    el.classList.add('pif-busy');
    if (spinner) spinner.classList.remove('hidden');
    try {
      await task();
    } finally {
      el.classList.remove('pif-busy');
      if (spinner) spinner.classList.add('hidden');
      busy = false;
    }
  }

  /* ---------- security patch ---------- */

  async function loadPatch() {
    var date = field((await run(PATCH + ' --show')).stdout, 'DATE');
    if (DATE_RE.test(date)) $('patch-input').value = date;
  }

  // Same source as the Custom Keybox page: home row first, then keybox_info.json
  async function loadBackend() {
    var el = $('patch-backend-name');
    if (!el) return;
    var home = $('keystore-backend-value');
    var cached = home && home.textContent && home.textContent !== '\u2014' ? home.textContent : '';
    if (cached) el.textContent = cached;
    try {
      var info = await (await fetch('/json/keybox_info.json?ts=' + Date.now())).json();
      if (info && info.backend) el.textContent = info.backend;
      else if (!cached) el.textContent = '\u2014';
    } catch (e) {
      if (!cached) el.textContent = '\u2014';
    }
  }

  // Reads the newest patch date from the Pixel bulletin and puts it in the field; Save writes it
  function fetchPatch() {
    return withBusy($('patch-fetch'), async function () {
      toast(tr('patch_fetching', 'Fetching from Pixel bulletin...'), false, true);
      var res = await run(PATCH + ' --fetch');
      var date = field(res.stdout, 'DATE');
      if (res.code === 0 && DATE_RE.test(date)) {
        $('patch-input').value = date;
        toast(tr('patch_fetched', 'Fetched from Pixel bulletin'), false);
      } else {
        toast(errorOf(res), true);
      }
    });
  }

  function savePatch() {
    var input = $('patch-input');
    var date = input.value.trim();
    if (!DATE_RE.test(date)) {
      toast(tr('patch_invalid', 'Enter the date as YYYY-MM-DD'), true);
      input.focus();
      return;
    }
    input.blur();
    return withBusy($('patch-save'), async function () {
      var res = await run(PATCH + ' --set ' + date);
      if (res.code === 0 && field(res.stdout, 'DATE') === date) {
        toast(tr('patch_saved', 'Security patch set to {date}').replace('{date}', date), false);
      } else {
        toast(errorOf(res), true);
      }
    });
  }

  /* ---------- boot hash ---------- */

  function normHash(text) { return String(text).replace(/\s+/g, '').toLowerCase(); }

  function validHash(hash) { return HASH_RE.test(hash) && /[1-9a-f]/.test(hash); }

  async function loadHash() {
    var out = (await run(HASH + ' --show')).stdout;
    var hash = field(out, 'HASH');
    var source = field(out, 'SOURCE');
    $('hash-current').textContent = hash || '-';
    var label = $('hash-source');
    label.textContent = source === 'custom' ? tr('hash_source_custom', 'Custom hash in use')
      : source === 'cache' ? tr('hash_source_auto', 'Automatic hash in use')
      : tr('hash_source_none', 'No hash stored yet');
    $('hash-input').value = source === 'custom' ? hash : '';
  }

  // Read-only boot state reported by the bootloader; shown for debugging, never written
  async function loadVbmeta() {
    var out = (await run('for p in size hash_alg avb_version device_state; do echo "$p=$(getprop ro.boot.vbmeta.$p)"; done')).stdout;
    [['size', 'size'], ['alg', 'hash_alg'], ['avb', 'avb_version'], ['state', 'device_state']].forEach(function (f) {
      $('vbmeta-' + f[0]).textContent = field(out, f[1]) || '-';
    });
  }

  // The hash is passed as plain hex only after validation, so it needs no shell quoting
  function saveHash() {
    var hash = normHash($('hash-input').value);
    if (!validHash(hash)) {
      toast(tr('hash_invalid', 'Enter 64 hex characters (not all zeros)'), true);
      $('hash-input').focus();
      return;
    }
    $('hash-input').blur();
    return withBusy($('hash-save'), async function () {
      var res = await run(HASH + ' --set ' + hash);
      if (res.code === 0) {
        toast(tr('hash_saved', 'Boot hash applied'), false);
        await loadHash();
      } else {
        toast(errorOf(res), true);
      }
    });
  }

  // Empty --set drops the custom pin and re-resolves the hash from the device
  function resetHash() {
    return withBusy($('hash-reset'), async function () {
      var res = await run(HASH + " --set ''");
      if (res.code === 0) {
        toast(tr('hash_reset_done', 'Custom hash cleared'), false);
        await loadHash();
      } else {
        toast(errorOf(res), true);
      }
    });
  }

  function refreshHash() {
    return withBusy($('hash-refresh'), async function () {
      toast(tr('hash_refreshing', 'Refreshing boot hash...'), false, true);
      var res = await run(HASH + ' --refresh');
      if (res.code === 0) {
        toast(tr('hash_refreshed', 'Boot hash refreshed'), false);
        await loadHash();
      } else {
        toast(errorOf(res), true);
      }
    });
  }

  // WebViews often refuse clipboard reads; the field then gets focus so the user can long-press to paste
  async function pasteHash() {
    var input = $('hash-input');
    var text;
    try {
      text = normHash(await navigator.clipboard.readText());
    } catch (e) {
      input.focus();
      toast(tr('hash_paste_blocked', 'Clipboard unavailable, long-press the field to paste'), true);
      return;
    }
    if (!validHash(text)) {
      toast(tr('hash_invalid', 'Enter 64 hex characters (not all zeros)'), true);
      return;
    }
    input.value = text;
  }

  /* ---------- pages ---------- */

  window.openSecurityPatch = function () {
    setPanel('patch-panel', true);
    loadPatch();
    loadBackend();
  };
  window.closeSecurityPatch = function () { setPanel('patch-panel', false); };

  window.openBootHash = function () {
    setPanel('hash-panel', true);
    loadHash();
    loadVbmeta();
  };
  window.closeBootHash = function () { setPanel('hash-panel', false); };

  document.addEventListener('DOMContentLoaded', function () {
    if (!$('patch-panel') || !$('hash-panel')) return;
    $('patch-save').addEventListener('click', savePatch);
    if ($('patch-fetch')) $('patch-fetch').addEventListener('click', fetchPatch);
    $('hash-save').addEventListener('click', saveHash);
    $('hash-reset').addEventListener('click', resetHash);
    if ($('hash-paste')) $('hash-paste').addEventListener('click', pasteHash);
    $('hash-refresh').addEventListener('click', refreshHash);
  });
})();
