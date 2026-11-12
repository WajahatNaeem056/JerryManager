/* Extends the data-i18n loader (which only handles text content) to attributes:
   data-i18n-placeholder, data-i18n-aria-label, data-i18n-title */
(function () {
  'use strict';
  var MAP = [
    ['data-i18n-placeholder', 'placeholder'],
    ['data-i18n-aria-label', 'aria-label'],
    ['data-i18n-title', 'title']
  ];
  function apply() {
    if (typeof window.__jerryGetTranslation !== 'function') return;
    MAP.forEach(function (m) {
      document.querySelectorAll('[' + m[0] + ']').forEach(function (el) {
        var v = window.__jerryGetTranslation(el.getAttribute(m[0]));
        if (v) el.setAttribute(m[1], v);
      });
    });
  }
  document.addEventListener('languageChanged', apply);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', apply);
  else apply();
})();
