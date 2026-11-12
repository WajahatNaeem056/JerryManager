/* Set Custom Keybox full page (same shell as Set Security Patch / Verified Boot Hash).
   Backend: features/keybox.sh reads kb_custom_type / kb_custom_value from the config. */
(function () {
  'use strict';

  var selected = '';
  var busy = false;

  function $(id) { return document.getElementById(id); }
  function toast(m, err) { if (typeof window.jerryToast === 'function') window.jerryToast(m, err); }
  function q(v) { return "'" + String(v).replace(/'/g, "'\\''") + "'"; }

  async function run(cmd) {
    if (typeof window.jerryRun !== 'function') return { code: -1, stdout: '', stderr: 'no bridge' };
    var timer;
    var timeout = new Promise(function (resolve) {
      timer = setTimeout(function () {
        resolve({ code: -1, stdout: '', stderr: 'Timed out, check the logs' });
      }, 60000);
    });
    try { return await Promise.race([window.jerryRun(cmd), timeout]); }
    finally { clearTimeout(timer); }
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

  function setPanel(open) {
    var panel = $('keybox-panel');
    if (!panel) return;
    panel.style.display = open ? 'flex' : 'none';
    paintBehind(panel, open);
    var main = document.querySelector('main');
    if (main) main.style.overflow = open ? 'hidden' : '';
  }

  function render() {
    $('kb-file-name').textContent = selected ? selected.split('/').pop() : 'No file selected';
    $('kb-file-path').textContent = selected || '-';
  }

  function cfgPrefix() {
    return '. @ROOT@/lib/paths.sh && . @ROOT@/lib/config_env.sh && MODDIR=@ROOT@';
  }

  async function loadBackend() {
    var el = $('kb-backend-name');
    if (!el) return;
    var home = $('keystore-backend-value');
    var cached = home && home.textContent && home.textContent !== '—' ? home.textContent : '';
    if (cached) el.textContent = cached;
    try {
      var info = await (await fetch('/json/keybox_info.json?ts=' + Date.now())).json();
      if (info && info.backend) el.textContent = info.backend;
      else if (!cached) el.textContent = '—';
    } catch (e) {
      if (!cached) el.textContent = '—';
    }
  }

  window.openCustomKeybox = function () { setPanel(true); render(); loadBackend(); };
  window.closeCustomKeybox = function () { setPanel(false); };

  // The line that says why it failed (last error-looking line), without timestamp / [TAG] / "Error:"
  function failReason(res) {
    var lines = String((res.stdout || '') + '\n' + (res.stderr || '')).split(/\r?\n/)
      .map(function (l) { return l.trim(); }).filter(Boolean);
    var hit = '';
    for (var i = lines.length - 1; i >= 0; i--) {
      if (/\b(error|failed|invalid|not found|cannot|unable|denied|timed out)\b/i.test(lines[i])) { hit = lines[i]; break; }
    }
    if (!hit) hit = lines[lines.length - 1] || 'Install failed';
    hit = hit.replace(/^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}\s*/, '').replace(/^\[[^\]]*\]\s*/, '').replace(/^(error|failed)\s*:\s*/i, '').trim();
    return 'Failed: ' + (hit.length > 140 ? hit.slice(0, 137) + '...' : hit || 'Install failed');
  }

  async function apply() {
    if (busy) return;
    if (!selected) { toast('Please select a file', true); return; }
    busy = true;
    var btn = $('kb-apply');
    var lbl = btn.querySelector('.ph-save-label');
    var oldLbl = lbl ? lbl.textContent : '';
    btn.disabled = true;
    if (lbl) lbl.textContent = 'Installing...';
    try {
      var cmd = cfgPrefix() + ' && cfg_set kb_custom_type "path" && cfg_set kb_custom_value ' + q(selected) +
        ' && sh @ROOT@/features/keybox.sh';
      var res = await run(cmd);
      if (res.code === 0) toast('Done', false);
      else toast(failReason(res), true);
    } finally {
      busy = false;
      btn.disabled = false;
      if (lbl) lbl.textContent = oldLbl;
    }
  }

  async function clearIt() {
    if (busy) return;
    busy = true;
    try {
      var res = await run(cfgPrefix() + ' && cfg_delete kb_custom_type && cfg_delete kb_custom_value');
      selected = '';
      render();
      toast(res.code === 0 ? 'Custom keybox cleared' : 'Failed to clear', res.code !== 0);
    } finally { busy = false; }
  }

  document.addEventListener('DOMContentLoaded', function () {
    if (!$('keybox-panel')) return;
    $('kb-pick-row').addEventListener('click', function () {
      if (typeof window.jerryOpenFileBrowser !== 'function') return;
      window.jerryOpenFileBrowser(function (path) { selected = path; render(); });
    });
    $('kb-apply').addEventListener('click', apply);
    $('kb-clear-row').addEventListener('click', clearIt);
  });
})();
