  (function() {

    function escHtml(s) {
      return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
    }

    function sh(cmd) {
      try {
        if (window.ksu && window.ksu.exec) return window.ksu.exec(cmd);
        return { code: -1, stdout: '', stderr: 'no exec' };
      } catch(e) { return { code: -1, stdout: '', stderr: e.message }; }
    }

    window.shAsync = function shAsync(cmd) {
      return new Promise(function(resolve) {
        try {

          var cb = 'cb_sh_' + Date.now() + '_' + Math.random().toString(36).slice(2);
          window[cb] = function(code, stdout, stderr) {
            delete window[cb];
            if (typeof code === 'number') {
              resolve({ code: code, stdout: stdout || '', stderr: stderr || '' });
            } else {

              try {
                var obj = JSON.parse(code);
                resolve({ code: 0, stdout: obj.result || obj.stdout || obj.output || '', stderr: '' });
              } catch(_) {
                resolve({ code: 0, stdout: code || '', stderr: '' });
              }
            }
          };
          if (window.ksu && typeof window.ksu.exec === 'function') {
            window.ksu.exec(cmd, '{}', cb);
          } else {
            delete window[cb];
            resolve({ code: -1, stdout: '', stderr: 'no bridge' });
          }
        } catch(e) {
          resolve({ code: -1, stdout: '', stderr: e.message });
        }
      });
    }

    function openFileBrowser(callback) {
      var currentPath = '/sdcard';
      var selectedPath = null;
      var showAll = false;
      var entries = [];

      var fbDialog = document.createElement('md-dialog');
      fbDialog.className = 'fb-dialog';

      function buildRow(path, icon, name, isFolder, isSelected) {
        var cls = 'fb-row' + (isFolder ? '' : ' fb-row--file') + (isSelected ? ' fb-row--selected' : '');
        return '<div class="' + cls + '" data-path="' + escHtml(path) + '">' +
          '<span class="fb-row-icon' + (isFolder ? ' fb-row-icon--folder' : ' fb-row-icon--file') + '">' +
          '<md-icon class="fb-row-icon-inner">' + icon + '</md-icon></span>' +
          '<span class="fb-row-name">' + escHtml(name) + '</span>' +
          (isFolder ? '<md-icon class="fb-chevron">chevron_right</md-icon>' : '') +
          '</div>';
      }

      function renderBrowser() {
        var folders = entries.filter(function(e) { return e.isFolder; });
        var files = entries.filter(function(e) {
          return !e.isFolder && (showAll || e.name.endsWith('.xml') || e.name.endsWith('.bak'));
        });

        fbDialog.innerHTML =
          '<div slot="headline" class="fb-headline">' +
            (currentPath !== '/sdcard' ? '<md-icon-button id="fb-back"><md-icon>arrow_back</md-icon></md-icon-button>' : '') +
            '<span class="fb-path">' + escHtml(currentPath) + '</span>' +
          '</div>' +
          '<div slot="content" class="fb-content">' +
            (currentPath !== '/' && currentPath !== '/sdcard' ? buildRow('..', 'folder_open', '..', true, false) : '') +
            folders.map(function(e) { return buildRow(e.path, 'folder', e.name, true, false); }).join('') +
            (files.length === 0 && folders.length === 0 ? '<div class="fb-empty">No XML files found</div>' : files.length === 0 ? '<div class="fb-empty" style="font-size:0.8rem;padding:16px">No XML files here — open a subfolder or tap Show all files</div>' : '') +
            files.map(function(e) { return buildRow(e.path, 'description', e.name, false, selectedPath === e.path); }).join('') +
            (!showAll && files.length < entries.filter(function(e){return !e.isFolder;}).length ?
              '<div class="fb-show-all"><span id="fb-show-all-btn">Show all files</span></div>' : '') +
          '</div>' +
          '<div slot="actions" class="fb-actions">' +
            '<md-text-button id="fb-cancel">Close</md-text-button>' +
            '<div style="flex:1"></div>' +
            '<md-filled-button id="fb-select"' + (selectedPath ? '' : ' disabled') + '>Select</md-filled-button>' +
          '</div>';

        var backBtn = fbDialog.querySelector('#fb-back');
        if (backBtn) backBtn.addEventListener('click', function() {
          var parent = currentPath.substring(0, currentPath.lastIndexOf('/')) || '/';
          currentPath = parent || '/sdcard';
          loadDir(currentPath);
        });

        var showAllBtn = fbDialog.querySelector('#fb-show-all-btn');
        if (showAllBtn) showAllBtn.addEventListener('click', function() { showAll = true; renderBrowser(); });

        fbDialog.querySelectorAll('.fb-row').forEach(function(row) {
          row.addEventListener('click', function() {
            var path = row.getAttribute('data-path');
            if (!path) return;
            if (path === '..') {
              var parent = currentPath.substring(0, currentPath.lastIndexOf('/')) || '/sdcard';
              currentPath = parent;
              loadDir(currentPath);
              return;
            }
            var entry = entries.find(function(e) { return e.path === path; });
            if (entry && entry.isFolder) {
              currentPath = path;
              loadDir(currentPath);
            } else {
              selectedPath = path;
              renderBrowser();
            }
          });
        });

        fbDialog.querySelector('#fb-cancel').addEventListener('click', function() { fbDialog.close(); });
        fbDialog.querySelector('#fb-select').addEventListener('click', function() {
          if (selectedPath) { callback(selectedPath); fbDialog.close(); }
        });

        if (!document.body.contains(fbDialog)) {
          document.body.appendChild(fbDialog);
          fbDialog.addEventListener('close', function() {
            if (document.body.contains(fbDialog)) document.body.removeChild(fbDialog);
          });
          fbDialog.show();
        }
      }

      function loadDir(path) {
        fbDialog.innerHTML =
          '<div slot="headline" class="fb-headline"><span class="fb-path">' + escHtml(path) + '</span></div>' +
          '<div slot="content" class="fb-loading"><md-circular-progress indeterminate></md-circular-progress></div>';

        if (!document.body.contains(fbDialog)) {
          document.body.appendChild(fbDialog);
          fbDialog.addEventListener('close', function() {
            if (document.body.contains(fbDialog)) document.body.removeChild(fbDialog);
          });
          fbDialog.show();
        }

        shAsync('ls -1p ' + path + ' 2>/dev/null | head -200').then(function(result) {
          var lines = (result.stdout || '').split('\n').filter(Boolean);
          entries = lines.map(function(line) {
            var isFolder = line.endsWith('/');
            var name = line.replace(/\/$/, '');
            return { name: name, isFolder: isFolder, path: path + '/' + name };
          }).filter(function(e) { return e.name !== '.' && e.name !== '..'; });
          selectedPath = null;
          showAll = false;
          renderBrowser();
        }).catch(function() {
          entries = [];
          renderBrowser();
        });
      }

      loadDir(currentPath);
    }

    function openCustomKeyboxDialog() {
      var modDir = '/data/adb/modules/Jerrykey';
      try { var _mp = JSON.parse(window.__jerry_module_paths||'{}'); if(_mp&&_mp.MODDIR) modDir=_mp.MODDIR; } catch(_){}
      if (window.__jerry_moddir) modDir = window.__jerry_moddir;
      var selectedFilePath = '';

      var dialog = document.createElement('md-dialog');

      var _isDark = document.documentElement.getAttribute('data-theme-resolved') === 'dark'
        || document.documentElement.getAttribute('data-theme') === 'dark';
      dialog.style.setProperty('--md-dialog-container-color', _isDark ? '#1E1E1E' : '#ffffff');
      dialog.style.setProperty('--md-dialog-headline-color', _isDark ? '#F5F5F5' : '#252525');
      dialog.style.setProperty('--md-dialog-supporting-text-color', _isDark ? '#A0A0A0' : '#444444');

      dialog.innerHTML =
        '<div slot="headline" style="padding:20px 24px 4px;font-size:1.1rem;font-weight:600;color:' + (_isDark ? '#F5F5F5' : '#252525') + '">Custom Keybox</div>' +
        '<div slot="content" style="padding:4px 24px">' +

        '<div style="background:' + (_isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)') + ';border-radius:14px;padding:14px;margin-bottom:8px">' +
          '<div style="display:flex;align-items:center;gap:8px;margin-bottom:6px">' +
            '<md-icon style="font-size:22px">upload_file</md-icon>' +
            '<span style="font-size:0.9rem;font-weight:500">Import File</span>' +
          '</div>' +
          '<p style="margin:0 0 10px;font-size:0.75rem;opacity:0.65">Select a keybox XML file from your device</p>' +
          '<div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">' +
            '<div id="kb-file-chip" style="font-size:0.75rem;opacity:0.55;padding:6px 12px;border:1px solid rgba(128,128,128,0.3);border-radius:20px;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">No file selected</div>' +
            '<md-filled-tonal-button id="kb-file-btn">Browse Files</md-filled-tonal-button>' +
          '</div>' +
        '</div>' +

        '<div style="background:' + (_isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)') + ';border-radius:14px;padding:14px">' +
          '<div style="display:flex;align-items:center;gap:8px;margin-bottom:6px">' +
            '<md-icon style="font-size:22px">link</md-icon>' +
            '<span style="font-size:0.9rem;font-weight:500">URL or Path</span>' +
          '</div>' +
          '<p style="margin:0 0 10px;font-size:0.75rem;opacity:0.65">Paste a download URL or enter a device path</p>' +
          '<md-outlined-text-field id="kb-url-input" style="width:100%;border-radius:14px" placeholder="https://example.com/keybox.xml or /sdcard/keybox.xml">' +
            '<md-icon-button slot="trailing-icon" id="kb-paste-btn"><md-icon>content_paste</md-icon></md-icon-button>' +
          '</md-outlined-text-field>' +
        '</div>' +

        '</div>' +
        '<div slot="actions" style="padding:4px 24px 20px;display:flex;align-items:center">' +
          '<md-text-button id="kb-clear-btn" style="--md-text-button-label-text-color:' + (_isDark ? '#cf6679' : '#b00020') + '"><md-icon slot="icon">delete</md-icon>Clear</md-text-button>' +
          '<div style="flex:1"></div>' +
          '<md-text-button id="kb-cancel-btn" style="--md-text-button-label-text-color:' + (_isDark ? '#b39ddb' : '#4a148c') + '">Cancel</md-text-button>' +
          '<md-filled-tonal-button id="kb-apply-btn">Apply & Install</md-filled-tonal-button>' +
        '</div>';

      document.body.appendChild(dialog);

      var fileChip = dialog.querySelector('#kb-file-chip');
      var urlInput = dialog.querySelector('#kb-url-input');
      var fileBtn = dialog.querySelector('#kb-file-btn');
      var pasteBtn = dialog.querySelector('#kb-paste-btn');
      var clearBtn = dialog.querySelector('#kb-clear-btn');
      var cancelBtn = dialog.querySelector('#kb-cancel-btn');
      var applyBtn = dialog.querySelector('#kb-apply-btn');

      fileBtn.addEventListener('click', function() {
        openFileBrowser(function(path) {
          selectedFilePath = path;
          fileChip.textContent = path.split('/').pop();
          fileChip.style.opacity = '1';
          urlInput.value = '';
        });
      });

      pasteBtn.addEventListener('click', function() {
        navigator.clipboard && navigator.clipboard.readText().then(function(text) {
          urlInput.value = text.trim();
          selectedFilePath = '';
          fileChip.textContent = 'No file selected';
          fileChip.style.opacity = '0.55';
        }).catch(function() {});
      });

      clearBtn.addEventListener('click', function() {
        var clearCmd = [
          'MODDIR="' + modDir + '"',
          '. "' + modDir + '/lib/paths.sh"',
          '. "' + modDir + '/lib/config_env.sh"',
          'cfg_delete kb_custom_type',
          'cfg_delete kb_custom_value'
        ].join(' && ');
        shAsync(clearCmd);
        selectedFilePath = '';
        urlInput.value = '';
        fileChip.textContent = 'No file selected';
        fileChip.style.opacity = '0.55';
        dialog.close();
        if (document.body.contains(dialog)) document.body.removeChild(dialog);
      });

      cancelBtn.addEventListener('click', function() {
        dialog.close();
        if (document.body.contains(dialog)) document.body.removeChild(dialog);
      });

      applyBtn.addEventListener('click', function() {
        var value = selectedFilePath || (urlInput.value ? urlInput.value.trim() : '');
        if (!value) { alert('Please select a file or enter a URL/path'); return; }
        var type = selectedFilePath ? 'path' : (value.startsWith('http') ? 'url' : 'path');
        var safeValue = value.replace(/'/g, "'\\''");

        applyBtn.disabled = true;
        applyBtn.textContent = 'Installing...';

        var saveCmd = [
          'MODDIR="' + modDir + '"',
          '. "' + modDir + '/lib/paths.sh"',
          '. "' + modDir + '/lib/config_env.sh"',
          'cfg_set kb_custom_type "' + type + '"',
          'cfg_set kb_custom_value \'' + safeValue + '\'',
          'sh \'' + modDir + '/features/keybox.sh\''
        ].join(' && ');

        dialog.close();
        if (document.body.contains(dialog)) document.body.removeChild(dialog);

        shAsync(saveCmd)
          .then(function(result) {
            if (result && result.code === 0) {
              alert('\u2705 Custom keybox installed successfully!');
            } else {
              var msg = result ? (result.stderr || result.stdout || 'code=' + result.code) : 'no result';
              alert('\u274c Install failed: ' + msg);
            }
          })
          .catch(function(e) {
            alert('\u274c Error: ' + (e && e.message ? e.message : String(e)));
          })
          .finally(function() {
            applyBtn.disabled = false;
            applyBtn.textContent = 'Apply & Install';
          });
      });

      dialog.addEventListener('close', function() {
        if (document.body.contains(dialog)) document.body.removeChild(dialog);
      });

      dialog.show();
    }

    var fbStyle = document.createElement('style');
    fbStyle.textContent = [
      '.fb-dialog { --md-dialog-container-max-height: 80vh; }',
      '.fb-headline { display:flex; align-items:center; gap:8px; padding:16px 24px 8px; }',
      '.fb-path { font-size:0.85rem; opacity:0.7; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }',
      '.fb-content { padding:0; min-height:200px; }',
      '.fb-loading { display:flex; justify-content:center; align-items:center; padding:40px; }',
      '.fb-row { display:flex; align-items:center; gap:12px; padding:12px 16px; cursor:pointer; border-radius:8px; margin:2px 8px; transition:background 0s; }',
      '.fb-row:hover, .fb-row--selected { background:rgba(255,255,255,0.08); }',
      '.fb-row--selected { background:rgba(124,58,237,0.15) !important; }',
      '.fb-row-icon { width:36px; height:36px; border-radius:10px; display:flex; align-items:center; justify-content:center; }',
      '.fb-row-icon--folder { background:rgba(59,130,246,0.2); color:#3B82F6; }',
      '.fb-row-icon--file { background:rgba(124,58,237,0.15); color:#A78BFA; }',
      '.fb-row-name { flex:1; font-size:0.9rem; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }',
      '.fb-chevron { opacity:0.4; font-size:18px !important; }',
      '.fb-empty { padding:32px; text-align:center; opacity:0.5; font-size:0.85rem; }',
      '.fb-show-all { padding:8px 16px; text-align:center; }',
      '#fb-show-all-btn { font-size:0.8rem; color:var(--md-sys-color-primary,#A78BFA); cursor:pointer; }',
      '.fb-actions { display:flex; align-items:center; padding:8px 16px; }',
    ].join('\n');
    document.head.appendChild(fbStyle);

    document.addEventListener('DOMContentLoaded', function() {
      var btn = document.getElementById('custom-keybox-btn');
      if (btn) {
        btn.addEventListener('click', openCustomKeyboxDialog);
        btn.addEventListener('touchstart', function(e) {
          e.preventDefault();
          openCustomKeyboxDialog();
        }, { passive: false });
      }
    });

  })();
