/* UI style: single default style.
   Choice is stored in localStorage ("uiStyle") and mirrored to the module config (ui_style).
   The data-ui-style attribute itself is set early by the inline script in index.html. */
(function () {
  var KEY = 'uiStyle';

  function normalize(v) { return 'default'; }
  function stored() { try { return localStorage.getItem(KEY); } catch (e) { return null; } }

  function apply(style) {
    style = normalize(style);
    document.documentElement.setAttribute('data-ui-style', style);
  }

  /* Status chips: classify the values the app already renders; nothing is invented. */
  var VALUE_IDS = ['status-value', 'android-value', 'root-value', 'rom-value', 'pif-status-value', 'keystore-backend-value'];

  function classify(id, text) {
    var empty = !text || text === '\u2014' || text === '-';
    if (id === 'status-value') {
      var chip = document.getElementById('network-chip');
      if (chip && chip.classList.contains('offline')) return 'error';
      return empty ? 'empty' : 'ok';
    }
    if (id === 'pif-status-value') return (empty || /^(unknown|not installed)$/i.test(text)) ? 'empty' : 'ok';
    return empty ? 'empty' : 'info';
  }

  function refreshState(id) {
    var el = document.getElementById(id);
    if (!el) return;
    var s = classify(id, (el.textContent || '').trim());
    if (el.getAttribute('data-state') !== s) el.setAttribute('data-state', s);
  }

  function watchValues() {
    VALUE_IDS.forEach(function (id) {
      var el = document.getElementById(id);
      if (!el) return;
      refreshState(id);
      new MutationObserver(function () { refreshState(id); })
        .observe(el, { childList: true, characterData: true, subtree: true });
    });
    var chip = document.getElementById('network-chip');
    if (chip) {
      new MutationObserver(function () { refreshState('status-value'); })
        .observe(chip, { attributes: true, attributeFilter: ['class'] });
    }
  }

  /* If localStorage was cleared but the module config still has the choice, restore it. */
  function restoreFromDisk(tries) {
    if (stored()) return;
    if (typeof window.ka !== 'function') {
      if (tries > 0) setTimeout(function () { restoreFromDisk(tries - 1); }, 500);
      return;
    }
    Promise.resolve(window.ka('ui_style', null)).then(function (v) {
      if (v === 'default') {
        apply(v);
        try { localStorage.setItem(KEY, v); } catch (e) {}
      }
    }).catch(function () {});
  }

  function init() {
    apply(stored());
    watchValues();
    restoreFromDisk(10);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
