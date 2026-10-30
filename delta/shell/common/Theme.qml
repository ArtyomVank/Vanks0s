pragma Singleton

import QtQuick
import Quickshell

// Токены оформления Delta — те же, что в концепт-макете (--glass, --fg, …).
Singleton {
    id: root

    // Тема — цвет стекла доков, меню и окон; у части тем свой акцент
    // (применяется при выборе, дальше его можно сменить).
    readonly property var builtinThemes: [
        { id: "midnight", name: "Полночь",       rgb: [20, 15, 38] },
        { id: "black",    name: "Чёрная",        rgb: [0, 0, 0] },
        { id: "graphite", name: "Графит",        rgb: [24, 25, 30] },
        { id: "storm",    name: "Шторм",         rgb: [28, 34, 44] },
        { id: "ocean",    name: "Океан",         rgb: [10, 28, 46] },
        { id: "sapphire", name: "Сапфир",        rgb: [10, 24, 66] },
        { id: "indigo",   name: "Индиго",        rgb: [24, 20, 64] },
        { id: "lilac",    name: "Сирень",        rgb: [44, 26, 60] },
        { id: "wine",     name: "Вино",          rgb: [44, 12, 28] },
        { id: "bordeaux", name: "Бордо",         rgb: [54, 10, 16] },
        { id: "cocoa",    name: "Какао",         rgb: [38, 26, 18] },
        { id: "forest",   name: "Лес",           rgb: [12, 32, 25] },
        { id: "emerald",  name: "Изумруд",       rgb: [6, 42, 36] },
        { id: "pine",     name: "Хвоя",          rgb: [18, 36, 14] },
        // готовые сочетания: фон и акцент подобраны вместе
        { id: "aurora",   name: "Сияние",        rgb: [8, 30, 38],   accent: "#3EE6B0" },
        { id: "sunset",   name: "Закат",         rgb: [46, 18, 34],  accent: "#FF8A4C" },
        { id: "neon",     name: "Неон",          rgb: [6, 6, 14],    accent: "#00E5FF" },
        { id: "amber",    name: "Янтарь",        rgb: [34, 24, 10],  accent: "#FFB020" },
        { id: "cosmos",   name: "Космос",        rgb: [14, 10, 30],  accent: "#B07CFF" },
        { id: "matrix",   name: "Терминал",      rgb: [4, 14, 6],    accent: "#39D353" },
        { id: "rose",     name: "Роза",          rgb: [40, 14, 24],  accent: "#FF5C8A" },
        { id: "slate",    name: "Сланец",        rgb: [30, 34, 40],  accent: "#7AA2F7" },
        // светлые
        { id: "white",    name: "Белая",         rgb: [247, 246, 251], light: true },
        { id: "sand",     name: "Песок",         rgb: [245, 238, 226], light: true },
        { id: "mint",     name: "Мята",          rgb: [228, 245, 238], light: true, accent: "#1FA67A" },
        { id: "lavender", name: "Лаванда",       rgb: [238, 234, 252], light: true, accent: "#7C5CFF" },
        { id: "sakura",   name: "Сакура",        rgb: [252, 236, 242], light: true, accent: "#E0567F" },
        { id: "sky",      name: "Небо",          rgb: [230, 241, 252], light: true, accent: "#2F80ED" }
    ]
    // свои темы пользователя (appearance.customThemes): те же поля + custom: true
    readonly property var customThemes: {
        const list = (Settings.s.appearance || {}).customThemes;
        return Array.isArray(list) ? list.filter(t => t && t.id && Array.isArray(t.rgb)).map(t => Object.assign({ custom: true }, t)) : [];
    }
    readonly property var themes: builtinThemes.concat(customThemes)

    readonly property var accents: ["#7C5CFF", "#2BC4F0", "#E0567F", "#3FB37A", "#F09A2B", "#E5484D", "#4C7DFF", "#C9A227"]

    readonly property var appearance: Settings.s.appearance || {}
    readonly property var current: themes.find(t => t.id === appearance.theme) || builtinThemes[2]
    readonly property bool light: current.light === true

    // Стиль — не цвет, а сам вид панелей (appearance.style):
    //   delta  — тонированное стекло с размытием (как было);
    //   gnome  — сплошные серые панели, как в GNOME (Adwaita), без прозрачности;
    //   liquid — жидкое стекло: прозрачнее, сильнее размытие, светлая кромка (Sheen).
    // preset — что ставится при выборе стиля (дальше можно поменять самому).
    readonly property var styles: [
        { id: "delta",  name: "Delta",          note: "Тонированное стекло",
          preset: { glass: 0.62, radius: 18, rounding: 16, blur: true, border: 2 } },
        { id: "gnome",  name: "GNOME",          note: "Сплошные панели без прозрачности",
          preset: { glass: 1, radius: 12, rounding: 12, blur: false, border: 0 } },
        { id: "liquid", name: "Жидкое стекло",  note: "Прозрачное стекло с бликом по краю",
          preset: { glass: 0.4, radius: 26, rounding: 22, blur: true, border: 1 } }
    ]
    readonly property string style: styles.some(x => x.id === appearance.style) ? appearance.style : "delta"
    readonly property bool flat: style === "gnome"
    readonly property bool liquid: style === "liquid"
    // выбрать стиль: вместе с ним — прозрачность, скругления, размытие и рамка окон
    function applyStyle(id) {
        const st = styles.find(x => x.id === id);
        if (!st) return;
        const p = st.preset;
        Settings.set("appearance.style", id);
        Settings.set("appearance.glass", p.glass);
        Settings.set("appearance.radius", p.radius);
        Settings.set("windows.rounding", p.rounding);
        Settings.set("windows.blur", p.blur);
        Settings.set("windows.border", p.border);
    }

    readonly property real opacity: flat ? 1 : Math.max(0.2, Math.min(1, appearance.glass ?? 0.62))
    // у GNOME панели нейтрально-серые (Adwaita), цвет темы остаётся в акценте
    readonly property color base: flat ? (light ? "#FAFAFB" : "#242428")
                                       : Qt.rgba(current.rgb[0] / 255, current.rgb[1] / 255, current.rgb[2] / 255, 1)
    readonly property color glass: Qt.rgba(base.r, base.g, base.b, opacity)
    readonly property color glass2: flat ? (light ? "#FFFFFF" : "#303034")
                                         : Qt.rgba(base.r, base.g, base.b, Math.min(0.98, opacity + 0.14))
    readonly property color accent: /^#[0-9A-Fa-f]{6}$/.test(appearance.accent || "") ? appearance.accent : "#7C5CFF"

    readonly property color fg:    light ? "#17131F" : "#ECE9F7"
    readonly property color fg2:   light ? "#433E57" : "#C9C3E0"
    readonly property color fg3:   light ? "#5C576E" : "#A9A3C2"
    readonly property color line:  light ? Qt.rgba(0, 0, 0, flat ? 0.12 : 0.10) : Qt.rgba(1, 1, 1, flat ? 0.07 : liquid ? 0.16 : 0.10)
    readonly property color soft:  light ? Qt.rgba(0, 0, 0, 0.05) : Qt.rgba(1, 1, 1, 0.05)
    readonly property color soft2: light ? Qt.rgba(0, 0, 0, 0.09) : Qt.rgba(1, 1, 1, 0.10)
    readonly property color inv:   light ? "#FFFFFF" : "#140F26"

    // Текст и значки поверх цвета: на светлом (белый, пастельный акцент) —
    // тёмные, иначе белые. Яркость — относительная (sRGB, как в WCAG).
    function luminance(c) {
        const ch = v => v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
    }
    function onColor(c) { return luminance(c) > 0.5 ? "#17131F" : "#FFFFFF"; }
    readonly property bool accentLight: luminance(accent) > 0.5
    readonly property color onAccent: accentLight ? "#17131F" : "#FFFFFF"

    readonly property int radius: Math.max(0, Math.min(32, appearance.radius ?? 18))
    // Если шрифта нет, fontconfig может подставить что угодно (вплоть до курсива),
    // поэтому проверяем наличие и откатываемся на системный sans-serif.
    // Общий «sans-serif» у Qt может дать курсив на полужирном, поэтому
    // перечисляем шрифты, где точно есть все начертания.
    readonly property var families: Qt.fontFamilies()
    function pickFont(names) {
        for (const n of names) if (families.indexOf(n) !== -1) return n;
        return names[names.length - 1];
    }
    readonly property var sansFallback: ["Inter", "Adwaita Sans", "Noto Sans", "Cantarell", "Liberation Sans", "sans-serif"]
    readonly property string font: pickFont([appearance.font || "Inter"].concat(sansFallback))
    readonly property string fontDisplay: pickFont(["Inter Tight", font])
    readonly property string fontMono: pickFont(["JetBrains Mono", "Adwaita Mono", "Noto Sans Mono", "monospace"])

    // Анимации: длительности в мс и кривые, общие для всех модулей.
    readonly property QtObject anim: QtObject {
        readonly property int fast: 160
        readonly property int normal: 280
        readonly property int slow: 460
        // круг появляется у края
        readonly property int drop: 220
        // круг растягивается в панель
        readonly property int stretch: 420
        readonly property int outCurve: Easing.OutCubic
        readonly property int inOutCurve: Easing.InOutCubic
        readonly property int springCurve: Easing.OutBack
    }
}
