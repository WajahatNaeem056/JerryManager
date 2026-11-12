// Shell bridge between the WebUI and the root manager (window.ksu).

const SCRIPT_TIMEOUT_MS = 15000;
const SPAWN_IDLE_MS = 45000;
let paths = null;

/** Loads /json/module_paths.json (written at install time) to learn MODDIR. */
export async function initBridge() {
    try {
        paths = await (await fetch(`/json/module_paths.json?ts=` + Date.now())).json();
        if (paths?.MODDIR)
            paths.MODDIR = paths.MODDIR.replace(`/modules_update/`, `/modules/`);
    }
    catch {
        const match = (document.currentScript?.src || ``).match(/^(file:\/\/\/data\/adb\/modules\/[^/]+)/);
        paths = match ? { MODDIR: match[1] } : null;
    }
    if (!paths)
        throw Error(`Cannot determine module path`);
}

export function getModuleDir() {
    return paths?.MODDIR || null;
}

function scriptDir(kind) {
    const sub = { feature: `features`, common: `webroot/common` }[kind] || `features`;
    return `${paths.MODDIR}/${sub}/`;
}

function bridgeKind() {
    return typeof window.ksu?.exec == `function` ? `ksu` : null;
}

const uniqueName = (prefix) => `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2)}`;

function parseScriptResult(raw) {
    if (!raw)
        return { success: true, rawOutput: `` };
    try {
        const json = JSON.parse(raw);
        return { success: json.success !== false, output: json.result || json.stdout || json.output || ``, rawOutput: raw };
    }
    catch {
        return { success: true, rawOutput: raw };
    }
}

/** Runs a module script (features/ or webroot/common/) and resolves with its output. */
export function runScript(name, kind = `feature`) {
    return new Promise((resolve, reject) => {
        if (!bridgeKind()) {
            reject(Error(`no-bridge`));
            return;
        }
        if (!paths) {
            reject(Error(`no-module-path`));
            return;
        }
        const fullPath = scriptDir(kind) + name;
        const callbackName = uniqueName(`cb`);
        let timer;
        function cleanup() {
            clearTimeout(timer);
            delete window[callbackName];
        }
        timer = setTimeout(() => {
            cleanup();
            reject(Error(`timeout`));
        }, SCRIPT_TIMEOUT_MS);
        window[callbackName] = function (code, stdout) {
            cleanup();
            if (typeof code == `number`) {
                resolve({ success: code === 0, output: stdout || ``, rawOutput: stdout || `` });
                return;
            }
            const result = parseScriptResult(code);
            result.success ? resolve(result) : reject(Object.assign(Error(`script-error`), { result }));
        };
        try {
            window.ksu.exec(`sh '${fullPath}'`, `{}`, callbackName);
        }
        catch (err) {
            cleanup();
            reject(err);
        }
    });
}

/** Runs an arbitrary shell command; resolves with { code?, stdout, stderr }. */
export function exec(command) {
    return new Promise((resolve, reject) => {
        if (!bridgeKind()) {
            reject(Error(`no-bridge`));
            return;
        }
        const callbackName = uniqueName(`cb`);
        window[callbackName] = function (code, stdout, stderr) {
            delete window[callbackName];
            if (typeof code == `number`) {
                resolve({ code, stdout: stdout || ``, stderr: stderr || `` });
                return;
            }
            if (!code) {
                resolve({ stdout: ``, stderr: `` });
                return;
            }
            try {
                const json = JSON.parse(code);
                resolve({ stdout: json.result || json.stdout || json.output || ``, stderr: json.stderr || json.error || `` });
            }
            catch {
                resolve({ stdout: code, stderr: `` });
            }
        };
        try {
            window.ksu.exec(command, `{}`, callbackName);
        }
        catch (err) {
            delete window[callbackName];
            reject(err);
        }
    });
}

/** Strict rules: only a real numeric exit code counts as a result.
 *  An empty reply, plain text or no reply is a failure (a shim that never ran the script must not read as success). */
function execStrict(command) {
    return new Promise((resolve, reject) => {
        if (!bridgeKind()) {
            reject(Error(`no-bridge`));
            return;
        }
        const callbackName = uniqueName(`cb`);
        window[callbackName] = function (code, stdout, stderr) {
            delete window[callbackName];
            if (typeof code == `number`) {
                resolve({ code, stdout: typeof stdout == `string` ? stdout : ``, stderr: typeof stderr == `string` ? stderr : `` });
                return;
            }
            if (typeof code == `string` && code) {
                try {
                    const json = JSON.parse(code);
                    resolve({ code: typeof json.code == `number` ? json.code : +(json.success === false), stdout: json.result || json.stdout || json.output || ``, stderr: json.stderr || json.error || `` });
                }
                catch {
                    resolve({ code: -1, stdout: code, stderr: `` });
                }
                return;
            }
            resolve({ code: -1, stdout: ``, stderr: `` });
        };
        try {
            window.ksu.exec(command, `{}`, callbackName);
        }
        catch (err) {
            delete window[callbackName];
            reject(err);
        }
    });
}

/** Minimal child-process-like emitter used by spawnScript. */
function createProcess() {
    let ended = false;
    const handlers = { stdout: [], stderr: [], stdin: [], exit: [], error: [] };
    const stream = (list) => ({
        on(event, fn) { event === `data` && list.push(fn); },
        emit(event, data) { event === `data` && list.forEach(fn => fn(data)); },
    });
    return {
        stdout: stream(handlers.stdout),
        stderr: stream(handlers.stderr),
        stdin: { on() { }, emit() { } },
        on(event, fn) { handlers[event] && handlers[event].push(fn); },
        emit(event, ...args) {
            if (event === `exit` || event === `error`) {
                if (ended)
                    return;
                ended = true;
            }
            handlers[event] && handlers[event].forEach(fn => fn(...args));
        },
    };
}

/** Starts a module script and streams its output (ksu.spawn, or exec fallback). */
export function spawnScript(name, kind = `feature`, args = []) {
    const bridge = bridgeKind();
    const proc = createProcess();
    if (!bridge)
        return setTimeout(() => proc.emit(`error`, Error(`no-bridge`))), proc;
    if (!paths)
        return setTimeout(() => proc.emit(`error`, Error(`no-module-path`))), proc;
    const fullPath = scriptDir(kind) + name;
    // No reply at all (nothing printed, no exit) for too long = failure, never a silent success
    let idleTimer;
    const arm = () => {
        clearTimeout(idleTimer);
        idleTimer = setTimeout(() => proc.emit(`error`, Error(`timeout`)), SPAWN_IDLE_MS);
    };
    arm();
    proc.stdout.on(`data`, arm);
    proc.stderr.on(`data`, arm);
    proc.on(`exit`, () => clearTimeout(idleTimer));
    proc.on(`error`, () => clearTimeout(idleTimer));
    if (bridge === `ksu` && typeof window.ksu?.spawn == `function`) {
        const handlerName = uniqueName(`sp`);
        window[handlerName] = proc;
        proc.on(`exit`, () => delete window[handlerName]);
        proc.on(`error`, () => delete window[handlerName]);
        try {
            window.ksu.spawn(`sh`, JSON.stringify([fullPath, ...args]), `{}`, handlerName);
        }
        catch (err) {
            delete window[handlerName];
            setTimeout(() => proc.emit(`error`, err));
        }
    }
    else {
        execStrict(`sh '${fullPath}'${args.map(a => ` '${a}'`).join(``)}`).then(({ code, stdout, stderr }) => {
            stdout && stdout.split(`\n`).forEach(line => line && proc.stdout.emit(`data`, line));
            stderr && stderr.split(`\n`).forEach(line => line && proc.stderr.emit(`data`, line));
            proc.emit(`exit`, code);
        }).catch(err => {
            proc.emit(`error`, err);
        });
    }
    return proc;
}
