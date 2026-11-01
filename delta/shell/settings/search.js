.pragma library
.import "../launcher/fuzzy.js" as Fuzzy

// Поиск по «Настройкам»: не только разделы, но и каждая строка в них.
// Слова запроса ищутся по отдельности и все должны найтись — в названии
// строки, её пояснении, карточке или разделе. Прощает другую раскладку
// («zhrjcnm» — «яркость», это умеет fuzzy.js), пропущенные буквы, другую
// форму слова («обоев» — «обои») и опечатку-другую («яркасть»).

function norm(s) { return String(s || "").toLowerCase().replace(/ё/g, "е"); }

// расстояние Дамерау — Левенштейна, с ранним выходом, когда больше max
function dist(a, b, max) {
    if (Math.abs(a.length - b.length) > max) return max + 1;
    let prev2 = null, prev = [];
    for (let j = 0; j <= b.length; j++) prev.push(j);
    for (let i = 1; i <= a.length; i++) {
        const cur = [i];
        let best = i;
        for (let j = 1; j <= b.length; j++) {
            const c = a[i - 1] === b[j - 1] ? 0 : 1;
            let v = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + c);
            if (prev2 && i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) v = Math.min(v, prev2[j - 2] + 1);
            cur.push(v);
            if (v < best) best = v;
        }
        if (best > max) return max + 1;
        prev2 = prev;
        prev = cur;
    }
    return prev[b.length];
}

// слово запроса против текста: точное и нечёткое (fuzzy.js), иначе — другая
// форма того же слова (общее начало) или опечатка
function wordScore(w, text) {
    if (!text) return 0;
    const s = Fuzzy.score(w, [[text, 1]]);
    // разреженная подпоследовательность у коротких слов — почти всегда случайность
    if (s >= 50 || (s > 0 && w.length >= 4)) return s;
    if (w.length < 4) return 0;
    let best = 0;
    const tokens = norm(text).split(/[^0-9a-zа-я]+/).filter(t => t.length);
    for (let i = 0; i < tokens.length; i++) {
        const t = tokens[i];
        if (t.length < 3) continue;
        // слово в начале названия ценнее: «Яркость» выше «Громкость и яркость»
        const lead = i === 0 ? 6 : 0;
        // формы слова: «обоев» — «обои», «яркости» — «яркость»; общее начало
        // почти во всё слово запроса («автоскрытие» — не «авто»)
        let k = 0;
        while (k < w.length && k < t.length && w[k] === t[k]) k++;
        if (k >= Math.max(4, Math.min(w.length, t.length) - 2, w.length - 3)) best = Math.max(best, 45 + lead);
        // опечатка: одна на 4–6 букв, две — в длинных словах
        const max = w.length >= 7 ? 2 : 1;
        const d = dist(w, t.slice(0, w.length + max), max);
        if (d <= max) best = Math.max(best, 40 - d * 8 + lead);
    }
    return best;
}

// как ещё называют то же самое: слово запроса → слова в строках настроек
const SYN = {
    "автоскрытие": "скрывать автоматически", "скрытие": "скрывать",
    "вайфай": "wi-fi", "вифи": "wi-fi", "wifi": "wi-fi", "блютуз": "bluetooth",
    "фон": "обои", "заставка": "обои", "тема": "оформление",
    "громкость": "звук", "микрофон": "вход", "разрешение": "разрешение экрана",
    "герцы": "частота", "гц": "частота", "fps": "частота", "dpi": "масштаб",
    "автовход": "входить автоматически", "автозагрузка": "автозапуск",
    "русский": "язык", "english": "язык", "часовой": "часовой пояс"
};

// fields: [[текст, вес], …]; все слова должны найтись хоть где-то.
// Запрос с синонимами считается вторым вариантом, берём лучший.
function score(query, fields) {
    const q = norm(query).trim();
    const alt = q.split(/\s+/).map(w => SYN[w] || w).join(" ");
    const a = scoreOne(q, fields);
    return alt === q ? a : Math.max(a, scoreOne(alt, fields) * 0.95);
}

function scoreOne(query, fields) {
    const words = norm(query).trim().split(/\s+/).filter(w => w.length);
    if (!words.length) return 0;
    let total = 0;
    for (const w of words) {
        let best = 0;
        for (const [text, weight] of fields) {
            const s = wordScore(w, text) * weight;
            if (s > best) best = s;
        }
        if (best <= 0) return 0;
        total += best;
    }
    return total / words.length;
}
