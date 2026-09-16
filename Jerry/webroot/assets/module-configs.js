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
          { key: 'toggle_suspicious_props',   icon: 'visibility_off',      def: '1', title: 'Clean Suspicious Props',      desc: 'Scan for and clear known root/emulator/tamper-indicating system properties, at boot and hourly' },
          { key: 'toggle_pif_traces',                 icon: 'cleaning_services', def: '1', title: 'Clean PIF Traces',    desc: 'Removes leftover spoofing traces (PIHook, PixelProps, and similar) from your device — helps avoid detection by security-checking apps' }
        ]
      },
      custom_rom: {
        title: 'Custom Rom',
        icon: 'android',
        desc: 'LineageOS / custom-ROM identity spoofing and GApps-install trace cleanup.',
        toggles: [

          { key: 'toggle_rom_fingerprint',    icon: 'fingerprint',         def: '0', title: 'Clean ROM Fingerprint',       desc: 'Strip custom ROM identity (LineageOS, crDroid, PixelOS, etc.) from build props at boot',
            detail: {
              title: 'ROM & Build Cleanup',
              desc: 'Clean custom ROM traces, debug build types, and module residue from properties.',
              items: [
                { key: 'toggle_rom_identifier_cleanup',      icon: 'label_off',   def: '0', title: 'ROM Identifier Cleanup',    desc: 'Delete any build property containing a custom ROM identifier (LineageOS, crDroid, PixelOS, and more).' },
                { key: 'toggle_rom_prefix_cleanup',     icon: 'text_fields', def: '0', title: 'ROM Prefix Cleanup', desc: 'Strip custom ROM prefixes (aosp_, lineage_) from build fingerprint and display id.' },
                { key: 'toggle_build_marker_cleanup', icon: 'build',       def: '0', title: 'Build Marker Cleanup',   desc: 'Strip userdebug/eng traces from build.flavor and build.fingerprint, and -dirty suffixes from build version props.' }
              ]
            }
          },
          { key: 'toggle_lineage_identity_cleanup',       icon: 'android',             def: '0', title: 'Lineage Identity Cleanup',                desc: 'Spoofs LineageOS-specific properties (from lineage_identity_cleanup.prop) so apps cannot detect a LineageOS-based custom ROM' },
          { key: 'toggle_nuke_lineage',       icon: 'delete_forever',      def: '0', title: 'Nuke Lineage',                desc: 'Medium risk: aggressively DELETES any prop whose value contains "lineage" at boot, instead of overriding it. Off by default — only enable if Lineage Identity Cleanup is not enough.' },
          { key: 'toggle_custom_rom_identity_cleanup',    icon: 'delete_sweep',        def: '0', title: 'Custom ROM Identity Cleanup',             desc: 'Deletes leftover NikGapps/BitGApps/LiteGApps installer log files at boot. Does not hide root or affect Play Integrity — only removes GApps-install forensic traces. Irreversible delete, no backup.' },
          { key: 'toggle_hide_rom_identifier', icon: 'delete_forever',  def: '0', title: 'Hide ROM Identifier', desc: 'Medium risk: deletes any prop whose key or value matches one of 24 known custom-ROM names (LineageOS, crDroid, PixelOS, GrapheneOS, Havoc, CalyxOS, and more), plus ro.modversion. Broader than Nuke Lineage, same collateral-deletion risk.' }
        ]
      },
      automation: {
        title: 'Automation',
        icon: 'radar',
        desc: 'Background automation for keystore backend targeting.',
        toggles: [
          { key: 'toggle_auto_target', icon: 'radar', def: '1', title: 'Auto Target New Apps', desc: 'Automatically detect newly installed apps and add them to target.txt' },
          { key: 'toggle_target_system', icon: 'apps', def: '0', title: 'Include System Apps', desc: 'Also scan and auto-target pre-installed system apps, not just user-installed ones' },
          { key: 'toggle_teesim_sync', icon: 'sync', def: '0', title: 'Sync TEESimulator Config', desc: 'If TEESimulator is installed, keep its device identity, security patch, and target list in sync with Jerry' }
        ]
      },
      adb: {
        title: 'ADB & Debug Disabler',
        icon: 'usb_off',
        desc: 'Master switch plus fine-grained control over what gets hidden at boot.',
        masterKey: 'toggle_adb_disabler',
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
          { key: 'toggle_action_gms_force_stop',  icon: 'stop_circle',           def: '1', title: 'Force-Stop GMS Apps',    desc: 'Kill DroidGuard, GMS, and Play Store processes; clear Play Store cache' },
          { key: 'toggle_action_gms_clear_data',  icon: 'delete_sweep',          def: '0', title: 'Clear Play Store Data',  desc: 'Full data wipe of Play Store — signs you out, more aggressive than cache clear. Off by default.' },
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

    function updateBadge(groupId) {
      var badge = document.getElementById('ctrl-badge-' + groupId);
      var container = document.getElementById('ctrl-rows-' + groupId);
      if (!badge || !container) return;
      var switches = container.querySelectorAll('.ctrl-row-switch');
      var total = switches.length;
      var on = 0;
      switches.forEach(function(sw) { if (sw.selected) on++; });
      badge.textContent = on + '/' + total;
    }

    function renderGroupRows(groupId, group) {
      var container = document.getElementById('ctrl-rows-' + groupId);
      if (!container) return;

      container.innerHTML = group.toggles.map(function(t) {
        var trailing = t.detail
          ? '<md-icon class="ctrl-chevron" data-role="chevron">chevron_right</md-icon>' +
            '<div class="ctrl-row-divider"></div>' +
            '<md-switch icons class="ctrl-row-switch" data-key="' + t.key + '"></md-switch>'
          : '<md-switch icons class="ctrl-row-switch" data-key="' + t.key + '"></md-switch>';
        return '<div class="ctrl-row' + (t.detail ? ' ctrl-row--detail' : '') + '" data-key="' + t.key + '">' +
          '<md-icon>' + t.icon + '</md-icon>' +
          '<div class="ctrl-row-content">' +
            '<div class="ctrl-row-title">' + t.title + '</div>' +
            '<span class="ctrl-row-desc">' + t.desc + '</span>' +
          '</div>' +
          trailing +
        '</div>';
      }).join('');

      var rows = container.querySelectorAll('.ctrl-row');
      var loads = [];
      var masterSw = group.masterKey ? container.querySelector('[data-key="' + group.masterKey + '"] .ctrl-row-switch') : null;

      function applyMasterLock(isOn) {
        if (!group.masterKey) return;
        rows.forEach(function(row) {
          var rKey = row.getAttribute('data-key');
          if (rKey === group.masterKey) return;
          var rSw = row.querySelector('.ctrl-row-switch');
          rSw.disabled = !isOn;
          row.classList.toggle('ctrl-row--locked', !isOn);
        });
      }

      rows.forEach(function(row) {
        var key = row.getAttribute('data-key');
        var toggleDef = group.toggles.filter(function(t) { return t.key === key; })[0];
        var sw = row.querySelector('.ctrl-row-switch');

        loads.push(
          Promise.resolve(readKa(key, toggleDef.def)).then(function(v) {
            sw.selected = v === '1';
          }).catch(function() {
            sw.selected = toggleDef.def === '1';
          })
        );

        sw.addEventListener('change', function() {
          writeAa(key, sw.selected ? '1' : '0');
          if (toggleDef.detail) {
            toggleDef.detail.items.forEach(function(item) {
              writeAa(item.key, sw.selected ? '1' : '0');
            });
          }
          if (group.masterKey && key === group.masterKey) {
            var _newVal = sw.selected;
            // Update visuals + lock state immediately — no perceived lag.
            rows.forEach(function(row2) {
              var rKey2 = row2.getAttribute('data-key');
              if (rKey2 === group.masterKey) return;
              var rSw2 = row2.querySelector('.ctrl-row-switch');
              rSw2.selected = _newVal;
            });
            applyMasterLock(_newVal);
            updateBadge(groupId);
            // Defer the actual backend writes to the next frame so the
            // switch animation isn't blocked by 3 sequential shell calls.
            requestAnimationFrame(function() {
              rows.forEach(function(row2) {
                var rKey2 = row2.getAttribute('data-key');
                if (rKey2 === group.masterKey) return;
                writeAa(rKey2, _newVal ? '1' : '0');
              });
            });
            return;
          }
          updateBadge(groupId);
        });

        if (toggleDef.detail) {
          row.querySelector('[data-role="chevron"]').addEventListener('click', function(e) {
            e.stopPropagation();
            openDetailDialog(toggleDef, groupId, sw);
          });
        }
      });

      Promise.all(loads).then(function() {
        if (masterSw) applyMasterLock(masterSw.selected);
        updateBadge(groupId);
      });
    }

    // Opens a Jerry-styled md-dialog for a row that has a `detail` block:
    // a master switch (the row's own toggle) plus its sub-toggle items.
    // Reuses the same md-dialog component and readKa/writeAa bridge as the
    // rest of the app — no new overlay system, no new persistence path.
    function openDetailDialog(toggleDef, groupId, outerSwitch) {
      var existing = document.getElementById('ctrl-detail-dialog');
      if (existing) existing.remove();

      var detail = toggleDef.detail;
      var dialog = document.createElement('md-dialog');
      dialog.id = 'ctrl-detail-dialog';
      dialog.innerHTML =
        '<div slot="headline">' + detail.title + '</div>' +
        '<div slot="content">' +
          (detail.desc ? '<p class="ctrl-dialog-desc">' + detail.desc + '</p>' : '') +
          '<div class="ctrl-dialog-row ctrl-dialog-row--master" id="ctrl-detail-master-row">' +
            '<div class="ctrl-dialog-row-text">' +
              '<div class="ctrl-dialog-row-title">' + toggleDef.title + '</div>' +
            '</div>' +
            '<md-switch icons id="ctrl-detail-master-switch"></md-switch>' +
          '</div>' +
          detail.items.map(function(item) {
            return '<div class="ctrl-dialog-row" data-key="' + item.key + '">' +
              '<div class="ctrl-dialog-row-text">' +
                '<div class="ctrl-dialog-row-title">' + item.title + '</div>' +
                '<div class="ctrl-dialog-row-desc">' + item.desc + '</div>' +
              '</div>' +
              '<md-switch icons class="ctrl-dialog-row-switch" data-key="' + item.key + '"></md-switch>' +
            '</div>';
          }).join('') +
        '</div>' +
        '<div slot="actions">' +
          '<md-text-button id="ctrl-detail-close">Close</md-text-button>' +
        '</div>';
      document.body.appendChild(dialog);

      var masterSwitch = dialog.querySelector('#ctrl-detail-master-switch');
      var itemSwitches = dialog.querySelectorAll('.ctrl-dialog-row-switch');

      // Master's current state is already known from the row switch that
      // opened this dialog — no need to re-read config for it.
      masterSwitch.selected = outerSwitch ? outerSwitch.selected : (toggleDef.def === '1');

      var loads = [];
      itemSwitches.forEach(function(sw) {
        var itemKey = sw.getAttribute('data-key');
        var itemDef = detail.items.filter(function(i) { return i.key === itemKey; })[0];
        loads.push(
          Promise.resolve(readKa(itemKey, itemDef.def)).then(function(v) {
            sw.selected = v === '1';
          }).catch(function() { sw.selected = itemDef.def === '1'; })
        );
      });

      masterSwitch.addEventListener('change', function() {
        writeAa(toggleDef.key, masterSwitch.selected ? '1' : '0');
        if (outerSwitch) outerSwitch.selected = masterSwitch.selected;
        itemSwitches.forEach(function(sw) {
          sw.selected = masterSwitch.selected;
          writeAa(sw.getAttribute('data-key'), masterSwitch.selected ? '1' : '0');
        });
        updateBadge(groupId);
      });

      itemSwitches.forEach(function(sw) {
        sw.addEventListener('change', function() {
          writeAa(sw.getAttribute('data-key'), sw.selected ? '1' : '0');
          updateBadge(groupId);
        });
      });

      dialog.querySelector('#ctrl-detail-close').addEventListener('click', function() { dialog.close(); });
      dialog.addEventListener('close', function() { dialog.remove(); });

      Promise.all(loads).then(function() { dialog.show(); });
    }

    function initRows() {
      Object.keys(ctrlGroups).forEach(function(groupId) {
        renderGroupRows(groupId, ctrlGroups[groupId]);
      });
    }

    var _pollCount = 0;
    var _pollMax = 60;
    function pollAndInit() {
      if (typeof window.ka === 'function' && typeof window.Aa === 'function') {
        initRows();
      } else if (_pollCount < _pollMax) {
        _pollCount++;
        setTimeout(pollAndInit, 50);
      } else {
        console.warn('Jerry: window.ka/Aa not ready after 3s — control rows may not persist');
        initRows();
      }
    }

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', pollAndInit);
    } else {
      pollAndInit();
    }
  })();
