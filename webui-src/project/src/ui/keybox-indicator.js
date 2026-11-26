  (function() {
    var RESULT_CLASSES = ['keybox-ok', 'keybox-revoked', 'keybox-outdated', 'keybox-unknown', 'keybox-none'];

    function t(key, fallback) {
      try { return (typeof window.__jerryGetTranslation === 'function' && window.__jerryGetTranslation(key)) || fallback; }
      catch (e) { return fallback; }
    }
    var CHECKING = t('keybox_checking', 'Checking…');

    function hasResult(card) {
      return RESULT_CLASSES.some(function(c) { return card.classList.contains(c); });
    }

    function init() {
      var card = document.getElementById('keybox-card');
      if (!card) return;

      if (hasResult(card)) return;

      card.classList.add('keybox-checking');

      var valueEl = document.getElementById('keybox-value');
      var prevText = valueEl ? valueEl.textContent : null;
      if (valueEl) valueEl.textContent = CHECKING;

      function checkDone() {
        if (hasResult(card)) {
          card.classList.remove('keybox-checking');
          observer.disconnect();
        }
      }

      var observer = new MutationObserver(checkDone);
      observer.observe(card, { attributes: true, attributeFilter: ['class'] });

      setTimeout(function() {
        card.classList.remove('keybox-checking');
        observer.disconnect();
        if (valueEl && valueEl.textContent === CHECKING) {
          valueEl.textContent = prevText || '—';
        }
      }, 8000);
    }

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', init);
    } else {
      init();
    }
  })();
