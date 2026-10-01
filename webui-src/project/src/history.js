// Script run history (localStorage).

var HISTORY_KEY = `jerry_script_history`;
var HISTORY_MAX = 240;
function readHistory() {
    try {
        return JSON.parse(localStorage.getItem(HISTORY_KEY) || `[]`);
    }
    catch {
        return [];
    }
}
export function addHistoryEntry(script, output) {
    if (typeof output != `string` && (output = String(output || ``)), !output.trim())
        return;
    let history = readHistory();
    history.unshift({
        script: script, output: output, time: new Date().toISOString()
    });
    history.length > HISTORY_MAX && (history.length = HISTORY_MAX);
    try {
        localStorage.setItem(HISTORY_KEY, JSON.stringify(history));
    }
    catch {
    }
}
