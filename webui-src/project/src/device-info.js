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
async function loadKeyboxCard() {
    try {
        lastKeyboxInfo = await fetchKeyboxInfo();
        renderKeyboxCard(lastKeyboxInfo);
    }
    catch {
    }
}
function renderKeyboxCard(info) {
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
    let setLabel = (v) => {
        if (valueEl) {
            let q = valueEl.firstChild;
            q && q.nodeType === 3 ? q.nodeValue = v + ` ` : valueEl.insertBefore(document.createTextNode(v + ` `), valueEl.firstChild);
        }
        if (numEl)
            numEl.textContent = info.version ? `/ v${info.version}` : ``;
    };
    if (!(!card || !icon || !valueEl)) {
        if (card.className = `hero-card`, !info.installed) {
            card.classList.add(`keybox-none`);
            icon.textContent = `vpn_key_off`;
            setLabel(`Not Installed`);
            return;
        }
        if (info.expired) {
            card.classList.add(`keybox-revoked`);
            icon.textContent = `event_busy`;
            setLabel(`Expired`);
            return;
        }
        if (!info.by_jerry) {
            card.classList.add(`keybox-unknown`);
            icon.textContent = `key`;
            setLabel(`Generic`);
            return;
        }
        if (info.revoked) {
            card.classList.add(`keybox-revoked`);
            icon.textContent = `gpp_bad`;
            setLabel(`Revoked`);
            return;
        }
        if (info.softbanned) {
            card.classList.add(`keybox-outdated`);
            icon.textContent = `warning`;
            setLabel(`Softbanned`);
            return;
        }
        if (info.up_to_date) {
            card.classList.add(`keybox-ok`);
            icon.textContent = `verified_user`;
            setLabel(`Valid`);
        }
        else
            card.classList.add(`keybox-outdated`), icon.textContent = `system_update`, setLabel(`New Keybox Available`);
    }
}
function setTextById(id, text) {
    let el = document.getElementById(id);
    el && (el.textContent = text);
}
