import { getConfig, migrateLegacyConfig, setConfig, setModuleDir } from './config.js';
import { getTranslation, initI18n } from './i18n.js';
import { startNetworkMonitor } from './network.js';
import { loadInitialInfo, refreshDeviceInfo, refreshKeyboxInfo } from './device-info.js';
import { addHistoryEntry } from './history.js';
import { showToast } from './toast.js';
import { escapeHtml } from './utils.js';
import { spawnScript, getModuleDir, initBridge, runScript, exec } from './bridge.js';

// Shared with the hand-written scripts in public/assets (pif-status.js, app-targeting.js),
// which cannot import from the bundle. Replaces the old dynamic import of bridge-*.js.
window.JerryBridge = { initBridge, runScript, exec, spawnScript, getModuleDir };

var friendlyNames = {};
document.addEventListener(`DOMContentLoaded`, async () => {
    try {
        await initBridge();
        setModuleDir(getModuleDir());
        await migrateLegacyConfig();
    }
    catch (e) {
        console.warn(`Bridge init failed, running without module path:`, e);
    }
    // Public names used by the hand-written scripts in public/assets (module-configs.js etc.)
    window.ka = getConfig;
    window.Aa = setConfig;
    setupTopBarScroll();
    setupNavigation();
    setupActionItems();
    setupExtras();
    setupRefreshButton();
    await initI18n();
    startNetworkMonitor();
    loadInitialInfo();
    collectFriendlyNames();
});
function setupTopBarScroll() {
    let e = document.getElementById(`top-bar`);
    let t = document.querySelector(`main`);
    !e || !t || t.addEventListener(`scroll`, () => {
        e.classList.toggle(`top-bar--scrolled`, t.scrollTop > 0);
    });
}
function setupNavigation() {
    let e = document.getElementById(`nav-bar`);
    let t = [document.getElementById(`home-page`), document.getElementById(`actions-page`), document.getElementById(`advanced-page`), document.getElementById(`settings-page`)];
    e.addEventListener(`navigation-bar-activated`, e => {
        let n = e.detail.activeIndex;
        t.forEach((e, t) => {
            e.hidden = t !== n;
        });
        window.scrollTo({
            top: 0, behavior: `instant`
        });
        let b = document.getElementById(`refresh-btn`);
        n === 0 && b && !b.disabled && b.click();
    });
}
function collectFriendlyNames() {
    document.querySelectorAll(`.list-item[data-script]`).forEach(e => {
        let t = e.dataset.script;
        let n = e.querySelector(`.toggle-text[data-i18n]`);
        n && (friendlyNames[t] = n.dataset.i18n);
    });
    window.__friendlyNames = friendlyNames;
}
function friendlyNameFor(script) {
    return friendlyNames[script] || script;
}
function setupActionItems() {
    document.querySelectorAll(`.list-item[data-script]`).forEach(e => {
        e.addEventListener(`click`, async () => {
            if (e.disabled)
                return;
            let t = e.dataset.script;
            let n = e.querySelector(`.action-spinner`);
            e.disabled = true;
            n?.classList.remove(`hidden`);
            try {
                await runAction(t, e, n);
            }
            catch (e) {
                console.warn(`Action error:`, e);
            }
            finally {
                e.disabled = false;
                n?.classList.add(`hidden`);
            }
        });
    });
}
async function runAction(e, n, r) {
    let i = getTranslation;
    let a = friendlyNameFor(e);
    let o = i(a) || a;
    let s = [];
    let c = document.getElementById(`progress-dialog`);
    let l = document.getElementById(`progress-label`);
    let u = document.getElementById(`progress-text`);
    l && (l.textContent = o);
    u && (u.textContent = i(`simple_dialog_wait`) || `This may take a moment`);
    c.show();
    let d = spawnScript(e, `feature`);
    d.stdout.on(`data`, e => {
        s.push(e);
    });
    d.stderr.on(`data`, e => {
        s.push(`[!] ` + e);
    });
    d.on(`exit`, t => {
        if (addHistoryEntry(e, s.join(`
`)), c.close(), t !== 0) {
            let e = s.find(e => e.includes(`Error`)) || s[s.length - 1] || o;
            showToast(`${i(`simple_toast_error`) || `Failed`}: ${e}`, {
                action: i(`simple_toast_view_details`) || `View Details`, autoCloseDelay: 8e3, className: `snackbar-error`, onActionClick: () => {
                    let e = document.createElement(`md-dialog`);
                    e.innerHTML = `
            <div slot="headline">${i(`error_dialog_title`) || `Error Details`}</div>
            <div slot="content"><div class="terminal"><pre>${escapeHtml(s.join(`
`))}</pre></div></div>
            <div slot="actions">
              <md-text-button class="dialog-close">${i(`dialog_close`) || `Close`}</md-text-button>
            </div>
          `;
                    document.body.appendChild(e);
                    e.querySelector(`.dialog-close`).addEventListener(`click`, () => e.close());
                    e.addEventListener(`close`, () => document.body.removeChild(e));
                    e.show();
                }
            });
        }
        else
            showToast(i(`toast_success`) || `Done ✓`, {
                autoCloseDelay: 3e3, className: `snackbar-success`
            });
    });
    d.on(`error`, t => {
        let n = t.message || `Unknown error`;
        addHistoryEntry(e, n);
        c.close();
        showToast(`${i(`simple_toast_error`) || `Failed`}: ${o}`, {
            action: i(`simple_toast_view_details`) || `View Details`, autoCloseDelay: 8e3, className: `snackbar-error`, onActionClick: () => {
                let e = document.createElement(`md-dialog`);
                e.innerHTML = `
          <div slot="headline">${i(`error_dialog_title`) || `Error Details`}</div>
          <div slot="content"><div class="terminal"><pre>${escapeHtml(n)}</pre></div></div>
          <div slot="actions">
            <md-text-button class="dialog-close">${i(`dialog_close`) || `Close`}</md-text-button>
          </div>
        `;
                document.body.appendChild(e);
                e.querySelector(`.dialog-close`).addEventListener(`click`, () => e.close());
                e.addEventListener(`close`, () => document.body.removeChild(e));
                e.show();
            }
        });
    });
}
function setupRefreshButton() {
    let e = document.getElementById(`refresh-btn`);
    e && e.addEventListener(`click`, async () => {
        e.disabled = true;
        await Promise.all([refreshDeviceInfo(), refreshKeyboxInfo()]);
        e.disabled = false;
    });
}
function setupExtras() {
}
