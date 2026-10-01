import { getTranslation } from './i18n.js';

var lastOnlineState = null;
export function startNetworkMonitor() {
    updateNetworkChip();
    setInterval(updateNetworkChip, 3e3);
    window.addEventListener(`online`, updateNetworkChip);
    window.addEventListener(`offline`, updateNetworkChip);
}
async function updateNetworkChip() {
    let e = await checkOnline();
    if (e === lastOnlineState)
        return;
    let t = lastOnlineState;
    lastOnlineState = e;
    let n = document.getElementById(`network-chip`);
    let r = getTranslation;
    let i = r(`home_status_online`) || `Online`;
    let a = r(`home_status_offline`) || `Offline`;
    if (e) {
        if (n?.classList.remove(`offline`), n) {
            let e = n.querySelector(`#network-label`);
            e && (e.textContent = i);
            let t = n.querySelector(`md-icon`);
            t && (t.textContent = `wifi`);
        }
    }
    else {
        if (n?.classList.add(`offline`), n) {
            let e = n.querySelector(`#network-label`);
            e && (e.textContent = a);
            let t = n.querySelector(`md-icon`);
            t && (t.textContent = `wifi_off`);
        }
    }
}
var CONNECTIVITY_URLS = [`https://clients3.google.com/generate_204`, `https://www.gstatic.com/generate_204`];
async function checkOnline() {
    if (!navigator.onLine)
        return false;
    for (let e of CONNECTIVITY_URLS)
        try {
            let controller = new AbortController;
            let timer = setTimeout(() => controller.abort(), 2e3);
            return await fetch(e, {
                signal: controller.signal, mode: `no-cors`
            }), clearTimeout(timer), true;
        }
        catch {
        }
    return false;
}
