  (function() {
    var _atApps = [];
    var _atSystemApps = [];
    var _atFilter = 'all';
    var _atSearch = '';
    var _atApplyTimer = null;
    var _atSystemPkgSet = new Set();
    var _atSystemAppsVisible = false;
    var _atBackend = '';
    var _atPerAppPatches = {};

    var AT_ALWAYS_VISIBLE_SYSTEM_PKGS = [
      'com.google.android.gms', 'com.android.vending', 'com.oplus.deepthinker',
      'com.heytap.speechassist', 'com.coloros.sceneservice'
    ];

    window.atToggleMenu = function(e) {
      if (e) e.stopPropagation();
      var menu = document.getElementById('at-menu');
      if (!menu) return;
      menu.style.display = (menu.style.display === 'none' || !menu.style.display) ? 'block' : 'none';
    };

    (function() {
      function spawnRipple(btn, x, y) {
        var rect = btn.getBoundingClientRect();
        var size = Math.max(rect.width, rect.height) * 1.6;
        var ripple = document.createElement('span');
        ripple.className = 'at-ripple';
        ripple.style.width = size + 'px';
        ripple.style.height = size + 'px';
        ripple.style.left = (x - rect.left - size / 2) + 'px';
        ripple.style.top = (y - rect.top - size / 2) + 'px';
        btn.appendChild(ripple);
        ripple.addEventListener('animationend', function() { ripple.remove(); });
      }
      function wire(btn) {
        var press = function(e) {
          btn.classList.add('at-pressed');
          var pt = (e.touches && e.touches[0]) || e;
          spawnRipple(btn, pt.clientX, pt.clientY);
        };
        var release = function() { btn.classList.remove('at-pressed'); };
        btn.addEventListener('pointerdown', press);
        btn.addEventListener('pointerup', release);
        btn.addEventListener('pointerleave', release);
        btn.addEventListener('pointercancel', release);
      }
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function() {
          document.querySelectorAll('#at-menu .at-menu-item').forEach(wire);
        });
      } else {
        document.querySelectorAll('#at-menu .at-menu-item').forEach(wire);
      }
    })();

    document.addEventListener('click', function(e) {
      var menu = document.getElementById('at-menu');
      if (!menu || menu.style.display === 'none') return;
      if (!menu.contains(e.target) && e.target.getAttribute('aria-label') !== 'More options') {
        menu.style.display = 'none';
      }
    });

    window.openAppTargeting = async function() {
      var panel = document.getElementById('app-targeting-panel');
      panel.style.display = 'flex';
      document.querySelector('main').style.overflow = 'hidden';
      _atSystemAppsVisible = false;
      document.getElementById('at-title').textContent = 'App Targeting';
      var sysLabel = document.getElementById('at-menu-togglesystem-label');
      if (sysLabel) sysLabel.textContent = 'Show system apps';
      _atFilter = 'all';
      _atSearch = '';
      document.getElementById('at-search').value = '';
      atSetFilter('all');
      await _atLoad();
    };

    window.closeAppTargeting = function() {
      var panel = document.getElementById('app-targeting-panel');
      panel.style.display = 'none';
      document.querySelector('main').style.overflow = '';
    };

    window.atSetFilter = function(f) {
      _atFilter = f;
      ['all','selected','not-selected'].forEach(function(id) {
        var el = document.getElementById('at-chip-' + id);
        if (el) el.classList.toggle('at-chip-active', id === f);
      });
      _atRender();
    };

    var _atFilterDebounceTimer = null;
    window.atFilter = function() {

      var val = document.getElementById('at-search').value.toLowerCase();
      if (_atFilterDebounceTimer) clearTimeout(_atFilterDebounceTimer);
      _atFilterDebounceTimer = setTimeout(function() {
        _atSearch = val;
        _atRender();
      }, 150);
    };

    window.atApply = async function() {
      var btn = document.getElementById('at-apply-btn');
      var sav = document.getElementById('at-saving-indicator');
      btn.disabled = true;
      if (sav) sav.style.display = 'block';

      try {
        var selected = _atApps.filter(function(a) { return a.selected; }).map(function(a) {
          return a.pkg + (a.mode === 'generate' ? '!' : a.mode === 'hack' ? '?' : '');
        });

        AT_PROTECTED_PKGS.forEach(function(p) {
          if (selected.indexOf(p) === -1 && !selected.some(function(s) { return s.replace(/[!?]$/, '') === p; })) selected.push(p);
        });
        var pkgListShell = selected.map(function(p){ return "'" + p.replace(/'/g,"'\\''") + "'"; }).join(' ');
        var fullCmd =
          'MODDIR="' + (window.__jerry_moddir || '/data/adb/modules/JerryManager') + '"; ' +
          '. "$MODDIR/lib/common.sh" 2>/dev/null; . "$MODDIR/lib/paths.sh" 2>/dev/null; ' +
          '. "$MODDIR/lib/config_env.sh" 2>/dev/null; . "$MODDIR/lib/keystore.sh" 2>/dev/null; ' +
          'resolve_keystore_backend 2>/dev/null; ' +
          'if [ "$KEYSTORE_BACKEND" = "omk" ]; then ' +
            'mkdir -p "$OMK_DIR" 2>/dev/null; ' +
            '_at_tmp="$OMK_INJECTOR.tmp"; ' +
            'awk \'BEGIN{skip=0} /^scoop = \\[/{skip=1; next} skip==1 && /\\]/{skip=0; next} skip==1{next} {print}\' "$OMK_INJECTOR" > "$_at_tmp" 2>/dev/null || : > "$_at_tmp"; ' +
            '{ echo "scoop = ["; ' + (selected.length === 0 ? 'true' :
              'for p in ' + pkgListShell + '; do echo "    \\"$p\\"," ; done') + '; echo "]"; cat "$_at_tmp"; } > "$OMK_INJECTOR"; ' +
            'rm -f "$_at_tmp"; ' +
            'mkdir -p "$OMK_RESTART_DIR" 2>/dev/null; ' +
            'touch "$OMK_RESTART_DIR/restart.injector" 2>/dev/null; ' +
          'else ' +
            'mkdir -p "${TRICKY_DIR:-/data/adb/tricky_store}" 2>/dev/null; ' +
            (selected.length === 0
              ? 'true > "${TARGET_TXT:-/data/adb/tricky_store/target.txt}"; '
              : 'printf "%s\\n" ' + pkgListShell + ' > "${TARGET_TXT:-/data/adb/tricky_store/target.txt}"; ') +
          'fi; echo done';
        await window.shAsync(fullCmd);
        if (sav) { sav.textContent = 'Saved ✓'; sav.style.color = 'green'; }
        setTimeout(function() { if (sav) { sav.style.display = 'none'; sav.textContent = 'Saving…'; sav.style.color = ''; } }, 1800);
      } catch(e) {
        if (sav) { sav.textContent = 'Error!'; sav.style.color = 'red'; }
        setTimeout(function() { if (sav) { sav.style.display = 'none'; sav.textContent = 'Saving…'; sav.style.color = ''; } }, 2000);
        console.error('atApply error:', e);
      }
      btn.disabled = false;
    };

    async function _atLoad() {
      var loading = document.getElementById('at-loading');
      var list = document.getElementById('at-list');
      loading.style.display = 'flex';
      list.style.display = 'none';
      _atApps = [];

      try {

        var r1u = await window.shAsync('pm list packages -3 2>/dev/null');
        var r1s = await window.shAsync('pm list packages -s 2>/dev/null');
        var toPkgList = function(stdout) {
          return (stdout || '').trim().split('\n').filter(Boolean)
            .map(function(l) { return l.replace(/^package:/, '').trim(); })
            .filter(Boolean);
        };
        var userPkgs = [...new Set(toPkgList(r1u.stdout))].sort();
        var systemPkgs = [...new Set(toPkgList(r1s.stdout))].sort();
        var userPkgSet = new Set(userPkgs);
        systemPkgs = systemPkgs.filter(function(p) { return !userPkgSet.has(p); });
        var allPkgs = userPkgs.concat(systemPkgs);
        _atSystemPkgSet = new Set(systemPkgs);

        var readCmd =
          'MODDIR="' + (window.__jerry_moddir || '/data/adb/modules/JerryManager') + '"; ' +
          '. "$MODDIR/lib/common.sh" 2>/dev/null; . "$MODDIR/lib/paths.sh" 2>/dev/null; ' +
          '. "$MODDIR/lib/config_env.sh" 2>/dev/null; . "$MODDIR/lib/keystore.sh" 2>/dev/null; ' +
          'resolve_keystore_backend 2>/dev/null; ' +
          'echo "__BACKEND__:$KEYSTORE_BACKEND"; ' +
          'if [ "$KEYSTORE_BACKEND" = "omk" ]; then ' +
            'awk \'/^scoop = \\[/{f=1;next} f && /\\]/{f=0;next} f{gsub(/[",]/,"");gsub(/^[ \\t]+|[ \\t]+$/,"");if(length($0))print}\' "$OMK_INJECTOR" 2>/dev/null; ' +
          'else ' +
            'cat "${TARGET_TXT:-/data/adb/tricky_store/target.txt}" 2>/dev/null; ' +
          'fi; ' +
          'echo "__PATCHES__"; ' +
          'keystore_read_per_app_patches 2>/dev/null';
        var r2 = await window.shAsync(readCmd + ' || true');
        var r2lines = (r2.stdout || '').split('\n');
        var backendSplit = r2lines.findIndex(function(l) { return l.indexOf('__BACKEND__:') === 0; });
        _atBackend = backendSplit !== -1 ? r2lines[backendSplit].slice('__BACKEND__:'.length).trim() : '';
        var patchSplit = r2lines.findIndex(function(l) { return l === '__PATCHES__'; });
        var targetLines = r2lines.slice(backendSplit !== -1 ? backendSplit + 1 : 0, patchSplit !== -1 ? patchSplit : r2lines.length);
        _atPerAppPatches = {};
        if (patchSplit !== -1) {
          r2lines.slice(patchSplit + 1).forEach(function(l) {
            l = l.trim();
            if (!l) return;
            var sep = l.indexOf('|');
            if (sep === -1) return;
            var pkg = l.slice(0, sep);
            var m = l.slice(sep + 1).match(/boot=([^;]+)/);
            if (m) _atPerAppPatches[pkg] = m[1];
          });
        }
        var currentTargets = new Map();
        targetLines.forEach(function(l) {
          l = l.trim();
          if (!l) return;
          var mode = 'auto';
          if (l.endsWith('!')) { mode = 'generate'; l = l.slice(0, -1); }
          else if (l.endsWith('?')) { mode = 'hack'; l = l.slice(0, -1); }
          if (l) currentTargets.set(l, mode);
        });

        var labelMap = {};
        try {
          var ksuBridge = globalThis.ksu;
          if (ksuBridge && typeof ksuBridge.getPackagesInfo === 'function') {
            var infoArr = JSON.parse(ksuBridge.getPackagesInfo(JSON.stringify(allPkgs)));
            for (var li = 0; li < allPkgs.length && li < infoArr.length; li++) {
              var lbl = infoArr[li] && infoArr[li].appLabel;
              labelMap[allPkgs[li]] = (lbl && lbl !== allPkgs[li]) ? lbl : allPkgs[li];
            }
          }
        } catch (_) {  }

        if (_atSystemAppsVisible) {

          _atApps = allPkgs.map(function(pkg) {
            return { name: labelMap[pkg] || pkg, pkg: pkg, selected: currentTargets.has(pkg), mode: currentTargets.get(pkg) || 'auto', patchDate: _atPerAppPatches[pkg] || '' };
          }).sort(function(a, b) { return a.name.localeCompare(b.name); });
          _atSystemApps = [];
        } else {

          var alwaysVisibleSet = new Set(AT_ALWAYS_VISIBLE_SYSTEM_PKGS);
          var promoted = [];
          var stillSystemPkgs = [];
          systemPkgs.forEach(function(pkg) {
            if (alwaysVisibleSet.has(pkg) || currentTargets.has(pkg)) {
              promoted.push(pkg);
            } else {
              stillSystemPkgs.push(pkg);
            }
          });
          _atApps = userPkgs.concat(promoted).map(function(pkg) {
            return { name: labelMap[pkg] || pkg, pkg: pkg, selected: currentTargets.has(pkg), mode: currentTargets.get(pkg) || 'auto', patchDate: _atPerAppPatches[pkg] || '' };
          }).sort(function(a, b) { return a.name.localeCompare(b.name); });
          _atSystemApps = stillSystemPkgs.map(function(pkg) {
            return { name: labelMap[pkg] || pkg, pkg: pkg, selected: currentTargets.has(pkg), mode: currentTargets.get(pkg) || 'auto', patchDate: _atPerAppPatches[pkg] || '' };
          }).sort(function(a, b) { return a.name.localeCompare(b.name); });
        }

        loading.style.display = 'none';
        list.style.display = 'block';
        _atRender();
      } catch(e) {
        loading.innerHTML = '<span style="opacity:0.5;">Failed to load apps: ' + e.message + '</span>';
        console.error('atLoad error:', e);
      }
    }

    window.atSelectAll = function() {

      _atApps.forEach(function(a, i) {
        a.selected = true;
        var chk = document.getElementById('at-chk-' + i);
        if (chk) chk.classList.add('at-checked');
      });
      _atSystemApps.forEach(function(a) { a.selected = true; });
      var menu = document.getElementById('at-menu');
      if (menu) menu.style.display = 'none';
      _atRender();
    }

    window.atDeselectAll = function() {

      _atApps.forEach(function(a, i) {
        a.selected = false;
        var chk = document.getElementById('at-chk-' + i);
        if (chk) chk.classList.remove('at-checked');
      });
      _atSystemApps.forEach(function(a) { a.selected = false; });
      var menu = document.getElementById('at-menu');
      if (menu) menu.style.display = 'none';
      _atRender();
    }

    var AT_LOCAL_UNNECESSARY_PKGS = [

      'com.topjohnwu.magisk', 'io.github.vvb2060.magisk', 'io.github.huskydg.magisk',
      'me.weishu.kernelsu', 'com.rifsxd.ksunext', 'com.sukisu.ultra',
      'me.bmax.apatch', 'me.garfieldhan.apatch.next',
      'org.lsposed.manager', 'com.termux', 'bin.mt.plus', 'bin.mt.plus.canary',
      'xzr.konabess', 'io.github.a13e300.ksuwebui', 'moe.shizuku.privileged.api',
      'com.dergoogler.mmrl', 'com.dergoogler.mmrl.wx',

      'com.zhenxi.hunter', 'icu.nullptr.nativetest', 'icu.nullptr.applistdetector',
      'com.byxiaorun.detector', 'io.github.huskydg.memorydetector', 'com.OrangeEnvironment.Detector',
      'com.Longze.detector.pro2', 'rikka.safetynetchecker', 'io.github.vvb2060.keyattestation',
      'io.github.vvb2060.mahoshojo', 'com.lingqing.detector', 'aidepro.top',
      'com.junge.algorithmAidePro', 'chunqiu.safe', 'luna.safe.luna',
      'io.liankong.riskdetector', 'com.studio.duckdetector', 'com.android.nativetest',
      'com.byyoung.setting', 'com.scottyab.rootbeer', 'com.scottyab.rootbeer.sample',
      'com.topjohnwu.magisk.detector', 'com.devadvance.rootcloak', 'com.fde.xposed.detector',
      'com.zhenxi.checker', 'com.example.nativelibtest', 'com.example.memcheck',
      'com.example.syscallchecker', 'com.jrummyapps.rootchecker', 'com.kimchangyoun.magiskdetector',
      'com.reveny.nativechecker', 'com.reveny.environmentchecker', 'com.reveny.rootchecker',
      'com.guardian.detect', 'com.security.environmentchecker', 'com.integrity.checker',
      'com.integrity.attestation', 'com.lody.virtual', 'com.lody.virtual.client',
      'com.lody.virtual.server', 'com.lody.whale', 'com.kimchangyoun.rootbeerfresh',
      'com.didikee.rootcheck', 'com.joeykrim.rootcheck', 'com.freeandroidtools.rootchecker',
      'com.bluestacks.rootchecker', 'com.moonshine.checker', 'com.ramdroid.appdetector',
      'com.smlj.rootcheck', 'com.devadvance.rootcloakplus', 'com.formyhm.hideroot',
      'com.example.emulatordetector', 'com.vmcheck.detector', 'com.virtual.checker',
      'com.antivm.detector', 'com.xposed.checker', 'com.google.snet.test',
      'com.attestation.checker', 'com.integrity.check', 'com.native.checker',
      'com.syscall.detector', 'com.memory.scan', 'me.garfieldhan.holmes',

      'com.omarea.vtools', 'com.estrongs.android.pop',
      'com.sevtinge.hyperceiler', 'com.coderstory.toolkit',

      'com.android.chrome', 'com.google.android.apps.photos', 'com.google.android.youtube', 'mmrl',

      'io.github.lsposed.disableflagsecure', 'io.github.a13e300.fusefixer',
      'io.github.chsbuffer.revancedxposed', 'ps.reso.instaeclipse',
      'com.treatangus.elbowhitcolor', 'com.my.televip'
    ];

    var AT_PROTECTED_PKGS = new Set([
      'android', 'com.android.vending', 'com.google.android.gsf',
      'com.google.android.gms', 'com.google.android.ims',
      'com.google.android.contactkeys', 'com.google.android.safetycore',
      'com.google.android.apps.walletnfcrel', 'com.google.android.apps.nbu.paisa.user',
      'io.github.vvb2060.keyattestation', 'io.github.vvb2060.mahoshojo',
      'io.github.qwq233.keyattestation'
    ]);

    // Pulls Magisk's DenyList and selects every matching package here too,
    // so apps already hidden from root detection also get attestation
    // spoofing without adding them to both lists by hand. Same command
    // TrickyAddon uses: denylist entries are "pkg|process", isolated
    // (zygote-spawned) process rows are filtered out since they aren't
    // installed apps.
    window.atSyncDenyList = async function() {
      var menu = document.getElementById('at-menu');
      if (menu) menu.style.display = 'none';

      var sav = document.getElementById('at-saving-indicator');
      if (sav) { sav.style.display = 'block'; sav.textContent = 'Syncing…'; sav.style.color = ''; }

      try {
        var r = await window.shAsync(
          "magisk --denylist ls 2>/dev/null | awk -F'|' '{print $1}' | grep -v \"isolated\""
        );
        var denyPkgs = (r.stdout || '').trim().split('\n')
          .map(function(l) { return l.trim(); })
          .filter(Boolean);

        if (denyPkgs.length === 0) {
          if (sav) { sav.textContent = 'No DenyList entries found'; sav.style.color = ''; }
          setTimeout(function() { if (sav) sav.style.display = 'none'; }, 1800);
          return;
        }

        var denySet = new Set(denyPkgs);
        var addedCount = 0;

        _atApps.forEach(function(a) {
          if (denySet.has(a.pkg) && !a.selected) {
            a.selected = true;
            if (!a.mode) a.mode = 'auto';
            addedCount++;
          }
        });

        // Hidden system apps matching the DenyList need to be promoted
        // into _atApps (same as selecting them by hand) so the selection
        // is both visible and included when Apply reads _atApps.
        var stillHidden = [];
        _atSystemApps.forEach(function(a) {
          if (denySet.has(a.pkg)) {
            a.selected = true;
            if (!a.mode) a.mode = 'auto';
            addedCount++;
            _atApps.push(a);
          } else {
            stillHidden.push(a);
          }
        });
        _atSystemApps = stillHidden;

        _atRender();
        if (sav) {
          sav.textContent = addedCount > 0 ? ('Synced ' + addedCount + ' app(s) ✓') : 'Already in sync';
          sav.style.color = addedCount > 0 ? 'green' : '';
        }
        setTimeout(function() { if (sav) { sav.style.display = 'none'; sav.textContent = 'Saving…'; sav.style.color = ''; } }, 2200);
      } catch (e) {
        console.error('atSyncDenyList error:', e);
        if (sav) { sav.textContent = 'DenyList sync failed'; sav.style.color = 'red'; }
        setTimeout(function() { if (sav) { sav.style.display = 'none'; sav.textContent = 'Saving…'; sav.style.color = ''; } }, 2200);
      }
    };

    window.atDeselectUnnecessary = async function() {
      var menu = document.getElementById('at-menu');
      if (menu) menu.style.display = 'none';

      var excludeSet = new Set(AT_LOCAL_UNNECESSARY_PKGS);
      var url = 'https://raw.githubusercontent.com/KOWX712/Tricky-Addon-Update-Target-List/main/more-exclude.json';
      var resp = null;
      try { resp = await fetch(url); } catch (e) {}
      if (!resp || !resp.ok) {
        try { resp = await fetch('https://gh.sevencdn.com/' + url); } catch (e) {}
      }
      if (resp && resp.ok) {
        try {
          var json = await resp.json();
          json.data.forEach(function(group) {
            group.apps.forEach(function(app) {
              excludeSet.add(app['package-name']);
            });
          });
        } catch (e) {
          console.warn('Failed to parse online unnecessary apps list, using local list only');
        }
      } else {
        console.warn('Failed to fetch online unnecessary apps list, using local list only');
      }

      try {
        var mod = await import('./bridge-BHYUl5TK.js');
        var bridge = mod.t;
        await bridge.initBridge();
        var xposedResult = await bridge.runScript('get_xposed.sh', 'common');
        (xposedResult.output || '').split('\n').forEach(function(pkg) {
          pkg = pkg.trim();
          if (pkg) excludeSet.add(pkg);
        });
      } catch (e) {
        console.warn('Live Xposed scan unavailable, using remote + local lists only');
      }

      function deselectIfUnnecessary(a, i, chkPrefix) {
        if (excludeSet.has(a.pkg) && !AT_PROTECTED_PKGS.has(a.pkg)) {
          a.selected = false;
          if (chkPrefix) {
            var chk = document.getElementById(chkPrefix + i);
            if (chk) chk.classList.remove('at-checked');
          }
        }
      }

      _atApps.forEach(function(a, i) { deselectIfUnnecessary(a, i, 'at-chk-'); });
      _atSystemApps.forEach(function(a) { deselectIfUnnecessary(a); });

      _atRender();
    }

    window.atToggleSystemApps = function() {
      var menu = document.getElementById('at-menu');
      var btn = document.getElementById('at-menu-togglesystem-label');
      _atSystemAppsVisible = !_atSystemAppsVisible;
      if (_atSystemAppsVisible) {
        _atApps = _atApps.concat(_atSystemApps);
        _atSystemApps = [];
      } else {
        var kept = [];
        var moved = [];
        _atApps.forEach(function(a) {
          (_atSystemPkgSet && _atSystemPkgSet.has(a.pkg)) ? moved.push(a) : kept.push(a);
        });
        _atApps = kept;
        _atSystemApps = moved;
      }
      if (btn) btn.textContent = _atSystemAppsVisible ? 'Hide system apps' : 'Show system apps';
      if (menu) menu.style.display = 'none';
      _atRender();
    };

    function _atRender() {
      var list = document.getElementById('at-list');
      if (!list) return;

      var searchActive = !!_atSearch;
      if (searchActive) {

        var stillSystem = [];
        _atSystemApps.forEach(function(a) {
          if (a.selected) { _atApps.push(a); } else { stillSystem.push(a); }
        });
        _atSystemApps = stillSystem;
      }

      var pool = searchActive ? _atApps.concat(_atSystemApps) : _atApps;

      var filtered = pool.filter(function(a) {
        if (_atFilter === 'selected' && !a.selected) return false;
        if (_atFilter === 'not-selected' && a.selected) return false;
        if (_atSearch && a.pkg.toLowerCase().indexOf(_atSearch) === -1 && (a.name || '').toLowerCase().indexOf(_atSearch) === -1) return false;
        return true;
      });

      if (filtered.length === 0) {
        list.innerHTML = '<div style="text-align:center;padding:40px;opacity:0.5;">No apps found</div>';
        return;
      }

      var html = filtered.map(function(a, i) {
        var idx = _atApps.indexOf(a);
        var sysIdx = idx === -1 ? _atSystemApps.indexOf(a) : -1;
        var chkSvg = '<svg viewBox="0 0 24 24" width="13" height="13" fill="#fff"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41L9 16.17z"/></svg>';
        var isSys = idx === -1;
        var targetIdx = !isSys ? idx : sysIdx;
        var toggleCall = !isSys ? '_atToggle(' + idx + ')' : '_atToggleSystem(' + sysIdx + ')';
        var chkId = !isSys ? 'at-chk-' + idx : 'at-chk-sys-' + sysIdx;

        // Selected rows open the mode dialog on tap (checkbox has its own
        // stopPropagation'd click to select/deselect). Not-yet-selected
        // rows keep the original behavior: tapping anywhere selects them.
        var rowClickAttr = a.selected
          ? 'onclick="atOpenModeDialog(' + targetIdx + ',' + isSys + ')"'
          : 'onclick="' + toggleCall + '" data-idx="' + targetIdx + '"';
        var chkClickAttr = 'onclick="event.stopPropagation();' + toggleCall + '"';

        var modeLabel = a.mode === 'generate' ? '!' : a.mode === 'hack' ? '?' : '';
        var modeBadge = (a.selected && modeLabel)
          ? '<div class="at-mode-badge at-mode-badge--' + a.mode + '">' + modeLabel + '</div>'
          : '';
        return '<div class="at-app-row" ' + rowClickAttr + '>' +
          '<img class="at-app-icon" data-pkg="' + _escHtml(a.pkg) + '" alt="" loading="lazy" />' +
          '<div style="flex:1;min-width:0;">' +
          '<div class="at-app-name" style="font-weight:600;font-size:14px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">' + _escHtml(a.name) + '</div>' +
          '<div class="at-app-sub" style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">' + _escHtml(a.pkg) + '</div>' +
          '</div>' +
          modeBadge +
          '<div class="at-checkbox' + (a.selected ? ' at-checked' : '') + '" id="' + chkId + '" ' + chkClickAttr + '>' +
          (a.selected ? chkSvg : '') +
          '</div>' +
          '</div>';
      }).join('');

      list.innerHTML = html;
      _atLoadIcons(list);
    }

    var _atDefaultIcon = 'data:image/svg+xml;utf8,' + encodeURIComponent(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="#9999aa">' +
      '<path d="M6 18c0 .55.45 1 1 1h1v3.5c0 .83.67 1.5 1.5 1.5s1.5-.67 1.5-1.5V19h2v3.5c0 .83.67 1.5 1.5 1.5s1.5-.67 1.5-1.5V19h1c.55 0 1-.45 1-1V8H6v10zM3.5 8C2.67 8 2 8.67 2 9.5v7c0 .83.67 1.5 1.5 1.5S5 17.33 5 16.5v-7C5 8.67 4.33 8 3.5 8zm17 0c-.83 0-1.5.67-1.5 1.5v7c0 .83.67 1.5 1.5 1.5s1.5-.67 1.5-1.5v-7c0-.83-.67-1.5-1.5-1.5zm-4.97-5.84l1.3-1.3c.2-.2.2-.51 0-.71-.2-.2-.51-.2-.71 0l-1.48 1.48C13.85 1.23 12.95 1 12 1c-.96 0-1.86.23-2.66.63L7.85.15c-.2-.2-.51-.2-.71 0-.2.2-.2.51 0 .71l1.31 1.31C6.97 3.26 6 5.01 6 7h12c0-1.99-.97-3.75-2.47-4.84zM10 5H9V4h1v1zm5 0h-1V4h1v1z"/>' +
      '</svg>'
    );

    var _atIconObserver = null;
    function _atLoadIcons(container) {
      if (_atIconObserver) { _atIconObserver.disconnect(); }
      var imgs = container.querySelectorAll('.at-app-icon[data-pkg]');
      _atIconObserver = new IntersectionObserver(function(entries) {
        entries.forEach(function(entry) {
          if (!entry.isIntersecting) return;
          var img = entry.target;
          _atIconObserver.unobserve(img);
          _atResolveIcon(img, img.dataset.pkg);
        });
      }, { root: container.closest('.at-list, #at-list') || null, rootMargin: '200px' });
      imgs.forEach(function(img) { _atIconObserver.observe(img); });
    }

    function _atResolveIcon(img, pkg) {
      img.onerror = function() { img.onerror = null; img.src = _atDefaultIcon; };
      try {
        var pm = globalThis.$packageManager;
        if (pm && typeof pm.getApplicationIcon === 'function') {
          var uri = pm.getApplicationIcon(pkg, 0, 0);
          if (uri) {
            fetch(uri).then(function(r) { return r.arrayBuffer(); }).then(function(buf) {
              var bytes = new Uint8Array(buf), bin = '';
              for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
              img.src = 'data:image/png;base64,' + btoa(bin);
            }).catch(function() { img.src = 'ksu://icon/' + pkg; });
            return;
          }
        }
      } catch (e) {}
      img.src = 'ksu://icon/' + pkg;
    }

    window._atToggle = function(idx) {
      if (!_atApps[idx]) return;
      _atApps[idx].selected = !_atApps[idx].selected;
      if (_atApps[idx].selected && !_atApps[idx].mode) _atApps[idx].mode = 'auto';
      _atRender();
    };

    window._atToggleSystem = function(sysIdx) {
      if (!_atSystemApps[sysIdx]) return;
      var app = _atSystemApps[sysIdx];
      app.selected = !app.selected;
      if (app.selected && !app.mode) app.mode = 'auto';
      if (app.selected) {

        _atSystemApps.splice(sysIdx, 1);
        _atApps.push(app);
        _atRender();
        return;
      }
      _atRender();
    };

    // Patch date saves immediately (writes security_patch.txt directly);
    // mode is still persisted later via atApply.
    window.atOpenModeDialog = function(idx, isSys) {
      var app = isSys ? _atSystemApps[idx] : _atApps[idx];
      if (!app) return;

      var existing = document.getElementById('at-mode-dialog');
      if (existing) existing.remove();

      var patchSupported = _atBackend === 'trickystore';
      var patchSection = patchSupported
        ? '<div class="at-patch-date-section">' +
            '<label style="font-size:0.8rem;opacity:0.7;display:block;margin-bottom:4px;">Custom security patch date (optional)</label>' +
            '<input type="date" id="at-patch-date-input" value="' + _escHtml(app.patchDate || '') + '" style="width:100%;box-sizing:border-box;" />' +
            (app.patchDate ? '<button type="button" id="at-patch-date-clear" style="margin-top:6px;background:none;border:none;color:inherit;opacity:0.7;font-size:0.8rem;text-decoration:underline;cursor:pointer;">Remove override</button>' : '') +
          '</div>'
        : '';

      var dialog = document.createElement('md-dialog');
      dialog.id = 'at-mode-dialog';
      dialog.innerHTML =
        '<div slot="headline">' +
          '<div>Attestation Mode</div>' +
          '<div style="font-size:12px;font-weight:400;opacity:0.6;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">' + _escHtml(app.name) + '</div>' +
        '</div>' +
        '<div slot="content" class="at-mode-options">' +
          '<label class="at-mode-option">' +
            '<input type="radio" name="at-mode" value="auto"' + (app.mode !== 'generate' && app.mode !== 'hack' ? ' checked' : '') + '>' +
            '<span>Auto</span>' +
          '</label>' +
          '<label class="at-mode-option">' +
            '<input type="radio" name="at-mode" value="generate"' + (app.mode === 'generate' ? ' checked' : '') + '>' +
            '<span>Generate certificate</span>' +
            '<span class="at-mode-icon at-mode-icon--generate">!</span>' +
          '</label>' +
          '<label class="at-mode-option">' +
            '<input type="radio" name="at-mode" value="hack"' + (app.mode === 'hack' ? ' checked' : '') + '>' +
            '<span>Leaf hack</span>' +
            '<span class="at-mode-icon at-mode-icon--hack">?</span>' +
          '</label>' +
          patchSection +
        '</div>' +
        '<div slot="actions">' +
          '<md-text-button id="at-mode-cancel">Cancel</md-text-button>' +
          '<md-filled-button id="at-mode-save">Save</md-filled-button>' +
        '</div>';
      document.body.appendChild(dialog);

      dialog.querySelector('#at-mode-cancel').addEventListener('click', function() { dialog.close(); });

      var clearBtn = dialog.querySelector('#at-patch-date-clear');
      if (clearBtn) {
        clearBtn.addEventListener('click', function() {
          var input = dialog.querySelector('#at-patch-date-input');
          if (input) input.value = '';
        });
      }

      dialog.querySelector('#at-mode-save').addEventListener('click', async function() {
        var picked = dialog.querySelector('input[name="at-mode"]:checked');
        app.mode = picked ? picked.value : 'auto';

        if (patchSupported) {
          var dateInput = dialog.querySelector('#at-patch-date-input');
          var newDate = dateInput ? dateInput.value.trim() : '';
          if (newDate !== (app.patchDate || '')) {
            var saveBtn = dialog.querySelector('#at-mode-save');
            saveBtn.disabled = true;
            try {
              var moddir = window.__jerry_moddir || '/data/adb/modules/JerryManager';
              var cmd = 'MODDIR="' + moddir + '"; ' +
                '. "$MODDIR/lib/common.sh" 2>/dev/null; . "$MODDIR/lib/paths.sh" 2>/dev/null; ' +
                '. "$MODDIR/lib/config_env.sh" 2>/dev/null; . "$MODDIR/lib/keystore.sh" 2>/dev/null; ' +
                'resolve_keystore_backend 2>/dev/null; ';
              if (newDate) {
                cmd += 'keystore_set_per_app_patch ' + "'" + app.pkg.replace(/'/g, "'\\''") + "'" + ' ' + "'" + newDate.replace(/'/g, "'\\''") + "'";
              } else {
                cmd += 'keystore_remove_per_app_patch ' + "'" + app.pkg.replace(/'/g, "'\\''") + "'";
              }
              await window.shAsync(cmd);
              app.patchDate = newDate;
              _atPerAppPatches[app.pkg] = newDate || undefined;
            } catch (e) {
              console.error('per-app patch date save failed:', e);
            }
            saveBtn.disabled = false;
          }
        }

        dialog.close();
        _atRender();
      });
      dialog.addEventListener('close', function() { dialog.remove(); });

      dialog.show();
    };

    function _escHtml(s) {
      return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    }
  })();
