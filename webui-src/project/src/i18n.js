import { getConfig, setConfig } from './config.js';

var translations = {};
var fallbackTranslations = {};
window.__jerryGetTranslation = getTranslation;
export async function initI18n() {
    try {
        fallbackTranslations = await (await fetch(`lang/source/string.json?ts=${Date.now()}`)).json();
    }
    catch {
        fallbackTranslations = {};
    }
    let lang = await getConfig(`lang`, `en`) || `en`;
    await applyLanguage(lang, true);
    setupLanguageMenu(lang);
}
async function applyLanguage(lang) {
    let url = lang === `en` ? `lang/source/string.json?ts=${Date.now()}` : `lang/${lang}.json?ts=${Date.now()}`;
    try {
        translations = await (await fetch(url)).json();
    }
    catch {
        translations = {};
    }
    document.documentElement.setAttribute(`lang`, lang);
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
    let _LANGS = [[`en`, `English`, `🇬🇧`], [`zh`, `中文`, `🇨🇳`], [`ar`, `العربية`, `🇸🇦`]];
    let trig = document.getElementById(`jerry-lang-trigger`);
    let label = document.getElementById(`jerry-lang-trigger-label`);
    let menu = document.getElementById(`jerry-lang-menu`);
    if (!trig || !menu)
        return;
    function nameFor(code) {
        let m = _LANGS.find(l => l[0] === code);
        return m ? (m[2] ? m[2] + ` ` + m[1] : m[1]) : code;
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
            nameSpan.textContent = name;
            item.appendChild(flagSpan);
            item.appendChild(nameSpan);
            item.addEventListener(`click`, async () => {
                closeMenu();
                try {
                    await applyLanguage(code);
                }
                catch (err) {
                    console.warn(`Language change failed:`, err);
                }
            });
            menu.appendChild(item);
        });
    }
    label.textContent = nameFor(e);
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
        label.textContent = nameFor(code);
        renderMenu(code);
    });
}
