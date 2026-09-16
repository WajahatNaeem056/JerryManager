    (function() {
      function syncNetworkStatus() {
        var chip = document.getElementById('network-chip');
        var statusEl = document.getElementById('status-value');
        if (!chip || !statusEl) return;
        var label = chip.querySelector('#network-label');
        var isOffline = chip.classList.contains('offline');
        if (label) {
          statusEl.textContent = label.textContent || '—';
        }
        statusEl.style.color = isOffline ? '#ff5252' : '#2ecc71';

        if (!isOffline) {
          document.querySelectorAll('.md-toast').forEach(function(t) {
            if (/offline/i.test(t.textContent || '')) {
              t.parentNode && t.parentNode.removeChild(t);
            }
          });
        }
      }

      var observer = new MutationObserver(syncNetworkStatus);
      document.addEventListener('DOMContentLoaded', function() {
        var chip = document.getElementById('network-chip');
        if (chip) {
          observer.observe(chip, { attributes: true, subtree: true, childList: true, characterData: true });
          syncNetworkStatus();
        }

      });
    })();
