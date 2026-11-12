import { getConfig, setConfig } from './config.js';

var translations = {};
var fallbackTranslations = {};
window.__jerryGetTranslation = getTranslation;
export async function initI18n() {
    try {
        fallbackTranslations = await (await fetch(`lang/en.json?ts=${Date.now()}`)).json();
    }
    catch {
        fallbackTranslations = {};
    }
    // Until the user picks a language by hand, follow "Module default".
    let chosen = await getConfig(`lang_chosen`, `0`);
    let lang = chosen === `1` ? (await getConfig(`lang`, `default`) || `default`) : `default`;
    await applyLanguage(lang, true);
    setupLanguageMenu(lang);
}
var SUPPORTED_LANGS = [`en`, `zh`, `ar`, `tr`];
// "Module default": follow the device language when the module has it, otherwise English.
function resolveLang(lang) {
    if (lang !== `default`)
        return lang;
    let list = [navigator.language].concat(navigator.languages || []);
    for (let i = 0; i < list.length; i++) {
        let code = (list[i] || ``).toLowerCase().split(`-`)[0];
        if (SUPPORTED_LANGS.includes(code))
            return code;
    }
    return `en`;
}
async function applyLanguage(lang) {
    let resolved = resolveLang(lang);
    let url = `lang/${resolved}.json?ts=${Date.now()}`;
    try {
        translations = await (await fetch(url)).json();
    }
    catch {
        translations = {};
    }
    document.documentElement.setAttribute(`lang`, resolved);
    applyTranslationsToDom();
    setConfig(`lang`, lang);
    document.dispatchEvent(new CustomEvent(`languageChanged`, { detail: { langCode: lang } }));
}
export function getTranslation(key) {
    return translations[key] || fallbackTranslations[key] || null;
}
function applyTranslationsToDom() {
    document.querySelectorAll(`[data-i18n]`).forEach(e => {
        let t = e.dataset.i18n;
        if (e.tagName === `TITLE`) {
            let e = translations[t] || fallbackTranslations[t];
            e && (document.title = e);
            return;
        }
        let n = translations[t] || fallbackTranslations[t];
        if (n) {
            if (e.tagName === `MD-NAVIGATION-TAB` || e.tagName === `MD-ASSIST-CHIP` || e.tagName === `MD-FILTER-CHIP`) {
                e.label = n;
                return;
            }
            if (n.includes(`<`))
                e.innerHTML = n;
            else {
                for (; e.firstChild;)
                    e.removeChild(e.firstChild);
                e.appendChild(document.createTextNode(n));
            }
        }
    });
}
function setupLanguageMenu(e) {
    let _LANGS = [[`default`, `Module default`, `🌐`], [`en`, `English`, `🇬🇧`], [`zh`, `中文`, `🇨🇳`], [`ar`, `العربية`, `🇸🇦`], [`tr`, `Türkçe`, `🇹🇷`]];
    let trig = document.getElementById(`jerry-lang-trigger`);
    let label = document.getElementById(`jerry-lang-trigger-label`);
    let menu = document.getElementById(`jerry-lang-menu`);
    if (!trig || !menu)
        return;
    function setLabel(code) {
        let m = _LANGS.find(l => l[0] === code);
        label.textContent = ``;
        if (m && m[2]) {
            let flagSpan = document.createElement(`span`);
            flagSpan.className = `jerry-lang-option-flag`;
            flagSpan.textContent = m[2];
            label.appendChild(flagSpan);
        }
        let nameSpan = document.createElement(`span`);
        nameSpan.textContent = code === `default` ? (getTranslation(`lang_module_default`) || m[1]) : (m ? m[1] : code);
        label.appendChild(nameSpan);
    }
    function closeMenu() {
        menu.hidden = true;
        trig.setAttribute(`aria-expanded`, `false`);
        document.removeEventListener(`click`, onDocClick, true);
    }
    function onDocClick(ev) {
        if (!menu.contains(ev.target) && ev.target !== trig && !trig.contains(ev.target))
            closeMenu();
    }
    function openMenu() {
        menu.hidden = false;
        trig.setAttribute(`aria-expanded`, `true`);
        document.addEventListener(`click`, onDocClick, true);
    }
    function renderMenu(current) {
        menu.innerHTML = ``;
        _LANGS.forEach(([code, name, flag]) => {
            let item = document.createElement(`div`);
            item.className = `jerry-lang-option` + (code === current ? ` jerry-lang-option--selected` : ``);
            item.setAttribute(`role`, `option`);
            item.setAttribute(`data-code`, code);
            let flagSpan = document.createElement(`span`);
            flagSpan.className = `jerry-lang-option-flag`;
            flagSpan.textContent = flag || ``;
            let nameSpan = document.createElement(`span`);
            nameSpan.textContent = code === `default` ? (getTranslation(`lang_module_default`) || name) : name;
            item.appendChild(flagSpan);
            item.appendChild(nameSpan);
            item.addEventListener(`click`, async () => {
                closeMenu();
                try {
                    setConfig(`lang_chosen`, `1`);
                    await applyLanguage(code);
                }
                catch (err) {
                    console.warn(`Language change failed:`, err);
                }
            });
            menu.appendChild(item);
        });
    }
    setLabel(e);
    renderMenu(e);
    trig.addEventListener(`click`, ev => {
        ev.stopPropagation();
        if (menu.hidden)
            openMenu();
        else
            closeMenu();
    });
    document.addEventListener(`languageChanged`, ev => {
        let code = ev.detail && ev.detail.langCode || e;
        setLabel(code);
        renderMenu(code);
    });
}
