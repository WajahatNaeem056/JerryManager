    (function() {
      var POLL_MS = 5000;
      var lastValue = null;
      var timerId = null;

      function setPifStatusValue(v) {
        var el = document.getElementById('pif-status-value');
        if (!el) return;
        var display = (v && v.trim()) ? v.trim() : 'Unknown';
        if (display === lastValue) return;
        lastValue = display;
        el.textContent = display;
      }

      async function pollOnce() {
        try {
          var bridge = window.JerryBridge; // set by the bundled app (src/main.js)
          if (!bridge) throw new Error('JerryBridge not ready');
          await bridge.initBridge();
          var result = await bridge.runScript('pif-status.sh', 'common');
          if (!result || result.success === false) { setPifStatusValue(null); return; }
          var parsed = null;
          try { parsed = JSON.parse(result.output || result.rawOutput || ''); } catch (e) {}
          setPifStatusValue(parsed && parsed.pif_status);
        } catch (e) {

          setPifStatusValue(null);
        }
      }

      function startPolling() {
        if (timerId) return;
        pollOnce();
        timerId = setInterval(pollOnce, POLL_MS);
      }
      function stopPolling() {
        if (!timerId) return;
        clearInterval(timerId);
        timerId = null;
      }

      document.addEventListener('DOMContentLoaded', function() {
        if (document.getElementById('pif-status-value')) startPolling();
        document.addEventListener('visibilitychange', function() {
          if (document.hidden) stopPolling(); else startPolling();
        });
      });
    })();
