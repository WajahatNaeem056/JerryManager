  (function() {
    var ctrlGroups = {
      boot: {
        title: 'Boot Behavior',
        icon: 'security',
        desc: 'Choose which boot-time hardening and cleanup steps to apply.',
        toggles: [
          { key: 'toggle_recovery',           icon: 'folder_off',          def: '1', title: 'Auto-Hide Recovery Folders',  desc: 'Hide TWRP, OrangeFox, FOX recovery folders from /sdcard at boot' },
          { key: 'toggle_boot_hardening',     icon: 'security',            def: '1', title: 'Boot Hardening',              desc: 'Apply security prop hardening (ro.secure, ro.debuggable, etc.) at boot' },
          { key: 'toggle_bootloader_spoofer', icon: 'lock',                def: '1', title: 'Bootloader Spoofer Block',    desc: 'Remove conflicting bootloader spoofer packages at boot' },
          { key: 'toggle_rom_spoof',          icon: 'smartphone',          def: '1', title: 'Block ROM Spoof Engines',     desc: 'Disable ROM-level spoof engines (PixelProps, PIHooks, etc.)' },
          { key: 'toggle_rom_fingerprint',    icon: 'fingerprint',         def: '1', title: 'Clean ROM Fingerprint',       desc: 'Strip custom ROM identity (LineageOS, crDroid, PixelOS, etc.) from build props at boot' },
          { key: 'toggle_suspicious_props',   icon: 'visibility_off',      def: '1', title: 'Clean Suspicious Props',      desc: 'Scan for and clear known root/emulator/tamper-indicating system properties, at boot and hourly' },
          { key: 'toggle_lsposed',            icon: 'code',                def: '1', title: 'LSPosed ODEX Clean',          desc: 'Delete base.odex files from /data/app at boot (LSPosed trace clean)' }
        ]
      },
      custom_rom: {
        title: 'Custom Rom',
        icon: 'android',
        desc: 'LineageOS / custom-ROM identity spoofing and GApps-install trace cleanup.',
        toggles: [

          { key: 'toggle_hide_lineage',       icon: 'android',             def: '1', title: 'Hide Lineage',                desc: 'Spoofs LineageOS-specific properties (from hide_lineage.prop) so apps cannot detect a LineageOS-based custom ROM' },
          { key: 'toggle_nuke_lineage',       icon: 'delete_forever',      def: '0', title: 'Nuke Lineage',                desc: 'Medium risk: aggressively DELETES any prop whose value contains "lineage" at boot, instead of overriding it. Off by default — only enable if Hide Lineage is not enough.' },
          { key: 'toggle_hide_custom_rom',    icon: 'delete_sweep',        def: '1', title: 'Hide Custom ROM',             desc: 'Deletes leftover NikGapps/BitGApps/LiteGApps installer log files at boot. Does not hide root or affect Play Integrity — only removes GApps-install forensic traces. Irreversible delete, no backup.' },
          { key: 'toggle_remove_custom_rom_props', icon: 'delete_forever',  def: '1', title: 'Remove Custom ROM Properties', desc: 'Medium risk: deletes any prop whose key or value matches one of 24 known custom-ROM names (LineageOS, crDroid, PixelOS, GrapheneOS, Havoc, CalyxOS, and more), plus ro.modversion. Broader than Nuke Lineage, same collateral-deletion risk.' }
        ]
      },
      automation: {
        title: 'Automation',
        icon: 'radar',
        desc: 'Background automation for keystore backend targeting.',
        toggles: [
          { key: 'toggle_auto_target', icon: 'radar', def: '1', title: 'Auto Target New Apps', desc: 'Automatically detect newly installed apps and add them to target.txt' },
          { key: 'toggle_target_system', icon: 'apps', def: '0', title: 'Include System Apps', desc: 'Also scan and auto-target pre-installed system apps, not just user-installed ones' }
        ]
      },
      adb: {
        title: 'ADB & Debug Disabler',
        icon: 'usb_off',
        desc: 'Master switch plus fine-grained control over what gets hidden at boot.',
        toggles: [
          { key: 'toggle_adb_disabler',             icon: 'usb_off',        def: '0', title: 'Disable ADB & Debugging',    desc: 'Master switch for hiding USB debugging, developer options, and OEM unlock' },
          { key: 'toggle_adb_disabler_dev_options', icon: 'developer_mode', def: '0', title: 'Hide Developer Options',     desc: 'Disable development_settings_enabled at boot' },
          { key: 'toggle_adb_disabler_usb_debug',   icon: 'usb',            def: '0', title: 'Hide USB Debugging',         desc: 'Reset ro.debuggable, adb.secure and related debug props at boot' },
          { key: 'toggle_adb_disabler_oem_unlock',  icon: 'lock_person',    def: '0', title: 'Hide OEM Unlock Support',    desc: 'Report OEM unlock as unsupported at boot' }
        ]
      },
      action: {
        title: 'Action Pipeline',
        icon: 'list_alt',
        desc: 'Steps run automatically at boot after the core module init.',
        toggles: [
          { key: 'toggle_action_gms',            icon: 'block',                 def: '1', title: 'Kill Play Store',        desc: 'Force-stop and clear Play Store, GMS, and DroidGuard processes' },
          { key: 'toggle_action_target',         icon: 'list_alt',              def: '1', title: 'Regenerate Target',      desc: 'Regenerate the app target list for the active keystore backend' },
          { key: 'toggle_action_security_patch', icon: 'security_update_good',  def: '1', title: 'Set Security Patch',     desc: 'Write spoofed security patch date to the active keystore backend' },
          { key: 'toggle_action_boot_hash',       icon: 'verified',              def: '1', title: 'Set Verified Boot Hash', desc: 'Read and write verified boot hash for attestation' },
          { key: 'toggle_action_pif',             icon: 'fingerprint',           def: '1', title: 'Set Fingerprint (PIF)',  desc: 'Run Play Integrity Fix auto-update scripts' }
        ]
      }
    };

    function readKa(key, def) {
      try { return window.ka(key, def); } catch (e) { return Promise.resolve(def); }
    }
    function writeAa(key, val) {
      try { window.Aa(key, val); } catch (e) {}
    }

    function loadGroupValues(group) {
      return Promise.all(group.toggles.map(function(t) {
        return Promise.resolve(readKa(t.key, t.def)).then(function(v) {
          return { key: t.key, val: v === '1' ? '1' : '0' };
        }).catch(function() {
          return { key: t.key, val: t.def };
        });
      })).then(function(results) {
        var map = {};
        results.forEach(function(r) { map[r.key] = r.val; });
        return map;
      });
    }

    function updateBadge(groupId, group) {
      var badge = document.getElementById('ctrl-badge-' + groupId);
      if (!badge) return;
      loadGroupValues(group).then(function(vals) {
        var on = group.toggles.filter(function(t) { return vals[t.key] === '1'; }).length;
        badge.textContent = on + '/' + group.toggles.length + ' On';
      });
    }

    function refreshAllBadges() {
      Object.keys(ctrlGroups).forEach(function(id) { updateBadge(id, ctrlGroups[id]); });
    }

    function openGroupDialog(groupId) {
      var group = ctrlGroups[groupId];
      if (!group) return;

      var _isDark = document.documentElement.getAttribute('data-theme-resolved') === 'dark'
        || document.documentElement.getAttribute('data-theme') === 'dark';

      var dialog = document.createElement('md-dialog');
      dialog.style.setProperty('--md-dialog-container-color', _isDark ? '#1E1E1E' : '#ffffff');
      dialog.style.setProperty('--md-dialog-headline-color', _isDark ? '#F5F5F5' : '#252525');
      dialog.style.setProperty('--md-dialog-supporting-text-color', _isDark ? '#A0A0A0' : '#444444');

      var rowsHtml = group.toggles.map(function(t) {
        return '<div class="ctrl-dialog-row" data-key="' + t.key + '">' +
          '<md-icon style="font-size:22px;opacity:0.85">' + t.icon + '</md-icon>' +
          '<div class="ctrl-dialog-row-text">' +
            '<div class="ctrl-dialog-row-title">' + t.title + '</div>' +
            '<div class="ctrl-dialog-row-desc">' + t.desc + '</div>' +
          '</div>' +
          '<md-switch icons class="ctrl-dialog-switch" data-key="' + t.key + '"></md-switch>' +
        '</div>';
      }).join('');

      dialog.innerHTML =
        '<div slot="headline" style="padding:20px 24px 4px;display:flex;align-items:center;gap:10px;font-size:1.05rem;font-weight:600;color:' + (_isDark ? '#ffffff' : '#252525') + '">' +
          '<md-icon>' + group.icon + '</md-icon>' + group.title +
        '</div>' +
        '<div slot="content" style="padding:4px 24px">' +
          '<p style="margin:0 0 10px;font-size:0.78rem;opacity:0.65">' + group.desc + '</p>' +
          rowsHtml +
        '</div>' +
        '<div slot="actions" style="padding:4px 24px 20px;display:flex;align-items:center">' +
          '<div style="flex:1"></div>' +
          '<md-text-button id="ctrl-cancel-btn" style="--md-text-button-label-text-color:' + (_isDark ? '#b39ddb' : '#4a148c') + '">Cancel</md-text-button>' +
          '<md-filled-tonal-button id="ctrl-save-btn">Save</md-filled-tonal-button>' +
        '</div>';

      document.body.appendChild(dialog);

      var switches = dialog.querySelectorAll('.ctrl-dialog-switch');

      loadGroupValues(group).then(function(vals) {
        switches.forEach(function(sw) {
          sw.selected = vals[sw.getAttribute('data-key')] === '1';
        });
      });

      function closeDialog() {
        dialog.close();
        if (document.body.contains(dialog)) document.body.removeChild(dialog);
      }

      dialog.querySelector('#ctrl-cancel-btn').addEventListener('click', closeDialog);

      dialog.querySelector('#ctrl-save-btn').addEventListener('click', function() {
        switches.forEach(function(sw) {
          writeAa(sw.getAttribute('data-key'), sw.selected ? '1' : '0');
        });
        closeDialog();
        updateBadge(groupId, group);
      });

      dialog.addEventListener('close', function() {
        if (document.body.contains(dialog)) document.body.removeChild(dialog);
      });

      dialog.show();
    }

    function initCards() {
      Object.keys(ctrlGroups).forEach(function(groupId) {
        var card = document.getElementById('ctrl-card-' + groupId);
        if (card) card.addEventListener('click', function() { openGroupDialog(groupId); });
      });
      refreshAllBadges();
    }

    var _pollCount = 0;
    var _pollMax = 60;
    function pollAndInit() {
      if (typeof window.ka === 'function' && typeof window.Aa === 'function') {
        initCards();
      } else if (_pollCount < _pollMax) {
        _pollCount++;
        setTimeout(pollAndInit, 50);
      } else {
        console.warn('Jerry: window.ka/Aa not ready after 3s — control cards may not persist');
        initCards();
      }
    }

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', pollAndInit);
    } else {
      pollAndInit();
    }
  })();
