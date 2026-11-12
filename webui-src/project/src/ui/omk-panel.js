/* OhMyKeymint config page: edits config.toml / injector.toml, restarts OMK services.
   Backend: features/omk_config.sh. The TOML is parsed generically, so every key that exists
   in the user's config.toml is shown; only the changed lines are rewritten. */
(function () {
  'use strict';

  var ROOT = '/data/adb/modules/JerryManager';

  /* i18n: falls back to the English text when no translation is loaded (also in Node tests) */
  function tr(key, fallback, vars) {
    var s = fallback;
    try {
      if (typeof window !== 'undefined' && typeof window.__jerryGetTranslation === 'function') {
        s = window.__jerryGetTranslation(key) || fallback;
      }
    } catch (e) {}
    if (vars) Object.keys(vars).forEach(function (k) { s = s.split('{' + k + '}').join(vars[k]); });
    return s;
  }

  var BOOL_KEYS = {
    'Disabled (recommended)': 'omk_bool_disabled', 'Enabled': 'omk_bool_enabled',
    'Verified': 'omk_bool_verified', 'Unverified': 'omk_bool_unverified',
    'Locked': 'omk_bool_locked', 'Unlocked': 'omk_bool_unlocked'
  };
  function boolText(s) { return BOOL_KEYS[s] ? tr(BOOL_KEYS[s], s) : s; }

  /* Field metadata taken from OhMyKeymint's docs/CONFIGURATION.md (config.toml version 3).
     Every key that exists in the user's file is still shown, even when it is not listed here. */
  var HOT_PATCH = { security_patch: 1, os_patchlevel: 1, vendor_patchlevel: 1, boot_patchlevel: 1 };

  var META = {
    version: { label: 'Configuration version', readonly: true, hint: 'Managed by OMK. Do not change.' },
    backend: { label: 'Backend', readonly: true, hint: 'Only "injector" is supported.' },
    log_level: { label: 'Log level', basic: true, options: ['off', 'error', 'warn', 'info', 'debug', 'trace'], hint: 'Requires KeyMint restart.' },
    force_skip_system_biometric_hat_verification: {
      label: 'Biometric compatibility override', hot: true, boolLabels: { 'false': 'Disabled (recommended)', 'true': 'Enabled' },
      hint: 'Only enable for a confirmed System KeyMint compatibility issue.'
    },
    ta_operation_delay_ms: { label: 'TA operation delay (ms)', hot: true, range: true, hint: '[min, max], 0 to 250. [0, 0] disables. Applies live.' },
    ta_generation_delay_ms: { label: 'TA generation delay (ms)', hot: true, range: true, hint: '[min, max], 0 to 250. [0, 0] disables. Applies live.' },
    ta_control_delay_ms: { label: 'TA control delay (ms)', hot: true, range: true, hint: '[min, max], 0 to 250. [0, 0] disables. Applies live.' },
    retire_stale_keybox_bound_keys: { label: 'Retire stale keybox-bound keys', hot: true, hint: 'Applies at the next keybox reload.' },
    os_version: { label: 'Android major version', basic: true, hint: 'Use auto or an integer from 0 to 99. Requires restart.' },
    security_patch: { label: 'Security patch', basic: true, hint: 'auto, latest, or an exact date (YYYY-MM-DD). Applies live.' },
    os_patchlevel: { label: 'OS patch level', hint: 'auto follows the effective security patch.' },
    vendor_patchlevel: { label: 'Vendor patch level', hint: 'auto uses vendor patch sources, then the OS patch level.' },
    boot_patchlevel: { label: 'Boot patch level', hint: 'Accepts auto, latest, a date, or a decimal u32 wire value.' },
    vb_key: { label: 'Verified boot key digest', basic: true, hint: 'auto, random, or 64 hex characters. Keep auto unless a fixed attestation profile is required. Requires restart.' },
    vb_hash: { label: 'Verified boot hash', basic: true, hint: 'auto, random, or 64 hex characters. Requires restart; random to auto needs a device reboot.' },
    verified_boot_state: { label: 'Verified boot state', boolLabels: { 'true': 'Verified', 'false': 'Unverified' }, hint: 'Requires KeyMint restart.' },
    device_locked: { label: 'Device locked', boolLabels: { 'true': 'Locked', 'false': 'Unlocked' }, hint: 'Reports the state only; it does not lock the bootloader. Requires restart.' },
    overrideTelephonyProperties: { label: 'Override telephony properties', hint: 'false fills only empty IMEI/MEID fields from the device.' },
    brand: { label: 'Brand' }, device: { label: 'Device' }, product: { label: 'Product' }, manufacturer: { label: 'Manufacturer' },
    model: { label: 'Model' }, serial: { label: 'Serial', hint: 'Private. Redact before sharing.' },
    meid: { label: 'MEID' }, imei: { label: 'IMEI', hint: 'Private. Leave empty to let OMK fill it.' }, imei2: { label: 'IMEI 2' }
  };

  var SECTION_TITLES = { main: 'KeyMint service', trust: 'Trust and patch levels', crypto: 'Crypto secrets', device: 'Device identity' };
  var SECTION_NOTES = {
    crypto: 'Private seeds that protect every key OMK created. They are read-only here and never leave this screen. Do not share them.',
    device: 'Identity strings reported to apps. Private, redact before sharing screenshots. Requires KeyMint restart.'
  };
  var ADV_SECTIONS = { crypto: 1, device: 1 };

  var state = {
    tab: 'config',
    advanced: false,
    busy: false,
    loaded: false,
    cfgText: '',
    lines: [],
    fields: [],
    injText: '',
    injOrig: '',
    backups: {},
    confirmRestore: false,
    confirmClose: false
  };

  function $(id) { return document.getElementById(id); }

  /* ---------- pure helpers (also used by tests) ---------- */

  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function prettify(key) {
    var s = String(key).replace(/([a-z0-9])([A-Z])/g, '$1 $2').replace(/[_\-.]+/g, ' ').trim();
    return s.charAt(0).toUpperCase() + s.slice(1);
  }

  function tomlUnescape(s) {
    return s.replace(/\\(["\\nt])/g, function (m, c) { return c === 'n' ? '\n' : c === 't' ? '\t' : c; });
  }

  function tomlEscape(s) {
    return s.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  }

  /* [main] and the root-level keys (version) share one card */
  function groupOf(sec) {
    if (sec === '' || sec === 'main') return 'main';
    if (/^app_patch_levels/.test(sec)) return sec;
    return sec;
  }

  function sectionTitle(g) {
    if (SECTION_TITLES.hasOwnProperty(g)) return tr('omk_sec_' + g, SECTION_TITLES[g]);
    var m = /^app_patch_levels\.?"?([^"]*)"?$/.exec(g);
    if (m) return tr('omk_sec_app_patch', 'App patch levels') + (m[1] ? ': ' + m[1] : '');
    return prettify(g);
  }

  function isAdvancedField(f) {
    var g = groupOf(f.sec);
    if (ADV_SECTIONS[g] || /^app_patch_levels/.test(g)) return true;
    var m = META[f.key];
    return !(m && m.basic);
  }

  function isReadOnly(f) {
    var m = META[f.key];
    return f.kind === 'raw' || groupOf(f.sec) === 'crypto' || !!(m && m.readonly && groupOf(f.sec) === 'main');
  }

  /* config.toml text -> { lines, fields } ; one field per single-line `key = value` */
  function parseToml(text) {
    var lines = String(text).replace(/\r/g, '').split('\n');
    var sec = '';
    var fields = [];
    for (var i = 0; i < lines.length; i++) {
      var ln = lines[i];
      if (/^\s*#/.test(ln) || !/\S/.test(ln)) continue;
      var sm = /^\s*\[\[?\s*([^\]]+?)\s*\]\]?\s*(#.*)?$/.exec(ln);
      if (sm) { sec = sm[1]; continue; }
      var kv = /^(\s*)([A-Za-z0-9_.\-]+)\s*=\s*(.*?)\s*$/.exec(ln);
      if (!kv) continue;
      var raw = kv[3];
      var f = { sec: sec, key: kv[2], line: i, indent: kv[1], raw: raw, kind: 'raw', value: raw, comment: '' };
      var m;
      if ((m = /^"((?:[^"\\]|\\.)*)"\s*(#.*)?$/.exec(raw))) {
        f.kind = 'str'; f.value = tomlUnescape(m[1]); f.comment = m[2] || '';
      } else if ((m = /^(-?\d+(?:\.\d+)?)\s*(#.*)?$/.exec(raw))) {
        f.kind = 'num'; f.value = m[1]; f.comment = m[2] || '';
      } else if ((m = /^(true|false)\s*(#.*)?$/.exec(raw))) {
        f.kind = 'bool'; f.value = m[1]; f.comment = m[2] || '';
      } else if ((m = /^\[\s*(-?\d+(?:\s*,\s*-?\d+)*)\s*,?\s*\]\s*(#.*)?$/.exec(raw))) {
        f.kind = 'ints'; f.value = m[1].split(/\s*,\s*/).join(', '); f.comment = m[2] || '';
      }
      fields.push(f);
    }
    return { lines: lines, fields: fields };
  }

  function isDate(v) { return /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/.test(v); }
  function isU32(v) { return /^\d{1,10}$/.test(v) && Number(v) <= 4294967295; }

  /* Returns an error string, or '' when the value is acceptable for that key */
  function validateValue(key, v, sec) {
    if (/[\u0000-\u001f]/.test(v)) return tr('omk_err_control', 'Control characters are not allowed');
    var low = v.toLowerCase();
    var app = /^app_patch_levels/.test(sec || '');
    switch (key) {
      case 'os_version':
        return /^(auto|\d{1,2})$/.test(low) ? '' : tr('omk_err_os_version', 'Use auto or a number from 0 to 99');
      case 'security_patch':
      case 'os_patchlevel':
      case 'vendor_patchlevel':
        if (low === 'auto' || (!app && low === 'latest') || isDate(v)) return '';
        return app ? tr('omk_err_patch_app', 'Use auto or YYYY-MM-DD') : tr('omk_err_patch', 'Use auto, latest or YYYY-MM-DD');
      case 'boot_patchlevel':
        if (low === 'auto' || (!app && low === 'latest') || isDate(v) || isU32(v)) return '';
        return tr('omk_err_boot_patch', 'Use auto, latest, YYYY-MM-DD or a decimal u32 value');
      case 'vb_key':
      case 'vb_hash':
        return /^(auto|random|[0-9a-f]{64})$/.test(low) ? '' : tr('omk_err_hex', 'Use auto, random or exactly 64 hex characters');
      default:
        return '';
    }
  }

  function parseRange(v) {
    var m = /^\s*\[?\s*(\d+)\s*,\s*(\d+)\s*\]?\s*$/.exec(v);
    if (!m) throw new Error(tr('omk_err_range', 'Use two numbers: min, max (for example 9, 21)'));
    var lo = Number(m[1]), hi = Number(m[2]);
    if (hi > 250) throw new Error(tr('omk_err_range_max', 'Maximum is 250 ms'));
    if (lo > hi) throw new Error(tr('omk_err_range_order', 'Minimum cannot be greater than maximum'));
    return '[' + lo + ', ' + hi + ']';
  }

  /* The full replacement line for a changed field (throws on invalid input) */
  function serializeValue(f, input) {
    var v = String(input).trim();
    var out;
    if (f.kind === 'ints') {
      out = parseRange(v);
    } else {
      var err = validateValue(f.key, v, f.sec);
      if (err) throw new Error(err);
      if (/^(auto|latest|random)$/i.test(v) || /^(vb_key|vb_hash)$/.test(f.key)) v = v.toLowerCase();
      if (f.kind === 'bool') {
        if (v !== 'true' && v !== 'false') throw new Error(tr('omk_err_bool', 'Use true or false'));
        out = v;
      } else if (f.kind === 'num') {
        out = /^-?\d+(\.\d+)?$/.test(v) ? v : '"' + tomlEscape(v) + '"';
      } else if (f.key === 'os_version' && /^\d+$/.test(v)) {
        out = String(Number(v));
      } else {
        out = '"' + tomlEscape(v) + '"';
      }
    }
    return f.indent + f.key + ' = ' + out + (f.comment ? ' ' + f.comment : '');
  }

  /* edits: [{ field, input }] -> new full text */
  function applyEdits(lines, edits) {
    var out = lines.slice();
    edits.forEach(function (e) { out[e.field.line] = serializeValue(e.field, e.input); });
    return out.join('\n');
  }

  /* OMK hot-applies some fields; the rest need a KeyMint restart (docs: "config.toml apply summary").
     The four patch levels only hot-apply when no other [trust] field changes in the same save. */
  function needsRestart(edits) {
    var trustOther = edits.some(function (e) {
      return groupOf(e.field.sec) === 'trust' && !HOT_PATCH[e.field.key];
    });
    return edits.some(function (e) {
      var f = e.field, g = groupOf(f.sec), m = META[f.key] || {};
      if (g === 'trust') return HOT_PATCH[f.key] ? trustOther : true;
      if (g === 'main') return !m.hot;
      return true;
    });
  }

  /* Extra advice after a save, depending on what changed */
  function followUpNotes(edits) {
    var notes = [];
    edits.forEach(function (e) {
      var f = e.field, nv = String(e.input).trim().toLowerCase();
      if (f.key === 'vb_hash' && f.value === 'random' && nv === 'auto') notes.push(tr('omk_note_vb_hash', 'Reboot the device to return vb_hash from random to auto.'));
      if (f.key === 'vb_key' && f.value === 'random' && nv === 'auto') notes.push(tr('omk_note_vb_key', 'If vb_key does not return to auto after the restart, reboot the device.'));
    });
    return notes.join(' ');
  }

  function toBase64(text) {
    if (typeof btoa === 'function') return btoa(unescape(encodeURIComponent(text)));
    return Buffer.from(text, 'utf8').toString('base64');
  }

  function parseStatus(out) {
    var r = {};
    String(out || '').split('\n').forEach(function (l) {
      var i = l.indexOf('=');
      if (i > 0) r[l.slice(0, i).trim()] = l.slice(i + 1).trim() === '1';
    });
    return r;
  }

  /* injector.toml sanity check; returns '' when OK */
  function checkInjector(text) {
    if (!/\S/.test(text)) return tr('omk_inj_err_empty', 'injector.toml cannot be empty');
    if (!/^\s*scoop\s*=\s*\[/m.test(text)) return tr('omk_inj_err_scoop', 'Keep the "scoop = [" line');
    if (!/^\s*\]\s*$/m.test(text) && !/^\s*scoop\s*=\s*\[.*\]\s*$/m.test(text)) return tr('omk_inj_err_close', 'Keep the closing "]" line of scoop');
    return '';
  }

  /* ---------- bridge ---------- */

  async function run(cmd) {
    var full = cmd.split('@ROOT@').join(ROOT);
    try {
      var bridge = window.JerryBridge;
      if (bridge && typeof bridge.exec === 'function') {
        await bridge.initBridge();
        if (typeof bridge.getModuleDir === 'function' && bridge.getModuleDir()) {
          ROOT = bridge.getModuleDir();
          full = cmd.split('@ROOT@').join(ROOT);
        }
        var r = await bridge.exec(full);
        return { code: typeof r.code === 'number' ? r.code : 0, stdout: r.stdout || '', stderr: r.stderr || '' };
      }
      if (typeof window.shAsync === 'function') {
        var s = await window.shAsync(full);
        return { code: s.code, stdout: s.stdout || '', stderr: s.stderr || '' };
      }
    } catch (e) {
      return { code: -1, stdout: '', stderr: String((e && e.message) || e) };
    }
    return { code: -1, stdout: '', stderr: 'no bridge' };
  }

  function sq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
  function omk(args) { return 'sh @ROOT@/features/omk_config.sh ' + args; }

  function errText(r) {
    var t = (r.stderr || r.stdout || '').trim();
    var lines = t.split('\n').filter(Boolean);
    var last = lines.length ? lines[lines.length - 1] : '';
    return last.replace(/^\S+ \S+ \[ERROR\] /, '') || ('code ' + r.code);
  }

  /* ---------- UI ---------- */

  function setStatus(msg, kind) {
    var el = $('omk-status');
    if (!el) return;
    if (!msg) { el.style.display = 'none'; el.textContent = ''; return; }
    el.className = 'omk-status' + (kind ? ' omk-status--' + kind : '');
    el.textContent = msg;
    el.style.display = '';
  }

  function setBusy(b) {
    state.busy = b;
    var root = $('omk-panel-root');
    if (!root) return;
    root.querySelectorAll('.pif-btn, .at-apply-fab, .omk-tab').forEach(function (el) { el.disabled = b; });
  }

  function dirtyConfig() {
    var out = [];
    state.fields.forEach(function (f) {
      var el = $('omk-f-' + f.line);
      if (!el || el.disabled) return;
      if (el.value !== f.value) out.push({ field: f, input: el.value, el: el });
    });
    return out;
  }

  function injDirty() {
    var ta = $('omk-inj-text');
    return !!ta && ta.value !== state.injOrig;
  }

  function isDirty() { return state.tab === 'config' ? dirtyConfig().length > 0 : injDirty(); }

  function clearFieldError(line) {
    var errEl = $('omk-e-' + line), wrap = $('omk-w-' + line);
    if (errEl) errEl.style.display = 'none';
    if (wrap) wrap.classList.remove('omk-field--err');
  }

  function updateSaveBar() {
    var bar = $('omk-savebar');
    if (!bar) return;
    var n = state.tab === 'config' ? dirtyConfig().length : (injDirty() ? 1 : 0);
    bar.style.display = n ? '' : 'none';
    var label = $('omk-save-label');
    if (label) {
      if (state.tab === 'config') {
        var ed = dirtyConfig().map(function (e) { return { field: e.field, input: e.input }; });
        label.textContent = tr(n === 1 ? 'omk_save_one' : 'omk_save_many', n === 1 ? 'Save {n} change' : 'Save {n} changes', { n: n }) +
          (ed.length && needsRestart(ed) ? tr('omk_save_restart_suffix', ' & restart KeyMint') : '');
      } else {
        label.textContent = tr('omk_save_injector', 'Save injector.toml');
      }
    }
    state.fields.forEach(function (f) {
      var wrap = $('omk-w-' + f.line), el = $('omk-f-' + f.line);
      if (wrap && el) {
        var dirty = !el.disabled && el.value !== f.value;   /* read-only/masked fields are never "changed" */
        wrap.classList.toggle('omk-field--dirty', dirty);
        if (!dirty) clearFieldError(f.line);   /* back to the original value: nothing left to complain about */
      }
    });
    state.confirmClose = false;
  }

  function selectHtml(id, options, current) {
    var list = options.slice();
    if (!list.some(function (o) { return o[0] === current; })) list.unshift([current, current]);
    return '<select id="' + id + '" class="omk-input">' + list.map(function (o) {
      return '<option value="' + esc(o[0]) + '"' + (o[0] === current ? ' selected' : '') + '>' + esc(o[1]) + '</option>';
    }).join('') + '</select>';
  }

  function fieldHtml(f) {
    var m = META[f.key] || {};
    var id = 'omk-f-' + f.line;
    var g = groupOf(f.sec);
    var label = m.label ? tr('omk_label_' + f.key, m.label) : prettify(f.key);
    var input, hint = m.hint ? tr('omk_hint_' + f.key, m.hint) : '';
    if (g === 'crypto') {
      input = '<input id="' + id + '" class="omk-input" type="text" disabled value="\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022">';
      hint = tr('omk_hint_keep', 'Keep unchanged.');
    } else if (f.kind === 'raw') {
      input = '<input id="' + id + '" class="omk-input" type="text" disabled value="' + esc(f.raw) + '">';
      hint = tr('omk_hint_complex', 'Complex value, edit it in the file directly.');
    } else if (isReadOnly(f)) {
      input = '<input id="' + id + '" class="omk-input" type="text" disabled value="' + esc(f.value) + '">';
    } else if (f.kind === 'bool') {
      var bl = m.boolLabels || { 'true': 'true', 'false': 'false' };
      input = selectHtml(id, [['true', boolText(bl['true'])], ['false', boolText(bl['false'])]], f.value);
    } else if (m.options) {
      input = selectHtml(id, m.options.map(function (o) { return [o, o]; }), f.value);
    } else {
      input = '<input id="' + id + '" class="omk-input" type="text" autocomplete="off" autocapitalize="off" spellcheck="false" value="' + esc(f.value) + '"' +
        (f.kind === 'ints' ? ' placeholder="' + esc(tr('omk_range_placeholder', 'min, max')) + '"' : '') + '>';
    }
    return '<div class="omk-field' + (isAdvancedField(f) ? ' omk-adv' : '') + '" id="omk-w-' + f.line + '">' +
      '<div class="omk-label"><span>' + esc(label) + '</span><span class="omk-key">' + esc(f.key) + '</span><span class="omk-dirty-dot"></span></div>' +
      input +
      (hint ? '<div class="omk-hint">' + esc(hint) + '</div>' : '') +
      '<div class="omk-err" id="omk-e-' + f.line + '" style="display:none"></div>' +
      '</div>';
  }

  function renderConfig() {
    var host = $('omk-fields');
    if (!host) return;
    if (!state.fields.length) {
      host.innerHTML = '<div class="omk-empty">' + esc(tr('omk_empty', 'No editable settings found in config.toml.')) + '</div>';
      return;
    }
    var order = [], groups = {};
    state.fields.forEach(function (f) {
      var g = groupOf(f.sec);
      if (!groups.hasOwnProperty(g)) { groups[g] = []; order.push(g); }
      groups[g].push(f);
    });
    var html = '';
    order.forEach(function (g) {
      html += '<div class="omk-card omk-section" data-sec="' + esc(g) + '"><div class="omk-card-title">' + esc(sectionTitle(g)) + '</div>' +
        (SECTION_NOTES[g] ? '<div class="omk-hint omk-note">' + esc(tr('omk_note_' + g, SECTION_NOTES[g])) + '</div>' : '') +
        groups[g].map(fieldHtml).join('') + '</div>';
    });
    host.innerHTML = html;
    host.querySelectorAll('.omk-input').forEach(function (el) {
      var onEdit = function () {
        var wrap = el.closest ? el.closest('.omk-field') : null;
        if (wrap && /^omk-w-/.test(wrap.id)) clearFieldError(wrap.id.slice(6));  /* re-validated on the next save */
        updateSaveBar();
      };
      el.addEventListener('input', onEdit);
      el.addEventListener('change', onEdit);
    });
    applyAdvanced();
    updateSaveBar();
  }

  function applyAdvanced() {
    document.querySelectorAll('#omk-fields .omk-adv').forEach(function (el) {
      el.style.display = state.advanced ? '' : 'none';
    });
    document.querySelectorAll('#omk-fields .omk-section').forEach(function (card) {
      var any = Array.prototype.some.call(card.querySelectorAll('.omk-field'), function (w) { return w.style.display !== 'none'; });
      card.style.display = any ? '' : 'none';
    });
    var btn = $('omk-adv-btn');
    if (btn) {
      btn.querySelector('.pif-btn-label').textContent = state.advanced ? tr('omk_adv_hide', 'Hide advanced settings') : tr('omk_adv_show', 'Show advanced settings');
      btn.setAttribute('aria-expanded', state.advanced ? 'true' : 'false');
    }
  }

  function showTab(tab) {
    state.tab = tab;
    document.querySelectorAll('.omk-tab').forEach(function (b) {
      b.classList.toggle('omk-tab--active', b.getAttribute('data-omk-tab') === tab);
    });
    $('omk-tab-config').style.display = tab === 'config' ? '' : 'none';
    $('omk-tab-injector').style.display = tab === 'injector' ? '' : 'none';
    $('omk-adv-btn').style.display = tab === 'config' ? '' : 'none';
    updateSaveBar();
  }

  /* ---------- actions ---------- */

  async function load() {
    setBusy(true);
    setStatus('');
    var host = $('omk-fields');
    if (host) host.innerHTML = '<div class="omk-loading"><md-circular-progress indeterminate></md-circular-progress><span>' + esc(tr('omk_loading', 'Reading OhMyKeymint config…')) + '</span></div>';

    var rc = await run(omk('--read config'));
    if (rc.code !== 0) {
      if (host) host.innerHTML = '<div class="omk-empty">' + esc(tr('omk_read_failed', 'Could not read config.toml')) + '</div>';
      setStatus(errText(rc), 'err');
      setBusy(false);
      return;
    }
    state.cfgText = rc.stdout;
    var parsed = parseToml(rc.stdout);
    state.lines = parsed.lines;
    state.fields = parsed.fields;
    renderConfig();

    var ri = await run(omk('--read injector'));
    state.injOrig = ri.code === 0 ? ri.stdout : '';
    var ta = $('omk-inj-text');
    if (ta) {
      ta.value = state.injOrig;
      ta.disabled = ri.code !== 0;
      ta.placeholder = ri.code !== 0 ? tr('omk_inj_missing', 'injector.toml not found yet') : '';
      ta.oninput = updateSaveBar;
    }

    var rs = await run(omk('--status'));
    state.backups = rs.code === 0 ? parseStatus(rs.stdout) : {};
    state.loaded = true;
    setBusy(false);
    updateSaveBar();
  }

  async function save() {
    if (state.busy) return;
    if (state.tab === 'config') {
      var edits = dirtyConfig();
      if (!edits.length) return;
      var bad = false;
      edits.forEach(function (e) {
        var errEl = $('omk-e-' + e.field.line), wrap = $('omk-w-' + e.field.line);
        try {
          serializeValue(e.field, e.input);
          if (errEl) errEl.style.display = 'none';
          if (wrap) wrap.classList.remove('omk-field--err');
        } catch (x) {
          bad = true;
          if (errEl) { errEl.textContent = x.message; errEl.style.display = ''; }
          if (wrap) wrap.classList.add('omk-field--err');
        }
      });
      if (bad) { setStatus(tr('omk_fix_fields', 'Fix the highlighted fields first'), 'err'); return; }
      var plain = edits.map(function (e) { return { field: e.field, input: e.input }; });
      var text;
      try { text = applyEdits(state.lines, plain); }
      catch (x) { setStatus(x.message, 'err'); return; }
      var restartNeeded = needsRestart(plain);
      var notes = followUpNotes(plain);
      setBusy(true);
      var r = await run(omk('--write config ' + sq(toBase64(text)) + (restartNeeded ? ' restart' : '')));
      setBusy(false);
      if (r.code === 0) {
        var msg = tr(edits.length === 1 ? 'omk_saved_one' : 'omk_saved_many', edits.length === 1 ? 'Saved {n} change.' : 'Saved {n} changes.', { n: edits.length }) + ' ' +
          (restartNeeded ? tr('omk_restart_requested', 'KeyMint restart requested.') : tr('omk_applied_live', 'Applied live, no restart needed.')) + (notes ? ' ' + notes : '');
        await load();
        setStatus(msg, 'ok');
      } else {
        setStatus(tr('omk_save_failed', 'Save failed: {err}', { err: errText(r) }), 'err');
      }
    } else {
      var ta = $('omk-inj-text');
      if (!ta || !injDirty()) return;
      var problem = checkInjector(ta.value);
      if (problem) { setStatus(problem, 'err'); return; }
      setBusy(true);
      var r2 = await run(omk('--write injector ' + sq(toBase64(ta.value))));
      setBusy(false);
      if (r2.code === 0) {
        await load();
        showTab('injector');
        setStatus(tr('omk_inj_saved', 'Saved. OMK applies a valid injector.toml automatically; use Restart injector for a clean routing boundary.'), 'ok');
      } else {
        setStatus(tr('omk_save_failed', 'Save failed: {err}', { err: errText(r2) }), 'err');
      }
    }
  }

  async function restart(which) {
    if (state.busy) return;
    setBusy(true);
    var r = await run(omk('--restart ' + which));
    setBusy(false);
    var names = { injector: tr('omk_name_injector', 'Injector'), keymint: tr('omk_name_keymint', 'KeyMint'), both: tr('omk_name_both', 'Injector and KeyMint') };
    if (r.code === 0) setStatus(tr('omk_restart_requested_for', '{name} restart requested.', { name: names[which] }), 'ok');
    else setStatus(tr('omk_restart_failed', 'Restart failed: {err}', { err: errText(r) }), 'err');
  }

  async function restoreOriginal() {
    if (state.busy) return;
    var name = state.tab === 'config' ? 'config' : 'injector';
    var btn = $('omk-restore');
    var label = btn.querySelector('.pif-btn-label');
    if (!state.backups[name + '.orig']) {
      setStatus(tr('omk_no_backup', 'No original {file} saved yet. A copy is taken automatically before the first save.', { file: name + '.toml' }), '');
      return;
    }
    if (!state.confirmRestore) {
      state.confirmRestore = true;
      label.textContent = tr('omk_restore_confirm', 'Tap again to restore');
      setTimeout(function () { state.confirmRestore = false; label.textContent = tr('omk_restore', 'Restore'); }, 3000);
      return;
    }
    state.confirmRestore = false;
    label.textContent = tr('omk_restore', 'Restore');
    setBusy(true);
    var r = await run(omk('--restore ' + name + ' orig'));
    setBusy(false);
    if (r.code === 0) {
      await load();
      if (name === 'injector') showTab('injector');
      setStatus(tr('omk_restored', 'Restored the original {file}.', { file: name + '.toml' }), 'ok');
    } else {
      setStatus(tr('omk_restore_failed', 'Restore failed: {err}', { err: errText(r) }), 'err');
    }
  }

  async function reload() {
    if (state.busy) return;
    await load();
    setStatus(tr('omk_reloaded', 'Reloaded from disk.'), 'ok');
  }

  /* ---------- page ---------- */

  window.openOmkPanel = function () {
    var panel = $('omk-panel-root');
    if (!panel) return;
    panel.style.display = 'flex';
    var main = document.querySelector('main');
    if (main) main.style.overflow = 'hidden';
    state.confirmClose = false;
    showTab('config');
    load();
  };

  window.closeOmkPanel = function () {
    var panel = $('omk-panel-root');
    if (!panel) return;
    if (isDirty() && !state.confirmClose) {
      state.confirmClose = true;
      setStatus(tr('omk_unsaved', 'Unsaved changes. Tap back again to discard them.'), '');
      return;
    }
    panel.style.display = 'none';
    var main = document.querySelector('main');
    if (main) main.style.overflow = '';
    state.confirmClose = false;
  };

  document.addEventListener('languageChanged', function () {
    if (!$('omk-panel-root')) return;
    if (state.loaded && !isDirty()) renderConfig();
    else applyAdvanced();
    updateSaveBar();
  });

  document.addEventListener('DOMContentLoaded', function () {
    if (!$('omk-panel-root')) return;
    $('omk-reload').addEventListener('click', reload);
    $('omk-restore').addEventListener('click', restoreOriginal);
    $('omk-save-btn').addEventListener('click', save);
    $('omk-adv-btn').addEventListener('click', function () { state.advanced = !state.advanced; applyAdvanced(); });
    document.querySelectorAll('.omk-tab').forEach(function (b) {
      b.addEventListener('click', function () { showTab(b.getAttribute('data-omk-tab')); });
    });
    document.querySelectorAll('[data-omk-restart]').forEach(function (b) {
      b.addEventListener('click', function () { restart(b.getAttribute('data-omk-restart')); });
    });
  });

  window.__omkPanel = { parseToml: parseToml, applyEdits: applyEdits, serializeValue: serializeValue, validateValue: validateValue, needsRestart: needsRestart, followUpNotes: followUpNotes, checkInjector: checkInjector, parseStatus: parseStatus, toBase64: toBase64, groupOf: groupOf, isAdvancedField: isAdvancedField, isReadOnly: isReadOnly };
})();
