/* Device RKP Issuer page (own full page, opened from Actions > RKP Keyboxes).
   Backend: features/rkp_device.sh status | provision <auto|v1|v2|v1-native>.
   duckd prints ONE JSON envelope line: {api:1, ok, command, data | error:{code,message}}.
   status data: prerequisites_met, blockers[], android_arm64, root, library_present/_path,
   device_present/_path, v1_available, v1_native_available, v2_available, soc_manufacturer,
   soc_detection:{state,model}, fingerprint, ...
   provision exit 0 = installed; 2/21/22/23/24 = failure. Its stdout holds the keybox incl. the
   private key: it is parsed for status only, never rendered or logged. */
(function () {
  'use strict';

  var STATUS_MS = 30000;
  var PROVISION_MS = 150000; // duckd's TA timeout is 30s per attempt, up to 3 attempts
  var METHODS = [
    { id: 'auto', key: 'rkpd_auto', fb: 'Auto', flag: null },
    { id: 'v2', fb: 'V2 (CSR_V2)', flag: 'v2_available' },
    { id: 'v1', fb: 'V1 AIDL', flag: 'v1_available' },
    { id: 'v1-native', fb: 'V1 Native', flag: 'v1_native_available' }
  ];
  var LABEL = { v2: 'V2', v1: 'V1 AIDL', 'v1-native': 'V1 Native' };
  var ICON = { loading: 'schedule', busy: 'schedule', ready: 'verified_user', blocked: 'block', err: 'cancel', ok: 'check_circle' };

  var seq = 0, busy = false, status = null, method = 'auto', cooldown = null, lastResult = null;

  function $(id) { return document.getElementById(id); }
  function toast(m, err) { if (typeof window.jerryToast === 'function') window.jerryToast(m, err); }
  function tr(key, fb, vars) {
    var s = null;
    try { if (typeof window.__jerryGetTranslation === 'function') s = window.__jerryGetTranslation(key); } catch (e) {}
    s = s || fb || key;
    if (vars) Object.keys(vars).forEach(function (k) { s = s.split('{' + k + '}').join(vars[k]); });
    return s;
  }
  function mk(tag, cls, txt) {
    var x = document.createElement(tag);
    if (cls) x.className = cls;
    if (txt != null) x.textContent = txt;
    return x;
  }
  function show(id, on) { var e = $(id); if (e) e.style.display = on ? '' : 'none'; }

  async function run(cmd, ms) {
    if (typeof window.jerryRun !== 'function') return { code: -1, stdout: '', stderr: 'no bridge' };
    var timer;
    var to = new Promise(function (res) { timer = setTimeout(function () { res({ code: -1, stdout: '', stderr: 'Timed out' }); }, ms); });
    try { return await Promise.race([window.jerryRun(cmd), to]); }
    finally { clearTimeout(timer); }
  }

  // Last parseable JSON object in stdout.
  function parseJson(out) {
    var t = String(out || '').trim();
    if (!t) return null;
    try { var w = JSON.parse(t); if (w && typeof w === 'object') return w; } catch (e) {}
    var lines = t.split('\n');
    for (var i = lines.length - 1; i >= 0; i--) {
      var l = lines[i].trim();
      if (l.charAt(0) !== '{') continue;
      try { return JSON.parse(l); } catch (e) {}
    }
    return null;
  }

  function clip(s, n) { s = String(s || '').trim(); return s.length > n ? s.slice(0, n) + '…' : s; }

  // status output carries no secrets, so a clipped copy is safe to show for diagnosis.
  function parseStatus(r) {
    var j = parseJson(r.stdout);
    var diag = 'exit ' + r.code + (r.stderr ? ' · ' + clip(r.stderr, 200) : '') + '\n' + clip(r.stdout, 400);
    if (!j) return { error: 'no_response', diag: diag };
    if (j.ok === false) {
      var e = j.error || {};
      return { error: e.code || 'error', message: e.message || '', diag: diag };
    }
    var d = (j.data && typeof j.data === 'object') ? j.data : (j.result && typeof j.result === 'object') ? j.result : j;
    if (typeof d.prerequisites_met !== 'boolean') return { error: 'unexpected_format', diag: diag };
    return { d: d, blockers: Array.isArray(d.blockers) ? d.blockers.filter(function (b) { return typeof b === 'string'; }) : [] };
  }

  function ready() { return !!(status && status.d && status.d.prerequisites_met && status.blockers.length === 0); }
  function available(id) {
    var m = METHODS.filter(function (x) { return x.id === id; })[0];
    if (!m || !status || !status.d) return false;
    return m.flag === null || status.d[m.flag] === true;
  }
  function yn(v) { return v ? tr('rkpd_yes', 'Yes') : tr('rkpd_no', 'No'); }

  function paint(state, title, sub) {
    $('rkpd-summary').setAttribute('data-state', state);
    $('rkpd-icon').textContent = ICON[state] || 'schedule';
    $('rkpd-status').textContent = title;
    $('rkpd-status-sub').textContent = sub || '';
    show('rkpd-status-sub', !!sub);
  }

  function setBtn(state) {
    var b = $('rkpd-issue');
    b.setAttribute('data-state', state);
    b.setAttribute('aria-busy', state === 'busy' ? 'true' : 'false');
    b.disabled = state === 'busy' || !ready() || !!cooldown;
    b.querySelector('.rkp-btn-label').textContent =
      state === 'busy' ? tr('rkpd_issuing', 'Issuing…') : state === 'err' ? tr('rkpd_retry', 'Try again') : tr('rkpd_issue', 'Issue from this device');
    b.querySelector('.rkp-btn-icon').textContent = state === 'err' ? 'refresh' : 'key';
  }

  function renderBlockers(list) {
    var box = $('rkpd-blockers');
    box.textContent = '';
    list.forEach(function (b) {
      var row = mk('div', 'list-item rkpd-row');
      var c = mk('div', 'list-item-content');
      row.appendChild(mk('md-icon', null, 'block'));
      c.appendChild(mk('div', 'toggle-text', tr('rkpd_b_' + b, b)));
      row.appendChild(c);
      box.appendChild(row);
    });
    show('rkpd-blockers', list.length > 0);
  }

  function addDetail(box, label, value, mono) {
    var row = mk('div', 'list-item rkpd-row');
    var c = mk('div', 'list-item-content');
    c.appendChild(mk('span', 'supporting-text', label));
    c.appendChild(mk('span', 'rkpd-val' + (mono ? ' rkpd-mono' : ''), value));
    row.appendChild(c);
    box.appendChild(row);
  }

  function renderDetails() {
    var box = $('rkpd-details');
    box.textContent = '';
    if (!status || !status.d) { show('rkpd-details', false); show('rkpd-details-title', false); return; }
    var d = status.d, det = d.soc_detection || {};
    var vendor = { qualcomm: tr('rkpd_detected', 'Detected') + ' · Qualcomm', media_tek: tr('rkpd_detected', 'Detected') + ' · MediaTek',
                   other: tr('rkpd_other_vendor', 'Other vendor'), conflicting: tr('rkpd_conflicting', 'Conflicting information') }[det.state] || tr('rkpd_unknown', 'Unknown');
    addDetail(box, tr('rkpd_platform', 'Platform (arm64)'), yn(d.android_arm64));
    addDetail(box, tr('rkpd_root', 'Root access'), yn(d.root));
    addDetail(box, tr('rkpd_soc_vendor', 'SoC vendor'), (d.soc_manufacturer ? d.soc_manufacturer + ' · ' : '') + vendor);
    addDetail(box, tr('rkpd_soc_model', 'SoC model'), det.model || tr('rkpd_unknown', 'Unknown'));
    addDetail(box, tr('rkpd_library', 'Keymaster library'), (d.library_present ? yn(true) : yn(false)) + (d.library_path ? ' · ' + d.library_path : ''), true);
    addDetail(box, tr('rkpd_device_node', 'Device node'), (d.device_present ? yn(true) : yn(false)) + (d.device_path ? ' · ' + d.device_path : ''), true);
    show('rkpd-details', true); show('rkpd-details-title', true);
  }

  function renderMethods() {
    var box = $('rkpd-methods');
    box.textContent = '';
    box.classList.toggle('is-busy', busy);
    var on = !!(status && status.d && ready());
    show('rkpd-methods', on); show('rkpd-methods-title', on);
    if (!on) return;
    if (!available(method)) method = 'auto';
    METHODS.forEach(function (m) {
      var ok = available(m.id);
      var row = mk('div', 'list-item rkp-item');
      row.setAttribute('role', 'radio');
      row.setAttribute('aria-checked', m.id === method ? 'true' : 'false');
      if (!ok) row.setAttribute('aria-disabled', 'true');
      row.tabIndex = ok ? 0 : -1;
      var c = mk('div', 'list-item-content');
      c.appendChild(mk('div', 'toggle-text', m.key ? tr(m.key, m.fb) : m.fb));
      c.appendChild(mk('span', 'supporting-text rkp-meta', m.id === 'auto' ? tr('rkpd_auto_desc', 'Tries every available method') : ok ? '' : tr('rkpd_unavailable', 'Not available on this device')));
      var radio = mk('span', 'rkp-radio'); radio.setAttribute('aria-hidden', 'true');
      row.appendChild(mk('md-icon', null, 'key')); row.appendChild(c); row.appendChild(radio);
      row.appendChild(document.createElement('md-ripple'));
      var pick = function () { if (busy || !ok) return; method = m.id; renderMethods(); };
      row.addEventListener('click', pick);
      row.addEventListener('keydown', function (ev) { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); pick(); } });
      box.appendChild(row);
    });
  }

  function render() {
    show('rkpd-diag', false);
    if (!status) return;
    if (status.error) {
      var title = status.error === 'arch_unsupported' ? tr('rkpd_err_arch', 'This needs an arm64 device')
        : status.error === 'binary_missing' ? tr('rkpd_err_binary', 'Helper binary missing. Reinstall the module')
        : tr('rkpd_check_failed', 'Could not check this device');
      paint('err', title, status.message || (status.error !== 'arch_unsupported' && status.error !== 'binary_missing' ? status.error : ''));
      if (status.error !== 'arch_unsupported' && status.error !== 'binary_missing') {
        $('rkpd-diag-text').textContent = status.diag;
        show('rkpd-diag', true);
      }
      renderBlockers([]); renderDetails(); renderMethods(); show('rkpd-notice', false); setBtn('idle');
      return;
    }
    if (ready()) {
      var via = METHODS.filter(function (m) { return m.flag && status.d[m.flag] === true; }).map(function (m) { return LABEL[m.id]; }).join(', ');
      paint('ready', tr('rkpd_prereq_met', 'Prerequisites met'), via);
    } else {
      paint('blocked', tr('rkpd_prereq_missing', 'Prerequisites missing'), tr('rkpd_not_ready', 'Not available on this device'));
    }
    renderBlockers(status.d.prerequisites_met ? [] : status.blockers);
    renderDetails(); renderMethods(); show('rkpd-notice', true); setBtn('idle');
  }

  async function refresh() {
    if (busy) return;
    var mine = ++seq;
    status = null; lastResult = null;
    paint('loading', tr('rkpd_checking', 'Checking this device…'), '');
    show('rkpd-diag', false); renderBlockers([]); renderDetails(); renderMethods(); show('rkpd-notice', false); setBtn('idle');
    var r = await run('sh @ROOT@/features/rkp_device.sh status', STATUS_MS);
    if (mine !== seq) return;
    status = parseStatus(r);
    render();
  }

  function failText(r) {
    if (r.code === -1 && r.stderr === 'Timed out') return tr('rkpd_timeout', 'No answer yet. It may still be running, so wait a minute and check the keybox on Home before retrying');
    var j = parseJson(r.stdout);
    var code = j && j.ok === false && j.error && j.error.code;
    if (code) return tr('rkpd_e_' + code, j.error.message || code);
    if (r.code === 2) return tr('rkpd_err_arch', 'This needs an arm64 device');
    if (r.code >= 21 && r.code <= 24) return tr('rkpd_err_' + r.code, 'Failed (exit ' + r.code + ')');
    return tr('rkpd_err_generic', 'Failed (exit {c})', { c: r.code });
  }

  async function provision() {
    if (busy) return;
    var m = /^(auto|v1|v2|v1-native)$/.test(method) ? method : 'auto';
    busy = true;
    $('rkpd-refresh').disabled = true;
    paint('busy', tr('rkpd_issuing', 'Issuing…'), tr('rkpd_issuing_hint', 'This can take up to a minute'));
    renderMethods(); setBtn('busy');
    var r = await run('sh @ROOT@/features/rkp_device.sh provision ' + m, PROVISION_MS);
    busy = false;
    $('rkpd-refresh').disabled = false;
    var ok = r.code === 0, msg;
    if (ok) {
      var used = null;
      try {
        var j = parseJson(r.stdout), d = j && (j.data || j.result || j), at = d && d.attempts;
        used = at && at.length ? LABEL[at[at.length - 1].method] : null;
      } catch (e) {}
      msg = used ? tr('rkpd_issued_via', 'Device RKP keybox installed ({m})', { m: used }) : tr('rkpd_issued', 'Device RKP keybox installed');
    } else {
      msg = failText(r);
      if (r.code === -1) cooldown = setTimeout(function () { cooldown = null; setBtn('idle'); }, 60000);
    }
    toast(msg, !ok);
    render();
    paint(ok ? 'ok' : 'err', msg, ok ? '' : '');
    renderMethods();
    setBtn(ok ? 'idle' : 'err');
  }

  function openConfirm() {
    var b = $('rkpd-issue');
    if (busy || !b || b.disabled) return;
    var dlg = $('rkpd-confirm');
    if (dlg && typeof dlg.show === 'function') dlg.show(); else provision();
  }

  function paintBehind(panel, open) {
    [document.documentElement, document.body].forEach(function (el) {
      if (!el) return;
      if (open) el.style.setProperty('background', getComputedStyle(panel).background, 'important');
      else el.style.removeProperty('background');
    });
  }
  function setPanel(open) {
    var panel = $('rkpd-panel');
    if (!panel) return;
    panel.style.display = open ? 'flex' : 'none';
    paintBehind(panel, open);
    var main = document.querySelector('main');
    if (main) main.style.overflow = open ? 'hidden' : '';
  }

  window.openRkpdPanel = function () { setPanel(true); if (!busy) refresh(); };
  window.closeRkpdPanel = function () { setPanel(false); };

  document.addEventListener('DOMContentLoaded', function () {
    if (!$('rkpd-panel')) return;
    $('rkpd-issue').addEventListener('click', openConfirm);
    $('rkpd-refresh').addEventListener('click', refresh);
    $('rkpd-confirm-cancel').addEventListener('click', function () { $('rkpd-confirm').close(); });
    $('rkpd-confirm-go').addEventListener('click', function () { $('rkpd-confirm').close(); provision(); });
    document.addEventListener('languageChanged', function () { if (!busy && status) render(); });
  });
})();
