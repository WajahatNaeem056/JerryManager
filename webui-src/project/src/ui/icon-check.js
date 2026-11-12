/* If the icon font cannot be loaded (offline and no bundled MaterialSymbolsRounded.woff2), hide the
   ligature text so rows show blank icon slots instead of words like "home" or "shield". */
(function () {
  var root = document.documentElement, tries = 0;
  function loaded() {
    var s = document.createElement('span');
    s.style.cssText = 'position:absolute;left:-9999px;top:0;font-size:40px;line-height:1;white-space:nowrap;font-family:"JM Symbols","Material Symbols Rounded",monospace;font-feature-settings:"liga"';
    s.textContent = 'check_circle';
    document.body.appendChild(s);
    var w = s.getBoundingClientRect().width;
    document.body.removeChild(s);
    return w < 90; /* one glyph ~40px; plain text ~300px */
  }
  function run() {
    if (!document.body) return;
    var ok = loaded();
    root.setAttribute('data-icons', ok ? 'ok' : 'missing');
    if (!ok && tries++ < 8) setTimeout(run, 1500);
  }
  function start() {
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(run); else run();
    if (document.fonts && document.fonts.addEventListener) document.fonts.addEventListener('loadingdone', run);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
