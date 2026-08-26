    (function() {
      function setRomValue(v) {
        var el = document.getElementById('rom-value');
        if (el) el.textContent = v || '—';
      }
      function fetchRom() {
        fetch('json/info.json?ts=' + Date.now())
          .then(function(r) { return r.json(); })
          .then(function(e) { if (e && e.rom) setRomValue(e.rom); })
          .catch(function() {});
      }
      document.addEventListener('DOMContentLoaded', function() {
        fetchRom();
        var hiddenBtn = document.getElementById('refresh-btn');
        if (hiddenBtn) {

          hiddenBtn.addEventListener('click', function() {
            setTimeout(fetchRom, 900);
          });
        }
      });
    })();
