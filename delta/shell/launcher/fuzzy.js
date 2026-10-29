.pragma library

// Нечёткий поиск для лаунчера и выбора обоев.
// Оценка 0 — не подходит; чем больше, тем выше в списке.

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

function norm(s) {
    return String(s || "").toLowerCase().replace(/ё/g, "е");
}

// Совпадение запроса с одной строкой.
function matchText(q, text) {
    if (!text) return 0;
    const t = norm(text);
    if (t === q) return 100;
    if (t.startsWith(q)) return 90 - Math.min(10, (t.length - q.length) / 4);
    const at = t.indexOf(q);
    if (at > 0) {
        // начало слова ценнее середины
        const prev = t[at - 1];
        return (prev === " " || prev === "-" || prev === "_" || prev === "." ? 75 : 55) - Math.min(10, at / 3);
    }
    if (q.length < 2) return 0;
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

// fields: [[строка или массив строк, вес], …]
function score(query, fields) {
    const q = norm(query.trim());
    if (q.length === 0) return 1;
    const variants = [q];
    const sw = swapLayout(q);
    if (sw !== q) variants.push(sw);
    let best = 0;
    for (const v of variants) {
        for (const [value, weight] of fields) {
            // списки из C++ (QStringList) — не настоящие массивы JS
            const list = typeof value === "string" ? [value] : (value ? Array.from(value) : []);
            for (const s of list) {
                const m = matchText(v, s) * weight;
                if (m > best) best = m;
            }
        }
    }
    return best;
}
