// Persistent settings: stored on disk through the root shell and mirrored in localStorage.
import { exec as rawExec } from './bridge.js';

// A config read must never block the WebUI: if the shell does not answer in time, give up and use defaults.
const EXEC_TIMEOUT_MS = 8000;
function exec(command) {
    return Promise.race([rawExec(command), new Promise((_, reject) => setTimeout(() => reject(Error(`timeout`)), EXEC_TIMEOUT_MS))]);
}

var moduleDir = null;
var configCache = {};
export function setModuleDir(dir) {
    moduleDir = dir;
}
const CONFIG_DIR = '/data/adb/JerryManager/config';

async function readConfigFile(key) {
    if (!moduleDir)
        return null;
    try {
        const { stdout } = await exec(`cat "${CONFIG_DIR}/${key}.val" 2>/dev/null || true`);
        return stdout.trim() || null;
    }
    catch {
        return undefined;
    }
}
function writeConfigFile(key, value) {
    if (!moduleDir)
        return Promise.resolve();
    const encoded = btoa(unescape(encodeURIComponent(value == null ? `` : String(value))));
    return exec(`mkdir -p "${CONFIG_DIR}" && printf '%s' "${encoded}" | base64 -d > "${CONFIG_DIR}/${key}.val"`)
        .catch(err => console.warn(`Config write failed for`, key, err));
}
var prefetched = false;
// Startup reads /json/state.json (one async fetch); the shell read is only a delayed fallback.
var prefetchPromise = null;
export function prefetchConfig() {
    return prefetchPromise = prefetchConfigNow();
}
function applyConfigValue(key, val) {
    val = typeof val == `string` ? val.trim() : ``;
    if (val && !(key in configCache))
        configCache[key] = val;
}
async function prefetchFromState() {
    try {
        const res = await fetch(`/json/state.json?ts=` + Date.now());
        if (!res.ok)
            return false;
        const state = await res.json();
        if (!state || typeof state.config != `object`)
            return false;
        // Newer WebUI saves win over the snapshot.
        try {
            const localTs = Number(localStorage.getItem(`jm_cfg_ts`)) || 0;
            if (localTs > (Number(state.config_ts) || 0) * 1000) {
                for (let i = 0; i < localStorage.length; i++) {
                    const k = localStorage.key(i);
                    if (k && k.startsWith(`jm_cfg_`) && k !== `jm_cfg_ts`) {
                        const v = localStorage.getItem(k);
                        v && (configCache[k.slice(7)] = v);
                    }
                }
            }
        }
        catch {
        }
        for (const [key, val] of Object.entries(state.config))
            applyConfigValue(key, val);
        return true;
    }
    catch {
        return false;
    }
}
async function prefetchFromShell() {
    try {
        const { stdout } = await exec(`cd "${CONFIG_DIR}" 2>/dev/null && for f in *.val; do [ -f "$f" ] || continue; printf '%s\\t%s\\n' "\${f%.val}" "$(base64 "$f" 2>/dev/null | tr -d '\\n')"; done; true`);
        for (const line of stdout.split(`\n`)) {
            const i = line.indexOf(`\t`);
            if (i < 1)
                continue;
            try {
                applyConfigValue(line.slice(0, i), decodeURIComponent(escape(atob(line.slice(i + 1).trim()))));
            }
            catch {
            }
        }
        return true;
    }
    catch {
        return false;
    }
}
async function prefetchConfigNow() {
    if (!moduleDir)
        return;
    if (await prefetchFromState()) {
        prefetched = true;
        return;
    }
    await new Promise(resolve => setTimeout(resolve, 3000));
    prefetched = await prefetchFromShell();
}
export async function getConfig(key, fallback) {
    if (prefetchPromise)
        await prefetchPromise;
    if (key in configCache)
        return configCache[key];
    if (prefetched)
        return configCache[key] = fallback;
    const val = await readConfigFile(key);
    if (val === undefined)
        return fallback; // shell did not answer: use the default now, ask again next time
    return configCache[key] = val ?? fallback;
}
export function setConfig(e, t) {
    // Same value: skip the shell write.
    const unchanged = configCache[e] === t;
    configCache[e] = t;
    try {
        localStorage.setItem(`jm_cfg_` + e, t == null ? `` : t);
        localStorage.setItem(`jm_cfg_ts`, String(Date.now()));
    }
    catch {
    }
    unchanged || writeConfigFile(e, t);
}
export async function migrateLegacyConfig() {
    try {
        if (localStorage.getItem(`_cfg_migrated`))
            return;
        for (let [e, t] of Object.entries({
            selectedLanguage: `lang`, themeMode: `theme`, themePreset: `theme_preset`, clockFormat: `clock_format`
        })) {
            let n = localStorage.getItem(e);
            n && (configCache[t] = n, writeConfigFile(t, n));
        }
        localStorage.setItem(`_cfg_migrated`, `1`);
    }
    catch {
    }
}
