.pragma library

// Нечёткий поиск для лаунчера и выбора обоев.
// Оценка 0 — не подходит; чем больше, тем выше в списке.
//
// Понимает: другую раскладку («ашкуащч» → firefox), транслит в обе стороны
// («телеграм» → Telegram, «nastroiki» → «Настройки»), несколько слов в любом
// порядке («code visual»), опечатку в одну-две буквы («fierfox»), звучание
// («стим» → Steam, «дискорд» → Discord) и первые буквы слов («vsc»).

const EN = "qwertyuiop[]asdfghjkl;'zxcvbnm,./`";
const RU = "йцукенгшщзхъфывапролджэячсмитьбю.ё";

// Набрали в другой раскладке («ашкуащч» вместо «firefox») — ищем и так.
function swapLayout(s) {
    let out = "";
    for (const ch of s) {
        let i = EN.indexOf(ch);
        if (i !== -1) { out += RU[i]; continue; }
        i = RU.indexOf(ch);
        out += i !== -1 ? EN[i] : ch;
    }
    return out;
}

// Кириллица латиницей — так, как её обычно пишут в названиях программ.
const TR = {
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ж": "zh", "з": "z", "и": "i",
    "й": "i", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s",
    "т": "t", "у": "u", "ф": "f", "х": "h", "ц": "c", "ч": "ch", "ш": "sh", "щ": "sch", "ъ": "",
    "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
    // казахские, украинские и белорусские буквы
    "і": "i", "ї": "i", "є": "e", "ў": "u", "ә": "a", "ғ": "g", "қ": "k", "ң": "n", "ө": "o",
    "ұ": "u", "ү": "u", "һ": "h"
};

function translit(s) {
    let out = "", any = false;
    for (const ch of s) {
        const t = TR[ch];
        if (t === undefined) { out += ch; continue; }
        out += t;
        any = true;
    }
    return any ? out : s;
}

// Остов слова по звучанию: без гласных и повторов, c/q → k, x → ks, ph → f.
// «стим» и Steam, «дискорд» и Discord, «фаерфокс» и Firefox дают одно и то же.
function skeleton(lat) {
    const s = lat.replace(/ph/g, "f").replace(/x/g, "ks").replace(/[cq]/g, "k").replace(/w/g, "v")
        .replace(/[aeiouy]/g, "");
    let out = "";
    for (const ch of s) if (ch !== out[out.length - 1]) out += ch;
    return out;
}

function norm(s) {
    return String(s || "").toLowerCase().replace(/ё/g, "е");
}

// Строки приложений одни и те же при каждом нажатии клавиши — нормализуем один раз.
const cache = {};
function prep(text) {
    let p = cache[text];
    if (p) return p;
    const t = norm(text);
    const lat = translit(t);
    p = { t, lat: lat !== t ? lat : "", words: t.split(/[\s\-_.\/]+/).filter(w => w.length) };
    if (p.lat) p.latWords = lat.split(/[\s\-_.\/]+/).filter(w => w.length);
    const lw = p.latWords || p.words;
    p.skels = lw.map(skeleton).filter(k => k.length >= 2);
    p.initials = p.words.length > 1 ? p.words.map(w => w[0]).join("") : "";
    cache[text] = p;
    return p;
}

// Опечатка: расстояние Дамерау — Левенштейна не больше max (иначе max + 1).
function typo(a, b, max) {
    if (Math.abs(a.length - b.length) > max) return max + 1;
    let prev2 = null, prev = [];
    for (let j = 0; j <= b.length; j++) prev.push(j);
    for (let i = 1; i <= a.length; i++) {
        const cur = [i];
        let low = i;
        for (let j = 1; j <= b.length; j++) {
            let d = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
            if (prev2 && i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1])
                d = Math.min(d, prev2[j - 2] + 1);
            cur.push(d);
            if (d < low) low = d;
        }
        if (low > max) return max + 1;
        prev2 = prev;
        prev = cur;
    }
    return prev[b.length];
}

// Совпадение запроса с одной строкой (уже нормализованной).
function matchPlain(q, t) {
    if (!t) return 0;
    if (t === q) return 100;
    if (t.startsWith(q)) return 90 - Math.min(10, (t.length - q.length) / 4);
    const at = t.indexOf(q);
    if (at > 0) {
        // начало слова ценнее середины
        const prev = t[at - 1];
        if (prev === " " || prev === "-" || prev === "_" || prev === ".") return 75 - Math.min(10, at / 3);
        // короткий кусок внутри слова — скорее случайность («тел» в «родительский»)
        return (q.length <= 3 ? 30 : 55) - Math.min(10, at / 3);
    }
    // три буквы по порядку где-то в середине — почти всегда случайность («тел» → «родительский»)
    if (q.length < 4) return 0;
    // подпоследовательность: буквы по порядку, чем плотнее — тем лучше
    let ti = 0, first = -1, gaps = 0, last = -1;
    for (const ch of q) {
        ti = t.indexOf(ch, ti);
        if (ti === -1) return 0;
        if (first === -1) first = ti;
        if (last !== -1) gaps += ti - last - 1;
        last = ti;
        ti++;
    }
    // слишком разреженное совпадение — скорее случайность
    if (gaps > q.length * 2 + 2) return 0;
    return Math.max(5, 40 - gaps * 3 - first);
}

// Опечатка в начале какого-нибудь слова: «fierfox», «телграм».
function matchTypo(q, words) {
    if (q.length < 4 || !words) return 0;
    const max = q.length >= 7 ? 2 : 1;
    let best = 0;
    for (const w of words) {
        if (w.length < 3) continue;
        // сравниваем с началом слова той же длины (запрос бывает недописан)
        const head = w.length > q.length + max ? w.slice(0, q.length) : w;
        const d = typo(q, head, max);
        if (d <= max) best = Math.max(best, (d === 1 ? 34 : 24) - (head === w ? 0 : 4));
    }
    return best;
}

function matchText(q, text) {
    if (!text) return 0;
    const p = prep(text);
    let s = matchPlain(q, p.t);
    if (p.lat) s = Math.max(s, matchPlain(q, p.lat) - 2);
    // первые буквы слов: «vsc» — Visual Studio Code
    if (p.initials && q.length >= 2 && p.initials.startsWith(q)) s = Math.max(s, 70 - (p.initials.length - q.length) * 2);
    if (s === 0) s = Math.max(matchTypo(q, p.words), p.lat ? matchTypo(q, p.latWords) : 0);
    if (s === 0 && q.length >= 3) {
        const k = skeleton(translit(q));
        if (k.length >= 2) for (const w of p.skels) if (w.startsWith(k)) { s = Math.max(s, w === k ? 32 : 20); }
    }
    return s;
}

// Лучшее совпадение одной строки запроса со всеми полями.
function bestOf(q, fields) {
    let best = 0;
    for (const [value, weight] of fields) {
        // списки из C++ (QStringList) — не настоящие массивы JS
        const list = typeof value === "string" ? [value] : (value ? Array.from(value) : []);
        for (const s of list) {
            const raw = matchText(q, s);
            // догадки (опечатка, звучание, буквы вразброс) — только по названию:
            // в ключевых словах и категориях они находят что попало
            if (raw < 35 && weight < 0.9) continue;
            const m = raw * weight;
            if (m > best) best = m;
        }
    }
    return best;
}

// Варианты набранного: как есть, в другой раскладке, транслитом.
function variants(q) {
    const out = [q];
    const sw = swapLayout(q);
    if (sw !== q) out.push(sw);
    const lat = translit(q);
    if (lat !== q) out.push(lat);
    return out;
}

// fields: [[строка или массив строк, вес], …]
function score(query, fields) {
    const q = norm(query.trim()).replace(/\s+/g, " ");
    if (q.length === 0) return 1;
    let best = 0;
    for (const v of variants(q)) best = Math.max(best, bestOf(v, fields));
    // несколько слов: каждое должно найтись, порядок любой
    const words = q.split(" ");
    if (words.length > 1) {
        let worst = 100;
        for (const w of words) {
            let s = 0;
            for (const v of variants(w)) s = Math.max(s, bestOf(v, fields));
            worst = Math.min(worst, s);
            if (worst === 0) break;
        }
        best = Math.max(best, worst * 0.9);
    }
    return best;
}
