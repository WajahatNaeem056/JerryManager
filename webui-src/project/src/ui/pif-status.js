    (function() {
      var POLL_MS = 15000;
      var lastValue = null;
      var timerId = null;

      // loaded=false: nothing could be read, show the same dash as the other rows.
      // loaded=true with no model: the script ran but found no PIF model, so "Unknown".
      function setPifStatusValue(v, loaded) {
        var el = document.getElementById('pif-status-value');
        if (!el) return;
        var display = (v && v.trim()) ? v.trim() : (loaded ? 'Unknown' : '\u2014');
        if (display === lastValue) return;
        lastValue = display;
        el.textContent = display;
      }

      async function readJson() {
        try {
          var r = await fetch('/json/pif_status.json?ts=' + Date.now());
          var parsed = await r.json();
          setPifStatusValue(parsed && parsed.pif_status, true);
        } catch (e) {
          setPifStatusValue(null, false);
        }
      }

      async function pollOnce() {
        try {
          var bridge = window.JerryBridge; // set by the bundled app (src/main.js)
          if (!bridge) throw new Error('JerryBridge not ready');
          await bridge.initBridge();
          var p = bridge.spawnScript('pif-status.sh', 'common');
          var done = function () { readJson(); };
          p.on('exit', done);
          p.on('error', done);
        } catch (e) {
          setPifStatusValue(null, false);
        }
      }

      function startPolling() {
        if (timerId) return;
        readJson();
        setTimeout(pollOnce, 2000);
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
