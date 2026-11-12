import catalogs from './catalogs.js';
const SOURCE = 'zh-CN';
const isLocale = (tag) => typeof tag === 'string' && Object.hasOwn(catalogs, tag);
const injected = globalThis.pointyLocale;
export const locale = isLocale(injected) ? injected : SOURCE;
function find(lang, id) {
    let node = catalogs[lang];
    for (const part of id.split('.'))
        node = node && typeof node === 'object' ? node[part] : undefined;
    return typeof node === 'string' ? node : undefined;
}
function lookup(lang, id, count) {
    if (typeof count === 'number')
        return find(lang, `${id}_${new Intl.PluralRules(lang).select(count)}`) ?? find(lang, `${id}_other`);
    return find(lang, id);
}
function say(lang, id, params = {}) {
    const msg = lookup(lang, id, params.count) ?? lookup(SOURCE, id, params.count) ?? id;
    return msg.replace(/\{(\w+)\}/g, (m, name) => (name in params ? String(params[name]) : m));
}
export const translate = (lang, key, params) => say(lang, key, params);
// The page's texts, in the language Go gave it.
export const t = (key, params) => say(locale, key, params);
// A text Go sent as a key and its params.
export const tm = (m) => say(locale, m.key, m.params);
