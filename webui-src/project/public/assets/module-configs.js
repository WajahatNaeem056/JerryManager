  (function() {
    var ctrlGroups = {
      boot: {
        titleKey: 'control_boot_title', title: 'Boot Behavior',
        icon: 'security',
        descKey: 'control_boot_desc', desc: 'Choose which boot-time hardening and cleanup steps to apply.',
        toggles: [
          { key: 'toggle_recovery',           icon: 'folder_off',          def: '1', titleKey: 'control_toggle_recovery', title: 'Auto-Hide Recovery Folders',  descKey: 'control_toggle_recovery_desc', desc: 'Hide TWRP, OrangeFox, FOX recovery folders from /sdcard at boot' },
          { key: 'toggle_boot_hardening',     icon: 'security',            def: '1', titleKey: 'control_toggle_boot_hardening', title: 'Boot Hardening',              descKey: 'control_toggle_boot_hardening_desc', desc: 'Apply security prop hardening (ro.secure, ro.debuggable, etc.) at boot' },
          { key: 'toggle_bootloader_spoofer', icon: 'lock',                def: '1', titleKey: 'control_toggle_bootloader_spoofer', title: 'Bootloader Spoofer Block',    descKey: 'control_toggle_bootloader_spoofer_desc', desc: 'Remove conflicting bootloader spoofer packages at boot' },
          { key: 'toggle_rom_spoof',          icon: 'smartphone',          def: '1', titleKey: 'control_toggle_rom_spoof', title: 'Block ROM Spoof Engines',     descKey: 'control_toggle_rom_spoof_desc', desc: 'Disable ROM-level spoof engines (PixelProps, PIHooks, etc.)' },
          { key: 'toggle_suspicious_props',   icon: 'visibility_off',      def: '1', titleKey: 'control_toggle_suspicious_props', title: 'Clean Suspicious Props',      descKey: 'control_toggle_suspicious_props_desc', desc: 'Scan for and clear known root/emulator/tamper-indicating system properties, at boot and hourly' },
          { key: 'toggle_pif_traces',                 icon: 'cleaning_services', def: '1', titleKey: 'control_toggle_pif_traces', title: 'Clean PIF Traces',    descKey: 'control_toggle_pif_traces_desc', desc: 'Removes leftover spoofing traces (PIHook, PixelProps, and similar) from your device — helps avoid detection by security-checking apps' }
        ]
      },
      custom_rom: {
        titleKey: 'control_custom_rom_title', title: 'Custom Rom',
        icon: 'android',
        descKey: 'control_custom_rom_desc', desc: 'LineageOS / custom-ROM identity spoofing and GApps-install trace cleanup.',
        toggles: [

          { key: 'toggle_rom_fingerprint',    icon: 'fingerprint',         def: '0', titleKey: 'control_toggle_rom_fingerprint', title: 'Clean ROM Fingerprint',       descKey: 'control_toggle_rom_fingerprint_desc', desc: 'Strip custom ROM identity (LineageOS, crDroid, PixelOS, etc.) from build props at boot',
            detail: {
              titleKey: 'control_rom_build_cleanup_title', title: 'ROM & Build Cleanup',
              descKey: 'control_rom_build_cleanup_desc', desc: 'Clean custom ROM traces, debug build types, and module residue from properties.',
              items: [
                { key: 'toggle_rom_identifier_cleanup',      icon: 'label_off',   def: '0', titleKey: 'control_toggle_rom_identifier_cleanup', title: 'ROM Identifier Cleanup',    descKey: 'control_toggle_rom_identifier_cleanup_desc', desc: 'Delete any build property containing a custom ROM identifier (LineageOS, crDroid, PixelOS, and more).' },
                { key: 'toggle_rom_prefix_cleanup',     icon: 'text_fields', def: '0', titleKey: 'control_toggle_rom_prefix_cleanup', title: 'ROM Prefix Cleanup', descKey: 'control_toggle_rom_prefix_cleanup_desc', desc: 'Strip custom ROM prefixes (aosp_, lineage_) from build fingerprint and display id.' },
                { key: 'toggle_build_marker_cleanup', icon: 'build',       def: '0', titleKey: 'control_toggle_build_marker_cleanup', title: 'Build Marker Cleanup',   descKey: 'control_toggle_build_marker_cleanup_desc', desc: 'Strip userdebug/eng traces from build.flavor and build.fingerprint, and -dirty suffixes from build version props.' }
              ]
            }
          },
          { key: 'toggle_lineage_identity_cleanup',       icon: 'android',             def: '0', titleKey: 'control_toggle_lineage_identity_cleanup', title: 'Lineage Identity Cleanup',                descKey: 'control_toggle_lineage_identity_cleanup_desc', desc: 'Spoofs LineageOS-specific properties (from lineage_identity_cleanup.prop) so apps cannot detect a LineageOS-based custom ROM' },
          { key: 'toggle_nuke_lineage',       icon: 'delete_forever',      def: '0', titleKey: 'control_toggle_nuke_lineage', title: 'Nuke Lineage',                descKey: 'control_toggle_nuke_lineage_desc', desc: 'Medium risk: aggressively DELETES any prop whose value contains "lineage" at boot, instead of overriding it. Off by default — only enable if Lineage Identity Cleanup is not enough.' },
          { key: 'toggle_custom_rom_identity_cleanup',    icon: 'delete_sweep',        def: '0', titleKey: 'control_toggle_custom_rom_identity_cleanup', title: 'Custom ROM Identity Cleanup',             descKey: 'control_toggle_custom_rom_identity_cleanup_desc', desc: 'Deletes leftover NikGapps/BitGApps/LiteGApps installer log files at boot. Does not hide root or affect Play Integrity — only removes GApps-install forensic traces. Irreversible delete, no backup.' },
          { key: 'toggle_hide_rom_identifier', icon: 'delete_forever',  def: '0', titleKey: 'control_toggle_hide_rom_identifier', title: 'Hide ROM Identifier', descKey: 'control_toggle_hide_rom_identifier_desc', desc: 'Medium risk: deletes any prop whose key or value matches one of 24 known custom-ROM names (LineageOS, crDroid, PixelOS, GrapheneOS, Havoc, CalyxOS, and more), plus ro.modversion. Broader than Nuke Lineage, same collateral-deletion risk.' }
        ]
      },
      automation: {
        titleKey: 'control_automation_title', title: 'Automation',
        icon: 'radar',
        descKey: 'control_automation_desc', desc: 'Background automation for keystore backend targeting.',
        toggles: [
          { key: 'toggle_auto_target', icon: 'radar', def: '1', titleKey: 'control_toggle_auto_target', title: 'Auto Target New Apps', descKey: 'control_toggle_auto_target_desc', desc: 'Automatically detect newly installed apps and add them to target.txt' },
          { key: 'toggle_target_system', icon: 'apps', def: '0', titleKey: 'control_toggle_target_system', title: 'Include System Apps', descKey: 'control_toggle_target_system_desc', desc: 'Also scan and auto-target pre-installed system apps, not just user-installed ones' },
          { key: 'toggle_teesim_sync', icon: 'sync', def: '0', titleKey: 'control_toggle_teesim_sync', title: 'Sync TEESimulator Config', descKey: 'control_toggle_teesim_sync_desc', desc: 'If TEESimulator is installed, keep its device identity, security patch, and target list in sync with Jerry' }
        ]
      },
      adb: {
        titleKey: 'control_adb_title', title: 'ADB & Debug Disabler',
        icon: 'usb_off',
        descKey: 'control_adb_desc', desc: 'Master switch plus fine-grained control over what gets hidden at boot.',
        masterKey: 'toggle_adb_disabler',
        toggles: [
          { key: 'toggle_adb_disabler',             icon: 'usb_off',        def: '0', titleKey: 'control_toggle_adb_disabler', title: 'Disable ADB & Debugging',    descKey: 'control_toggle_adb_disabler_desc', desc: 'Master switch for hiding USB debugging, developer options, and OEM unlock' },
          { key: 'toggle_adb_disabler_dev_options', icon: 'developer_mode', def: '0', titleKey: 'control_toggle_adb_disabler_dev_options', title: 'Hide Developer Options',     descKey: 'control_toggle_adb_disabler_dev_options_desc', desc: 'Disable development_settings_enabled at boot' },
          { key: 'toggle_adb_disabler_usb_debug',   icon: 'usb',            def: '0', titleKey: 'control_toggle_adb_disabler_usb_debug', title: 'Hide USB Debugging',         descKey: 'control_toggle_adb_disabler_usb_debug_desc', desc: 'Reset ro.debuggable, adb.secure and related debug props at boot' },
          { key: 'toggle_adb_disabler_oem_unlock',  icon: 'lock_person',    def: '0', titleKey: 'control_toggle_adb_disabler_oem_unlock', title: 'Hide OEM Unlock Support',    descKey: 'control_toggle_adb_disabler_oem_unlock_desc', desc: 'Report OEM unlock as unsupported at boot' }
        ]
      },
      action: {
        titleKey: 'control_action_title', title: 'Action Pipeline',
        icon: 'list_alt',
        descKey: 'control_action_desc', desc: 'Steps run automatically at boot after the core module init.',
        toggles: [
          { key: 'toggle_action_gms',            icon: 'block',                 def: '1', titleKey: 'control_toggle_action_gms', title: 'Kill Play Store',        descKey: 'control_toggle_action_gms_desc', desc: 'Force-stop and clear Play Store, GMS, and DroidGuard processes' },
          { key: 'toggle_action_gms_force_stop',  icon: 'stop_circle',           def: '1', titleKey: 'control_toggle_action_gms_force_stop', title: 'Force-Stop GMS Apps',    descKey: 'control_toggle_action_gms_force_stop_desc', desc: 'Kill DroidGuard, GMS, and Play Store processes; clear Play Store cache' },
          { key: 'toggle_action_gms_clear_data',  icon: 'delete_sweep',          def: '0', titleKey: 'control_toggle_action_gms_clear_data', title: 'Clear Play Store Data',  descKey: 'control_toggle_action_gms_clear_data_desc', desc: 'Full data wipe of Play Store — signs you out, more aggressive than cache clear. Off by default.' },
          { key: 'toggle_action_target',         icon: 'list_alt',              def: '1', titleKey: 'control_toggle_action_target', title: 'Regenerate Target',      descKey: 'control_toggle_action_target_desc', desc: 'Regenerate the app target list for the active keystore backend' },
          { key: 'toggle_action_security_patch', icon: 'security_update_good',  def: '1', titleKey: 'control_toggle_action_security_patch', title: 'Set Security Patch',     descKey: 'control_toggle_action_security_patch_desc', desc: 'Write spoofed security patch date to the active keystore backend' },
          { key: 'toggle_action_boot_hash',       icon: 'verified',              def: '1', titleKey: 'control_toggle_action_boot_hash', title: 'Set Verified Boot Hash', descKey: 'control_toggle_action_boot_hash_desc', desc: 'Read and write verified boot hash for attestation' },
          { key: 'toggle_action_pif',             icon: 'fingerprint',           def: '1', titleKey: 'control_toggle_action_pif', title: 'Set Fingerprint (PIF)',  descKey: 'control_toggle_action_pif_desc', desc: 'Run Play Integrity Fix auto-update scripts' }
        ]
      }
    };

    function tr(key, fallback) {
      try {
        if (typeof window.__jerryGetTranslation === 'function') {
          var v = window.__jerryGetTranslation(key);
          if (v) return v;
        }
      } catch (e) {}
      return fallback;
    }

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
        var titleText = tr(t.titleKey, t.title);
        var descText = tr(t.descKey, t.desc);
        return '<div class="ctrl-row' + (t.detail ? ' ctrl-row--detail' : '') + '" data-key="' + t.key + '">' +
          '<md-icon>' + t.icon + '</md-icon>' +
          '<div class="ctrl-row-content">' +
            '<div class="ctrl-row-title">' + titleText + '</div>' +
            '<span class="ctrl-row-desc">' + descText + '</span>' +
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
      var detailTitleText = tr(detail.titleKey, detail.title);
      var detailDescText = detail.desc ? tr(detail.descKey, detail.desc) : '';
      var masterTitleText = tr(toggleDef.titleKey, toggleDef.title);
      dialog.innerHTML =
        '<div slot="headline">' + detailTitleText + '</div>' +
        '<div slot="content">' +
          (detailDescText ? '<p class="ctrl-dialog-desc">' + detailDescText + '</p>' : '') +
          '<div class="ctrl-dialog-row ctrl-dialog-row--master" id="ctrl-detail-master-row">' +
            '<div class="ctrl-dialog-row-text">' +
              '<div class="ctrl-dialog-row-title">' + masterTitleText + '</div>' +
            '</div>' +
            '<md-switch icons id="ctrl-detail-master-switch"></md-switch>' +
          '</div>' +
          detail.items.map(function(item) {
            var itemTitleText = tr(item.titleKey, item.title);
            var itemDescText = tr(item.descKey, item.desc);
            return '<div class="ctrl-dialog-row" data-key="' + item.key + '">' +
              '<div class="ctrl-dialog-row-text">' +
                '<div class="ctrl-dialog-row-title">' + itemTitleText + '</div>' +
                '<div class="ctrl-dialog-row-desc">' + itemDescText + '</div>' +
              '</div>' +
              '<md-switch icons class="ctrl-dialog-row-switch" data-key="' + item.key + '"></md-switch>' +
            '</div>';
          }).join('') +
        '</div>' +
        '<div slot="actions">' +
          '<md-text-button id="ctrl-detail-close">' + tr('dialog_close', 'Close') + '</md-text-button>' +
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
    document.addEventListener('languageChanged', initRows);

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
