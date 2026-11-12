import { getConfig, migrateLegacyConfig, prefetchConfig, setConfig, setModuleDir } from './config.js';
import { getTranslation, initI18n } from './i18n.js';
import { startNetworkMonitor } from './network.js';
import { loadInitialInfo, refreshDeviceInfo, refreshKeyboxInfo, startLiveDeviceInfo } from './device-info.js';
import { addHistoryEntry, readHistory, clearHistory } from './history.js';
import { showToast } from './toast.js';
import { escapeHtml } from './utils.js';
import { spawnScript, getModuleDir, initBridge, runScript, exec } from './bridge.js';

// Shared with the hand-written scripts in src/ui (pif-status.js, app-targeting.js),
// which do not import from main.js. Replaces the old dynamic import of bridge-*.js.
window.JerryBridge = { initBridge, runScript, exec, spawnScript, getModuleDir };

var friendlyNames = {};
document.addEventListener(`DOMContentLoaded`, async () => {
    try {
        await initBridge();
        setModuleDir(getModuleDir());
        prefetchConfig();
        // Migration uses the shell: run it after startup.
        setTimeout(() => migrateLegacyConfig(), 5000);
    }
    catch (e) {
        console.warn(`Bridge init failed, running without module path:`, e);
    }
    // Public names used by the hand-written scripts in src/ui (module-configs.js etc.)
    window.ka = getConfig;
    window.Aa = setConfig;
    setupTopBarScroll();
    setupNavigation();
    setupActionItems();
    setupExtras();
    setupRefreshButton();
    // Device info first: it only needs fetch() of the json files already on disk, so it must not wait for the language/config shell reads.
    startNetworkMonitor();
    loadInitialInfo();
    startLiveDeviceInfo();
    collectFriendlyNames();
    await initI18n();
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
// Pick the one line that says what went wrong: last error-looking line, else the last line.
// Drops the log timestamp, [TAG] and "Error:" prefix so the toast reads like "Failed: <reason>"
function errorSummary(chunks, fallback) {
    let lines = chunks.join(`\n`).split(/\r?\n/).map(l => l.replace(/^\[!\]\s*/, ``).trim()).filter(Boolean);
    let hit = [...lines].reverse().find(l => /\b(error|failed|invalid|not found|cannot|unable|denied)\b/i.test(l)) || lines[lines.length - 1];
    if (!hit) return fallback;
    hit = hit.replace(/^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}\s*/, ``).replace(/^\[[^\]]*\]\s*/, ``).replace(/^(error|failed)\s*:\s*/i, ``).trim();
    return hit.length > 140 ? hit.slice(0, 137) + `...` : (hit || fallback);
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
`), t), c.close(), t !== 0) {
            let e = errorSummary(s, o);
            showToast(`${i(`simple_toast_error`) || `Failed`}: ${escapeHtml(e)}`, {
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
            showToast((i(`toast_success`) || `Done`).replace(/\s*✓\s*$/, ``), {
                autoCloseDelay: 3e3, className: `snackbar-success`
            });
    });
    d.on(`error`, t => {
        let n = t.message || `Unknown error`;
        addHistoryEntry(e, n, 1);
        c.close();
        showToast(`${i(`simple_toast_error`) || `Failed`}: ${escapeHtml(n)}`, {
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
    // No button: tapping the right half of the Keybox Status card opens History
    let card = document.getElementById(`keybox-card`);
    card && card.addEventListener(`click`, e => {
        let r = card.getBoundingClientRect();
        if (e.clientX >= r.left + r.width / 2)
            openHistoryDialog();
    });
}
function historyTime(iso) {
    let d = new Date(iso);
    return isNaN(d) ? `` : d.toLocaleString([], { month: `short`, day: `numeric`, hour: `2-digit`, minute: `2-digit` });
}
function historyRows() {
    let i = getTranslation;
    let items = readHistory();
    if (!items.length)
        return `<p class="history-empty">${escapeHtml(i(`history_empty`) || `No activity yet — run an action to get started`)}</p>`;
    return items.map(h => {
        let key = friendlyNames[h.script];
        let name = (key && i(key)) || h.script;
        let mark = h.code === null || h.code === undefined ? `` : (h.code === 0 ? `<md-icon class="history-ok">check_circle</md-icon>` : `<md-icon class="history-fail">error</md-icon>`);
        return `<details class="history-item"><summary>${mark}<span class="history-name">${escapeHtml(name)}</span><span class="history-time">${escapeHtml(historyTime(h.time))}</span></summary><div class="terminal"><pre>${escapeHtml(h.output)}</pre></div></details>`;
    }).join(``);
}
function openHistoryDialog() {
    let i = getTranslation;
    let d = document.createElement(`md-dialog`);
    d.className = `history-dialog`;
    d.innerHTML = `
    <div slot="headline">${escapeHtml(i(`history_title`) || `Recent Activity`)}</div>
    <div slot="content" class="history-list">${historyRows()}</div>
    <div slot="actions">
      <md-text-button class="history-clear">${escapeHtml(i(`history_clear`) || `Clear`)}</md-text-button>
      <md-text-button class="dialog-close">${escapeHtml(i(`dialog_close`) || `Close`)}</md-text-button>
    </div>
  `;
    document.body.appendChild(d);
    d.querySelector(`.dialog-close`).addEventListener(`click`, () => d.close());
    d.querySelector(`.history-clear`).addEventListener(`click`, () => {
        clearHistory();
        d.querySelector(`.history-list`).innerHTML = historyRows();
    });
    d.addEventListener(`close`, () => d.remove());
    d.show();
}
