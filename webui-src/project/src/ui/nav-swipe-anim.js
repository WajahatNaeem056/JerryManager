  var _jerryPages = ['home-page','actions-page','advanced-page','control-page','settings-page'];
  var _jerryCurrentIndex = 0;
  window._jerryPages = _jerryPages;
  Object.defineProperty(window, '_jerryCurrentIndex', {
    get: function() { return _jerryCurrentIndex; },
    configurable: true
  });

  var _spring = {
    pos: 0, vel: 0, target: 0,
    stiffness: 280, damping: 24,
    rafId: null, lastT: null
  };
  var _indicatorTopPx = null;
  var _JERRY_INDICATOR_ENABLED = false;

  function _getPillRect(index) {
    var tabs = document.querySelectorAll('.jerry-nav-tab');
    var tab  = tabs[index];
    if (!tab) return null;
    var pill = tab.querySelector('.jerry-nav-pill');
    if (!pill) return null;
    var inner = document.querySelector('.jerry-nav-inner');
    if (!inner) return null;

    var ind = document.getElementById('jerry-indicator');
    var indW = ind ? ind.offsetWidth  : 42;
    var indH = ind ? ind.offsetHeight : 42;

    var el = pill, offsetLeft = 0, offsetTop = 0;
    while (el && el !== inner) {
      offsetLeft += el.offsetLeft;
      offsetTop  += el.offsetTop;
      el = el.offsetParent;
    }

    return {

      left: offsetLeft + (pill.offsetWidth  - indW) / 2,
      top:  offsetTop  + (pill.offsetHeight - indH) / 2
    };
  }

  function _springTick(ts) {
    if (_spring.lastT === null) _spring.lastT = ts;
    var dt = Math.min((ts - _spring.lastT) / 1000, 0.064);
    _spring.lastT = ts;

    var force = (_spring.target - _spring.pos) * _spring.stiffness
                - _spring.vel * _spring.damping;
    _spring.vel += force * dt;
    _spring.pos += _spring.vel * dt;

    var ind = document.getElementById('jerry-indicator');
    if (ind) ind.style.left = _spring.pos.toFixed(2) + 'px';

    var settled = Math.abs(_spring.target - _spring.pos) < 0.15
               && Math.abs(_spring.vel) < 0.15;
    if (settled) {
      _spring.pos = _spring.target;
      if (ind) ind.style.left = _spring.pos + 'px';
      _spring.rafId = null;
      _spring.lastT = null;
    } else {
      _spring.rafId = requestAnimationFrame(_springTick);
    }
  }

  function _jerryMoveIndicator(index, animate) {
    if (!_JERRY_INDICATOR_ENABLED) return;
    var rect = _getPillRect(index);
    if (!rect) return;

    var ind = document.getElementById('jerry-indicator');

    if (ind && (_indicatorTopPx === null || !animate)) {
      _indicatorTopPx = rect.top;
      ind.style.top = _indicatorTopPx + 'px';
    }

    _spring.target = rect.left;

    if (!animate) {
      if (_spring.rafId) { cancelAnimationFrame(_spring.rafId); _spring.rafId = null; }
      _spring.pos = rect.left;
      _spring.vel = 0;
      _spring.lastT = null;
      if (ind) {
        ind.style.left = rect.left + 'px';
        ind.style.top  = rect.top  + 'px';
      }
      return;
    }

    if (!_spring.rafId) {
      _spring.lastT = null;
      _spring.rafId = requestAnimationFrame(_springTick);
    }
  }

  function jerryNavSwitch(index) {
    if (index === _jerryCurrentIndex) return;
    _jerryCurrentIndex = index;
    _jerryPages.forEach(function(id, i) {
      var page = document.getElementById(id);
      if (page) page.hidden = (i !== index);
    });
    document.querySelectorAll('.jerry-nav-tab').forEach(function(tab, i) {
      tab.classList.toggle('active', i === index);
    });
    _jerryMoveIndicator(index, true);
    var main = document.querySelector('main');
    if (main) main.scrollTop = 0;
  }
  window.jerryNavSwitch = jerryNavSwitch;

  document.addEventListener('DOMContentLoaded', function() {

    requestAnimationFrame(function() {
      _jerryMoveIndicator(0, false);
    });
    window.addEventListener('resize', function() {
      _indicatorTopPx = null;
      _jerryMoveIndicator(_jerryCurrentIndex, false);
    });
  });
