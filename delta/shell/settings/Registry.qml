pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Список разделов «Настроек»: группы, названия, иконки, слова для поиска.
// Файлы разделов пишут разные модули, поэтому названия и группы живут здесь,
// а не в самих файлах: боковая панель и поиск работают, даже пока раздел не
// загружен или его ещё нет. Слова для поиска из файлов (property keywords)
// подмешиваются при запуске.
Singleton {
    id: root

    readonly property string dir: Quickshell.shellDir + "/settings/sections"

    // id = имя файла в нижнем регистре; он же — аргумент `delta-settings <id>`
    readonly property var sections: [
        { id: "display",       file: "Display",       group: "Система",          title: "Экран",                    icon: "monitor",   keywords: "монитор разрешение частота масштаб поворот hdr vrr яркость ночной свет" },
        { id: "sound",         file: "Sound",         group: "Система",          title: "Звук",                     icon: "volume",    keywords: "громкость динамики наушники микрофон выход вход" },
        { id: "network",       file: "Network",       group: "Система",          title: "Сеть",                     icon: "wifi",      keywords: "wi-fi wifi интернет ethernet vpn прокси" },
        { id: "bluetooth",     file: "Bluetooth",     group: "Система",          title: "Bluetooth",                icon: "bluetooth", keywords: "блютуз устройства наушники сопряжение" },
        { id: "power",         file: "Power",         group: "Система",          title: "Питание",                  icon: "power",     keywords: "батарея сон гибернация крышка энергия профиль" },
        { id: "appearance",    file: "Appearance",    group: "Персонализация",   title: "Оформление",               icon: "palette",   keywords: "тема цвет акцент тёмная светлая прозрачность стекло скругление шрифт значки курсор gtk qt" },
        { id: "wallpapers",    file: "Wallpapers",    group: "Персонализация",   title: "Обои",                     icon: "image",     keywords: "фон картинка видеообои папка" },
        { id: "docks",         file: "Docks",         group: "Персонализация",   title: "Доки",                     icon: "dock",      keywords: "панель автоскрытие край модули значки" },
        { id: "widgets",       file: "Widgets",       group: "Персонализация",   title: "Виджеты",                  icon: "widgets",   keywords: "часы погода календарь рабочий стол" },
        { id: "lock",          file: "Lock",          group: "Персонализация",   title: "Экран блокировки",         icon: "lock",      keywords: "блокировка вход часы виджеты" },
        { id: "windows",       file: "Windows",       group: "Персонализация",   title: "Окна",                     icon: "windows",   keywords: "отступы рамка скругление размытие анимации желе" },
        { id: "keyboard",      file: "Keyboard",      group: "Ввод",             title: "Клавиатура",               icon: "keyboard",  keywords: "раскладка язык переключение повтор сочетания горячие клавиши" },
        { id: "mouse",         file: "Mouse",         group: "Ввод",             title: "Мышь и тачпад",            icon: "mouse",     keywords: "чувствительность скорость прокрутка тап касание" },
        { id: "profile",       file: "Profile",       group: "Учётные записи",   title: "Профиль",                  icon: "user",      keywords: "имя аватар фото пароль автовход" },
        { id: "users",         file: "Users",         group: "Учётные записи",   title: "Пользователи",             icon: "users",     keywords: "учётные записи добавить удалить администратор" },
        { id: "datetime",      file: "DateTime",      group: "Общие",            title: "Дата и время",             icon: "clock",     keywords: "часовой пояс время ntp синхронизация 24 часа" },
        { id: "language",      file: "Language",      group: "Общие",            title: "Язык и регион",            icon: "globe",     keywords: "локаль язык форматы дата числа валюта регион" },
        { id: "defaultapps",   file: "DefaultApps",   group: "Общие",            title: "Приложения по умолчанию",  icon: "apps",      keywords: "браузер почта файлы терминал изображения видео музыка текст mime" },
        { id: "autostart",     file: "Autostart",     group: "Общие",            title: "Автозапуск",               icon: "rocket",    keywords: "запуск при входе программы" },
        { id: "notifications", file: "Notifications", group: "Общие",            title: "Уведомления",              icon: "bell",      keywords: "не беспокоить приложения экран блокировки" },
        { id: "recommendations", file: "Recommendations", group: "Общие",        title: "Рекомендации",             icon: "gamepad",   keywords: "добро пожаловать помощник драйверы видеокарта nvidia amd vulkan steam игры библиотеки магазин приложения" },
        { id: "updates",       file: "Updates",       group: "Общие",            title: "Обновления",               icon: "download",  keywords: "pacman пакеты обновить система" },
        { id: "github",        file: "GitHub",        group: "Общие",            title: "GitHub",                   icon: "github",    keywords: "репозиторий синхронизация" },
        { id: "about",         file: "About",         group: "Общие",            title: "О системе",                icon: "info",      keywords: "система версия процессор видеокарта память диск имя компьютера ядро" }
    ]
    readonly property var groups: ["Система", "Персонализация", "Ввод", "Учётные записи", "Общие"]

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
        const hay = norm([sec.title, sec.group, sec.keywords, fileKeywords[sec.file] || ""].join(" "));
        return q.split(/\s+/).every(w => hay.indexOf(w) !== -1);
    }
    function filtered(query) { return sections.filter(s => matches(s, query)); }

    function rescan() { scan.running = true; }

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
