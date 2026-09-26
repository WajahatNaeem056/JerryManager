  (function() {
    var main = document.querySelector('main');
    if (!main) return;

    var startX = 0, startY = 0, tracking = false;
    var THRESHOLD = 50;
    var MAX_OFF_AXIS = 60;

    function isInsideHorizontalScroller(target) {
      return !!(target.closest && target.closest('.at-chips-row'));
    }

    main.addEventListener('touchstart', function(e) {
      if (e.touches.length !== 1) { tracking = false; return; }
      if (isInsideHorizontalScroller(e.target)) { tracking = false; return; }
      startX = e.touches[0].clientX;
      startY = e.touches[0].clientY;
      tracking = true;
    }, { passive: true });

    main.addEventListener('touchend', function(e) {
      if (!tracking) return;
      tracking = false;

      var touch = e.changedTouches[0];
      var dx = touch.clientX - startX;
      var dy = touch.clientY - startY;

      if (Math.abs(dy) > MAX_OFF_AXIS) return;
      if (Math.abs(dx) < THRESHOLD) return;

      if (dx < 0) {
        if (window._jerryCurrentIndex < window._jerryPages.length - 1) {
          window.jerryNavSwitch(window._jerryCurrentIndex + 1);
        }
      } else {
        if (window._jerryCurrentIndex > 0) {
          window.jerryNavSwitch(window._jerryCurrentIndex - 1);
        }
      }
    }, { passive: true });
  })();
