pragma Singleton

import QtQuick
import Quickshell

// Токены оформления Delta — те же, что в концепт-макете (--glass, --fg, …).
Singleton {
    id: root

    readonly property var themes: [
        { id: "midnight", name: "Полночь",       rgb: [20, 15, 38] },
        { id: "black",    name: "Чёрная",        rgb: [0, 0, 0] },
        { id: "white",    name: "Белая",         rgb: [247, 246, 251], light: true },
        { id: "sand",     name: "Светлый песок", rgb: [245, 238, 226], light: true },
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
        { id: "pine",     name: "Хвоя",          rgb: [18, 36, 14] }
    ]
    readonly property var accents: ["#7C5CFF", "#2BC4F0", "#E0567F", "#3FB37A", "#F09A2B", "#E5484D", "#4C7DFF", "#C9A227"]

    readonly property var appearance: Settings.s.appearance || {}
    readonly property var current: themes.find(t => t.id === appearance.theme) || themes[4]
    readonly property bool light: current.light === true

    readonly property real opacity: Math.max(0.2, Math.min(1, appearance.glass ?? 0.62))
    readonly property color base: Qt.rgba(current.rgb[0] / 255, current.rgb[1] / 255, current.rgb[2] / 255, 1)
    readonly property color glass: Qt.rgba(base.r, base.g, base.b, opacity)
    readonly property color glass2: Qt.rgba(base.r, base.g, base.b, Math.min(0.98, opacity + 0.14))
    readonly property color accent: /^#[0-9A-Fa-f]{6}$/.test(appearance.accent || "") ? appearance.accent : "#7C5CFF"

    readonly property color fg:    light ? "#17131F" : "#ECE9F7"
    readonly property color fg2:   light ? "#433E57" : "#C9C3E0"
    readonly property color fg3:   light ? "#5C576E" : "#A9A3C2"
    readonly property color line:  light ? Qt.rgba(0, 0, 0, 0.10) : Qt.rgba(1, 1, 1, 0.10)
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
