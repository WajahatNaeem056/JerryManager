    (function() {
      function setText(id, v) {
        var el = document.getElementById(id);
        if (el) el.textContent = v || '—';
      }
      function fetchInfo() {
        fetch('json/info.json?ts=' + Date.now())
          .then(function(r) { return r.json(); })
          .then(function(e) {
            if (!e) return;
            if (e.rom) setText('rom-value', e.rom);
            if (e.android) setText('android-value', e.android);
            if (e.root) setText('root-value', e.root);
            if (e.keystore_backend) setText('keystore-backend-value', e.keystore_backend);
          })
          .catch(function() {});
      }
      document.addEventListener('DOMContentLoaded', function() {
        fetchInfo();
        var hiddenBtn = document.getElementById('refresh-btn');
        if (hiddenBtn) {

          hiddenBtn.addEventListener('click', function() {
            setTimeout(fetchInfo, 900);
          });
        }
      });
    })();
