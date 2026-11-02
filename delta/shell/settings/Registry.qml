pragma Singleton

import QtQuick
import qs.common
import Quickshell
import Quickshell.Io
import "search.js" as Search

// Список разделов «Настроек»: группы, названия, иконки, слова для поиска.
// Файлы разделов пишут разные модули, поэтому названия и группы живут здесь,
// а не в самих файлах: боковая панель и поиск работают, даже пока раздел не
// загружен или его ещё нет. Слова для поиска из файлов (property keywords)
// подмешиваются при запуске.
Singleton {
    id: root

    readonly property string dir: Quickshell.shellDir + "/settings/sections"

    // id = имя файла в нижнем регистре; он же — аргумент `delta-settings <id>`;
    // group — папка (folders ниже). "home" — главная с папками, не файл.
    readonly property var sections: [
        { id: "display",       file: "Display",       group: "system",    title: I18n.tr("Экран"),                    icon: "monitor",   keywords: "монитор разрешение частота масштаб поворот hdr vrr яркость ночной свет" },
        { id: "sound",         file: "Sound",         group: "system",    title: I18n.tr("Звук"),                     icon: "volume",    keywords: "громкость динамики наушники микрофон выход вход" },
        { id: "power",         file: "Power",         group: "system",    title: I18n.tr("Питание"),                  icon: "power",     keywords: "батарея сон гибернация крышка энергия профиль" },
        { id: "performance",   file: "Performance",   group: "system",    title: I18n.tr("Производительность"),       icon: "gauge",     keywords: "процессор частота ядра турбо эконом экономия баланс максимальная режим игры" },
        { id: "updates",       file: "Updates",       group: "system",    title: I18n.tr("Обновления"),               icon: "download",  keywords: "pacman пакеты обновить система" },
        { id: "about",         file: "About",         group: "system",    title: I18n.tr("О системе"),                icon: "info",      keywords: "система версия процессор видеокарта память диск имя компьютера ядро" },
        { id: "network",       file: "Network",       group: "devices",   title: I18n.tr("Сеть"),                     icon: "wifi",      keywords: "wi-fi wifi интернет ethernet vpn прокси" },
        { id: "bluetooth",     file: "Bluetooth",     group: "devices",   title: "Bluetooth",                icon: "bluetooth", keywords: "блютуз устройства наушники сопряжение" },
        { id: "keyboard",      file: "Keyboard",      group: "devices",   title: I18n.tr("Клавиатура"),               icon: "keyboard",  keywords: "раскладка язык переключение повтор сочетания горячие клавиши" },
        { id: "mouse",         file: "Mouse",         group: "devices",   title: I18n.tr("Мышь и тачпад"),            icon: "mouse",     keywords: "чувствительность скорость прокрутка тап касание" },
        { id: "appearance",    file: "Appearance",    group: "look",      title: I18n.tr("Оформление"),               icon: "palette",   keywords: "тема цвет акцент тёмная светлая прозрачность стекло скругление шрифт значки курсор gtk qt" },
        { id: "wallpapers",    file: "Wallpapers",    group: "look",      title: I18n.tr("Обои"),                     icon: "image",     keywords: "фон картинка видеообои папка" },
        { id: "docks",         file: "Docks",         group: "look",      title: I18n.tr("Доки"),                     icon: "dock",      keywords: "панель автоскрытие край модули значки" },
        { id: "widgets",       file: "Widgets",       group: "look",      title: I18n.tr("Виджеты"),                  icon: "widgets",   keywords: "часы погода календарь рабочий стол" },
        { id: "lock",          file: "Lock",          group: "look",      title: I18n.tr("Экран блокировки"),         icon: "lock",      keywords: "блокировка вход часы виджеты" },
        { id: "windows",       file: "Windows",       group: "look",      title: I18n.tr("Окна"),                     icon: "windows",   keywords: "отступы рамка скругление размытие анимации желе" },
        { id: "defaultapps",   file: "DefaultApps",   group: "apps",      title: I18n.tr("Приложения по умолчанию"),  icon: "apps",      keywords: "браузер почта файлы терминал изображения видео музыка текст mime" },
        { id: "autostart",     file: "Autostart",     group: "apps",      title: I18n.tr("Автозапуск"),               icon: "rocket",    keywords: "запуск при входе программы" },
        { id: "notifications", file: "Notifications", group: "apps",      title: I18n.tr("Уведомления"),              icon: "bell",      keywords: "не беспокоить приложения экран блокировки" },
        { id: "recommendations", file: "Recommendations", group: "apps",      title: I18n.tr("Рекомендации"),             icon: "gamepad",   keywords: "добро пожаловать помощник драйверы видеокарта nvidia amd vulkan steam игры библиотеки магазин приложения" },
        { id: "profile",       file: "Profile",       group: "accounts",  title: I18n.tr("Профиль"),                  icon: "user",      keywords: "имя аватар фото пароль автовход" },
        { id: "users",         file: "Users",         group: "accounts",  title: I18n.tr("Пользователи"),             icon: "users",     keywords: "учётные записи добавить удалить администратор" },
        { id: "github",        file: "GitHub",        group: "accounts",  title: "GitHub",                   icon: "github",    keywords: "репозиторий синхронизация" },
        { id: "datetime",      file: "DateTime",      group: "time",      title: I18n.tr("Дата и время"),             icon: "clock",     keywords: "часовой пояс время ntp синхронизация 24 часа" },
        { id: "language",      file: "Language",      group: "time",      title: I18n.tr("Язык и регион"),            icon: "globe",     keywords: "локаль язык форматы дата числа валюта регион" }
    ]
    // папки: в боковой панели сворачиваются, на главной — карточки
    readonly property var folders: [
        { id: "system",   title: I18n.tr("Система"),            icon: "settings" },
        { id: "devices",  title: I18n.tr("Сеть и устройства"),  icon: "wifi" },
        { id: "look",     title: I18n.tr("Персонализация"),     icon: "palette" },
        { id: "apps",     title: I18n.tr("Приложения"),         icon: "apps" },
        { id: "accounts", title: I18n.tr("Учётные записи"),     icon: "users" },
        { id: "time",     title: I18n.tr("Время и язык"),       icon: "globe" }
    ]
    function folder(id) { return folders.find(f => f.id === id) || null; }

    // другие имена для ссылок вида `delta-settings look`
    readonly property var aliases: ({
        look: "appearance", theme: "appearance", walls: "wallpapers", wallpaper: "wallpapers",
        dock: "docks", bottom: "docks", top: "docks", notif: "notifications",
        monitor: "display", monitors: "display", screen: "display", audio: "sound",
        wifi: "network", mouse: "mouse", touchpad: "mouse", input: "keyboard",
        account: "profile", time: "datetime", date: "datetime", locale: "language",
        apps: "defaultapps", system: "about", update: "updates",
        welcome: "recommendations", drivers: "recommendations", games: "recommendations"
    })

    // { "Display": true, … } — какие файлы разделов есть на диске
    property var present: ({})
    // { "Display": "слова из файла", … }
    property var fileKeywords: ({})
    property bool scanned: false

    function byId(id) { return sections.find(s => s.id === id) || null; }

    // имя из командной строки → id раздела (или "", если такого нет)
    function resolve(name) {
        const n = String(name || "").toLowerCase().trim();
        if (n === "home" || n === "all") return "home";
        if (byId(n)) return n;
        if (aliases[n]) return aliases[n];
        const hit = sections.find(s => s.file.toLowerCase() === n || s.title.toLowerCase() === n);
        return hit ? hit.id : "";
    }

    // поиск без учёта регистра и разницы «ё»/«е»
    function norm(t) { return String(t || "").toLowerCase().replace(/ё/g, "е"); }
    function matches(sec, query) {
        const q = norm(query).trim();
        if (q.length === 0) return true;
        const hay = norm([sec.title, (folder(sec.group) || {}).title, sec.keywords, fileKeywords[sec.file] || ""].join(" "));
        return q.split(/\s+/).every(w => hay.indexOf(w) !== -1);
    }
    // разделы, где что-то нашлось (боковая панель при поиске)
    function filtered(query) {
        if (norm(query).trim().length === 0) return sections;
        const hit = {};
        for (const r of search(query)) hit[r.sec] = true;
        return sections.filter(s => hit[s.id] || matches(s, query));
    }

    // Строки разделов для поиска: { sec, kind: "row"|"card", key, sub, card }.
    // key, sub, card — исходные строки для I18n.tr (ищем и по переводу, и по
    // ним); у заголовков вида «Теплота: 40 %» key — начало до значения.
    property var index: []
    // заголовок строки без значения на конце («Теплота: » → «Теплота»)
    function label(key) { return String(key || "").replace(/[\s:—-]+$/, ""); }

    // Поиск: разделы и строки, лучшие первыми, не больше limit.
    // Результат: { sec, kind: "section"|"card"|"row", key ("" — раздел
    // целиком), sub, card, score }
    function search(query, limit) {
        const q = norm(query).trim();
        if (q.length === 0) return [];
        const out = [];
        for (const sec of sections) {
            if (scanned && present[sec.file] !== true) continue;
            const f = folder(sec.group);
            const s = Search.score(q, [[sec.title, 1.15], [sec.keywords, 0.7], [fileKeywords[sec.file] || "", 0.7], [f ? f.title : "", 0.45]]);
            if (s > 0) out.push({ sec: sec.id, kind: "section", key: "", sub: "", card: "", score: s + 8 });
        }
        for (const e of index) {
            const sec = byId(e.sec);
            if (!sec) continue;
            const name = label(e.key);
            const tr = I18n.tr(e.key);
            const fields = [[label(tr), 1.0], [e.sub ? I18n.tr(e.sub) : "", 0.55],
                            [e.card ? label(I18n.tr(e.card)) : "", 0.6], [sec.title, 0.5], [sec.keywords, 0.35]];
            // другой язык — ищем и по русскому оригиналу
            if (tr !== e.key) fields.push([name, 0.9]);
            const s = Search.score(q, fields);
            if (s > 0) out.push({ sec: e.sec, kind: e.kind, key: e.key, sub: e.sub, card: e.kind === "card" ? "" : e.card, score: s + (e.kind === "card" ? 2 : 0) });
        }
        out.sort((a, b) => b.score - a.score);
        // слабое рядом с сильным — шум (опечатка «свет» → «Цвет», строки,
        // попавшие только по словам раздела): отсекаем относительно лучшего
        const floor = out.length ? Math.max(18, out[0].score * 0.5) : 0;
        // одинаковые строки в одной карточке (заголовок повторён) — один раз
        const seen = {}, res = [];
        for (const r of out) {
            if (r.score < floor) break;
            const k = r.sec + "\t" + r.card + "\t" + label(r.key);
            if (seen[k]) continue;
            seen[k] = true;
            res.push(r);
            if (res.length >= (limit || 50)) break;
        }
        return res;
    }

    function rescan() { scan.running = true; indexer.running = true; }

    Process {
        id: indexer
        running: true
        command: ["sh", "-c", "cd \"$1\" 2>/dev/null && awk -f \"$2\" ./*.qml", "sh", root.dir, Quickshell.shellDir + "/settings/index.awk"]
        stdout: StdioCollector {
            onStreamFinished: {
                const byFile = {};
                for (const s of root.sections) byFile[s.file] = s.id;
                const out = [];
                let card = "", file = "", last = null;
                for (const line of text.split("\n")) {
                    const p = line.split("\t");
                    if (p.length < 3) continue;
                    const f = p[0].replace(/^\.\//, "");
                    if (f !== file) { file = f; card = ""; last = null; }
                    const sec = byFile[f];
                    if (!sec) continue;
                    if (p[1] === "sub") { if (last && !last.sub) last.sub = p[2]; continue; }
                    if (p[1] === "card") card = p[2];
                    last = { sec, kind: p[1], key: p[2], sub: "", card };
                    out.push(last);
                }
                root.index = out;
            }
        }
    }

    // имя файла <TAB> слова из `property string keywords: "…"`
    Process {
        id: scan
        running: true
        command: ["sh", "-c", "cd \"$1\" 2>/dev/null || exit 0; for f in *.qml; do [ -f \"$f\" ] || continue; " +
                  "k=$(sed -n 's/.*property string keywords: *\"\\([^\"]*\\)\".*/\\1/p' \"$f\" | head -n1); " +
                  "printf '%s\\t%s\\n' \"${f%.qml}\" \"$k\"; done", "sh", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = {}, k = {};
                for (const line of text.split("\n")) {
                    if (!line.length) continue;
                    const tab = line.indexOf("\t");
                    const name = tab === -1 ? line : line.slice(0, tab);
                    p[name] = true;
                    k[name] = tab === -1 ? "" : line.slice(tab + 1);
                }
                root.present = p;
                root.fileKeywords = k;
                root.scanned = true;
            }
        }
    }
}
