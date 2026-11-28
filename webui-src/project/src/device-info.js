import { spawnScript } from './bridge.js';

var INFO_JSON = `/json/info.json`;
var KEYBOX_INFO_JSON = `/json/keybox_info.json`;
export async function loadInitialInfo() {
    // Startup: json fetch only. Scripts run later via spawn, so they cannot block the page.
    await showCachedDeviceInfo();
    applyVersionInfo();
    loadKeyboxCard();
    setTimeout(() => { refreshDeviceInfo(); refreshKeyboxInfo(); }, 2500);
}
var LIVE_INTERVAL_MS = 120e3;
var lastLiveRun = 0;
export function startLiveDeviceInfo() {
    let busy = false;
    let tick = async () => {
        if (busy || document.hidden || Date.now() - lastLiveRun < 60e3)
            return;
        busy = true;
        lastLiveRun = Date.now();
        try {
            await refreshDeviceInfo();
            await refreshKeyboxInfo();
        }
        finally {
            busy = false;
        }
    };
    setInterval(tick, LIVE_INTERVAL_MS);
    document.addEventListener(`visibilitychange`, tick);
}
export async function refreshDeviceInfo() {
    await new Promise(resolve => {
        let done = () => resolve();
        let p = spawnScript(`device-info.sh`, `common`);
        p.on(`exit`, done);
        p.on(`error`, done);
    });
    await pollDeviceInfo();
}
export async function refreshKeyboxInfo() {
    let _priorGenTs = null;
    try {
        _priorGenTs = (await fetchKeyboxInfo()).generated_at || null;
    }
    catch {
    }
    spawnScript(`keybox_info.sh`, `feature`);
    await waitForKeyboxInfo(_priorGenTs);
    await loadKeyboxCard();
}
async function fetchDeviceInfo() {
    let e = await (await fetch(`${INFO_JSON}?ts=${Date.now()}`)).json();
    if (e.android || e.kernel || e.root)
        return e;
    throw Error(`empty`);
}
async function showCachedDeviceInfo() {
    try {
        applyDeviceInfo(await fetchDeviceInfo());
    }
    catch {
    }
}
async function pollDeviceInfo(timeoutMs = 6e3, intervalMs = 400) {
    let startedAt = Date.now();
    for (; Date.now() - startedAt < timeoutMs;) {
        try {
            applyDeviceInfo(await fetchDeviceInfo());
            return;
        }
        catch {
        }
        await new Promise(e => setTimeout(e, intervalMs));
    }
}
function applyDeviceInfo(info) {
    setTextById(`android-value`, info.android || `—`);
    setTextById(`root-value`, info.root || `—`);
    setTextById(`rom-value`, info.rom || `—`);
    // Module version is re-read from module.prop (via device-info.sh) on every refresh, not only at startup.
    info.version && setTextById(`version-info-value`, info.version);
    let backendEl = document.getElementById(`keystore-backend-value`);
    backendEl && info.keystore_backend && (backendEl.textContent = info.keystore_backend);
}
async function applyVersionInfo() {
    try {
        let e = await (await fetch(`${INFO_JSON}?ts=${Date.now()}`)).json();
        e.version && setTextById(`version-info-value`, e.version);
    }
    catch {
    }
}
async function fetchKeyboxInfo() {
    return await (await fetch(`${KEYBOX_INFO_JSON}?ts=${Date.now()}`)).json();
}
async function waitForKeyboxInfo(_priorGenTs = null, timeoutMs = 6e3, intervalMs = 300) {
    let startedAt = Date.now();
    for (; Date.now() - startedAt < timeoutMs;) {
        try {
            let info = await fetchKeyboxInfo();
            if (`installed` in info && info.generated_at && info.generated_at !== _priorGenTs)
                return;
        }
        catch {
        }
        await new Promise(e => setTimeout(e, intervalMs));
    }
}
var lastKeyboxInfo = null;
setInterval(() => {
    if (lastKeyboxInfo && !document.hidden)
        renderKeyboxCard(lastKeyboxInfo);
}, 30e3);
async function loadKeyboxCard() {
    try {
        lastKeyboxInfo = await fetchKeyboxInfo();
        renderKeyboxCard(lastKeyboxInfo);
    }
    catch {
    }
}
function kbT(key, fallback) {
    return window.__jerryGetTranslation && window.__jerryGetTranslation(key) || fallback;
}
document.addEventListener(`languageChanged`, () => { lastKeyboxInfo && renderKeyboxCard(lastKeyboxInfo); });
function renderKeyboxCard(info) {
    lastKeyboxInfo = info;
    let card = document.getElementById(`keybox-card`);
    let icon = document.getElementById(`keybox-icon`);
    let valueEl = document.getElementById(`keybox-value`);
    let numEl = document.getElementById(`keybox-num`);
    let backendEl = document.getElementById(`keystore-backend-value`);
    if (valueEl && !numEl) {
        numEl = document.createElement(`span`);
        numEl.id = `keybox-num`;
        valueEl.appendChild(numEl);
    }
    if (backendEl)
        backendEl.textContent = info.backend || `—`;
    let setLabel = (v, num) => {
        if (valueEl) {
            let q = valueEl.firstChild;
            q && q.nodeType === 3 ? q.nodeValue = v + ` ` : valueEl.insertBefore(document.createTextNode(v + ` `), valueEl.firstChild);
        }
        if (numEl)
            numEl.textContent = num !== undefined ? num : (info.version ? `/ v${info.version}` : ``);
    };
    let setExpiry = (show, value) => {
        let wrap = document.getElementById(`keybox-expiry`);
        if (!wrap)
            return;
        wrap.style.display = show ? `` : `none`;
        if (!show)
            return;
        document.getElementById(`keybox-expiry-label`).textContent = window.__jerryGetTranslation && window.__jerryGetTranslation(`home_keybox_expiry`) || `Expiry`;
        document.getElementById(`keybox-expiry-value`).textContent = value;
    };
    if (!(!card || !icon || !valueEl)) {
        if (card.className = `hero-card`, !info.installed) {
            setExpiry(false);
            card.classList.add(`keybox-none`);
            icon.textContent = `vpn_key_off`;
            setLabel(kbT(`keybox_not_installed`, `Not Installed`));
            return;
        }
        let num = info.by_jerry && info.version ? `/ v${info.version}` : info.by_rkp && info.rkp_id ? `/ ${info.rkp_id === `device` ? (window.__jerryGetTranslation && window.__jerryGetTranslation(`keybox_rkp_device`) || `RKP Device`) : info.rkp_id}` : `/ Generic`;
        let label, cls, ico;
        let expMs = Date.parse(info.expires_at || ``);
        if (info.revoked) {
            label = `revoked`, cls = `keybox-revoked`, ico = `gpp_bad`;
        }
        else if (info.expired || (!isNaN(expMs) && expMs <= Date.now())) {
            label = `expired`, cls = `keybox-revoked`, ico = `event_busy`;
        }
        else if (info.softbanned) {
            label = `softbanned`, cls = `keybox-outdated`, ico = `warning`;
        }
        else if (info.by_jerry && !info.up_to_date && info.latest_version) {
            label = `update_available`, cls = `keybox-outdated`, ico = `system_update`;
        }
        else {
            label = `valid`, cls = `keybox-ok`, ico = `verified_user`;
        }
        card.classList.add(cls);
        icon.textContent = ico;
        setLabel(kbT(`keybox_` + label, { revoked: `Revoked`, expired: `Expired`, softbanned: `Softbanned`, update_available: `Update Available`, valid: `Valid` }[label]), num);
        setExpiry(!isNaN(expMs) && (label === `valid` || label === `expired`), (info.expires_at || ``).slice(0, 10));
    }
}
function setTextById(id, text) {
    let el = document.getElementById(id);
    el && (el.textContent = text);
}
