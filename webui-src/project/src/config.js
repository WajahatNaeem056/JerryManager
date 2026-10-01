// Persistent settings: stored on disk through the root shell and mirrored in localStorage.
import { exec } from './bridge.js';

var moduleDir = null;
var configCache = {};
export function setModuleDir(dir) {
    moduleDir = dir;
}
const CONFIG_DIR = '/data/adb/JerryManager/config';

async function readConfigFile(key) {
    if (!moduleDir)
        return null;
    const { stdout } = await exec(`cat "${CONFIG_DIR}/${key}.val" 2>/dev/null || true`);
    return stdout.trim() || null;
}
function writeConfigFile(key, value) {
    if (!moduleDir)
        return Promise.resolve();
    const encoded = btoa(unescape(encodeURIComponent(value == null ? `` : String(value))));
    return exec(`mkdir -p "${CONFIG_DIR}" && printf '%s' "${encoded}" | base64 -d > "${CONFIG_DIR}/${key}.val"`)
        .catch(err => console.warn(`Config write failed for`, key, err));
}
export async function getConfig(key, fallback) {
    if (!(key in configCache))
        configCache[key] = await readConfigFile(key) ?? fallback;
    return configCache[key];
}
export function setConfig(e, t) {
    configCache[e] = t;
    try {
        localStorage.setItem(`jm_cfg_` + e, t == null ? `` : t);
    }
    catch {
    }
    writeConfigFile(e, t);
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
