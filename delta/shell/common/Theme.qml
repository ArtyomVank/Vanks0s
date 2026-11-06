pragma Singleton

import QtQuick
import Quickshell
import "../wallpaper/media.js" as Media

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
        { id: "sky",      name: "Небо",          rgb: [230, 241, 252], light: true, accent: "#2F80ED" },
        // для всех стилей: цвета берутся из обоев, как в Android
        { id: "wallpaper",       name: "Цвет обоев",         rgb: root.rgbOf(root.wallBaseDark),  wall: true },
        { id: "wallpaper-light", name: "Цвет обоев, светлая", rgb: root.rgbOf(root.wallBaseLight), wall: true, light: true }
    ]
    function rgbOf(c) { return [Math.round(c.r * 255), Math.round(c.g * 255), Math.round(c.b * 255)]; }
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

    // Три уровня оформления (Настройки → Стили и темы):
    //   стиль — интерфейс: как разложены панели и какие у них кнопки
    //           (appearance.ui, Theme.uiStyles);
    //   тема  — материал панелей: стекло, сплошные, линза… (appearance.style,
    //           Theme.styles — ключ остался от старых версий);
    //   цвет  — цветокор: оттенок поверхностей и акцент (appearance.theme,
    //           Theme.themes).
    //
    // Темы (материал):
    //   delta  — тонированное стекло с размытием (как было);
    //   acrylic — акриловое стекло: дымка с размытием и светящийся контур
    //             (Contour), ползунки и переключатели светятся;
    //   gnome  — сплошные серые панели, как в GNOME (Adwaita), без прозрачности;
    //   liquid — жидкое стекло: линза — фон у края изгибается, тонкий блик (Sheen);
    //   material — Material You, как на Pixel: плотные панели, цвета от темы;
    //   nothing — как Nothing OS: чёрное и белое без оттенков, тонкие рамки,
    //             красный акцент, часы из точек.
    // preset — что ставится при выборе темы (дальше можно поменять самому).
    readonly property var styles: [
        { id: "delta",  name: "Delta",          note: "Тонированное стекло",
          preset: { glass: 0.62, frost: 0.5, radius: 18, rounding: 16, blur: true, border: 2, clock: "ios" } },
        { id: "acrylic", name: "Акриловое стекло", note: "Дымка и светящийся контур",
          preset: { glass: 0.46, frost: 0.7, radius: 26, rounding: 24, blur: true, border: 1, clock: "tall" } },
        { id: "liquid", name: "Жидкое стекло",  note: "Стекло-линза: фон у края изгибается",
          preset: { glass: 0.4, frost: 0.3, radius: 30, rounding: 24, blur: true, border: 1, clock: "tall" } },
        { id: "gnome",  name: "GNOME",          note: "Сплошные панели без прозрачности",
          preset: { glass: 1, radius: 12, rounding: 12, blur: false, border: 0, clock: "minimal" } },
        { id: "material", name: "Material You", note: "Цвета от темы, резкие пружинистые анимации",
          preset: { glass: 0.97, radius: 28, rounding: 22, blur: false, border: 0, clock: "stack" } },
        { id: "nothing", name: "Nothing", note: "Монохром, тонкие рамки, красный акцент и часы из точек",
          preset: { glass: 1, radius: 20, rounding: 16, blur: false, border: 1, clock: "dots", accent: "#D71921" } }
    ]
    readonly property string style: styles.some(x => x.id === appearance.style) ? appearance.style : "delta"
    readonly property bool flat: style === "gnome"
    readonly property bool liquid: style === "liquid"
    readonly property bool material: style === "material"
    readonly property bool nothing: style === "nothing"
    readonly property bool acrylic: style === "acrylic"
    // сессия на своём композиторе: стекло, линзу и анимации окон делает он
    readonly property bool ownCompositor: !!Quickshell.env("DELTA_COMPOSITOR")
    // выбрать тему: вместе с ней — прозрачность, скругления, размытие и рамка окон
    function applyStyle(id) {
        const st = styles.find(x => x.id === id);
        if (!st) return;
        const p = st.preset;
        Settings.set("appearance.style", id);
        Settings.set("appearance.glass", p.glass);
        if (p.frost !== undefined) Settings.set("appearance.frost", p.frost);
        Settings.set("appearance.radius", p.radius);
        Settings.set("windows.rounding", p.rounding);
        Settings.set("windows.blur", p.blur);
        Settings.set("windows.border", p.border);
        // часы у каждой темы свои; виджеты со своим видом (item.style) не меняются
        Settings.set("clock.style", p.clock);
        if (p.accent) Settings.set("appearance.accent", p.accent);
    }

    // Стили (интерфейс):
    //   delta   — как было: полоса сверху, плитки кнопок с подписями;
    //   acrylic — «Акрил»: сверху острова с чипами (док в режиме «Плитки»),
    //             круглые кнопки, толстые ползунки-капсулы, цифры
    //             моноширинным шрифтом.
    // theme — тема, которая подходит стилю: ставится, только если сейчас
    // стоит «своя» тема другого стиля (Delta ↔ акриловое стекло), остальные
    // темы (жидкое стекло, Nothing…) стиль не трогает.
    readonly property var uiStyles: [
        { id: "delta",   name: "Delta", note: "Полоса сверху, плитки с подписями", theme: "delta", top: "full" },
        { id: "acrylic", name: "Акрил", note: "Острова сверху, круглые кнопки, моноширинные цифры", theme: "acrylic", top: "tiles" }
    ]
    // до 1.8 «Акрил» был темой: у кого он выбран, тому и стиль «Акрил»
    readonly property string ui: uiStyles.some(x => x.id === appearance.ui) ? appearance.ui
        : appearance.style === "acrylic" ? "acrylic" : "delta"
    readonly property bool round: ui === "acrylic"
    function applyUi(id) {
        const u = uiStyles.find(x => x.id === id);
        if (!u) return;
        Settings.set("appearance.ui", id);
        Settings.set("docks.top.length", u.top);
        if (uiStyles.some(x => x.theme === style) && style !== u.theme) applyStyle(u.theme);
    }

    // Матовость (appearance.frost, 0…1) — сила размытия под панелями (её
    // задаёт delta-apply). У жидкого стекла от неё же и подложка: прозрачное —
    // едва тонировано, матовое — молочная дымка. У Delta подложку задаёт
    // прозрачность (appearance.glass), а матовость — только размытие.
    readonly property real frost: Math.max(0, Math.min(1, Number(appearance.frost ?? 0.5)))
    readonly property real opacity: flat || nothing ? 1
        : material ? 0.97
        : liquid ? 0.12 + 0.26 * frost
        : Math.max(0.2, Math.min(1, appearance.glass ?? 0.62))

    // ---- Цвета из обоев (темы «Цвет обоев») ----
    // Главный цвет обоев (ColorQuantizer, самый насыщенный из восьми) — от него
    // поверхности (тот же оттенок, почти без насыщенности) и акцент (тон 80 в
    // тёмной теме, 40 в светлой), как динамические цвета Android.
    readonly property string wallFile: {
        const w = Settings.s.wallpaper || {};
        const f = w.path || "";
        if (!f) return "";
        return Media.isVideo(f) || w.video === true ? (w.poster || "") : f;
    }
    readonly property bool wallTheme: current.wall === true
    property color wallSeed: "#7C5CFF"
    ColorQuantizer {
        source: root.wallTheme && root.wallFile ? Media.fileUrl(root.wallFile) : ""
        depth: 3
        rescaleSize: 96
        onColorsChanged: {
            let best = null, score = -1;
            for (const c of colors) {
                // насыщенный и не слишком тёмный/светлый
                const sc = c.hsvSaturation * (0.35 + c.hsvValue) * (c.hslLightness > 0.08 && c.hslLightness < 0.92 ? 1 : 0.2);
                if (sc > score) { score = sc; best = c; }
            }
            if (best) root.wallSeed = best;
        }
    }
    function satOf(c) { return Math.max(0.35, Math.min(0.9, c.hslSaturation)); }
    function hueOf(c) { return c.hslHue < 0 ? 0.72 : c.hslHue; }
    function surfaceOf(c, isLight) {
        return isLight ? Qt.hsla(hueOf(c), Math.min(satOf(c), 0.6) * 0.5, 0.94, 1)
                       : Qt.hsla(hueOf(c), Math.min(satOf(c), 0.5) * 0.42, 0.13, 1);
    }
    function toneOf(c, isLight) {
        return isLight ? Qt.hsla(hueOf(c), Math.max(0.5, satOf(c) * 0.8), 0.40, 1)
                       : Qt.hsla(hueOf(c), Math.max(0.55, satOf(c) * 0.85), 0.76, 1);
    }
    readonly property color wallBaseDark: surfaceOf(wallSeed, false)
    readonly property color wallBaseLight: surfaceOf(wallSeed, true)
    // акцент из обоев уходит и в настройки — рамки окон и GTK (delta-apply)
    // берут appearance.accent; с задержкой, чтобы смена обоев не дёргала
    // delta-apply на каждом промежуточном цвете
    readonly property color wallAccent: toneOf(wallSeed, light)
    onWallAccentChanged: if (wallTheme) accentSync.restart()
    onWallThemeChanged: if (wallTheme) accentSync.restart()
    Timer {
        id: accentSync
        interval: 1500
        onTriggered: {
            const hex = String(root.wallAccent).toUpperCase();
            // у Nothing акцент свой (красный), обои его не трогают
            if (root.wallTheme && !root.nothing && String(root.appearance.accent || "").toUpperCase() !== hex)
                Settings.set("appearance.accent", hex);
        }
    }

    // ---- Material You: цвета от выбранной темы ----
    // Оттенок поверхностей — от цвета темы (у серых тем он никакой, тогда от
    // акцента), акцент — тот же цвет в тоне 80 или 40. Обои ни при чём.
    readonly property color userAccent: /^#[0-9A-Fa-f]{6}$/.test(appearance.accent || "") ? appearance.accent : "#7C5CFF"
    readonly property color themeColor: Qt.rgba(current.rgb[0] / 255, current.rgb[1] / 255, current.rgb[2] / 255, 1)
    readonly property color seed: wallTheme ? wallSeed : themeColor.hsvSaturation > 0.18 ? themeColor : userAccent
    readonly property real seedHue: hueOf(seed)
    readonly property color materialBase: surfaceOf(seed, light)
    readonly property color materialAccent: toneOf(wallTheme ? wallSeed : userAccent, light)

    // цвет панелей «r,g,b» для программ GTK/Qt (theme-apply): у GNOME —
    // серый, у Material You — от темы
    readonly property string baseRgb: [base.r, base.g, base.b].map(v => Math.round(v * 255)).join(",")

    // у GNOME панели нейтрально-серые (Adwaita), цвет темы остаётся в акценте
    // у Nothing — чистые чёрный и белый, без оттенка темы
    readonly property color base: nothing ? (light ? "#F2F2F2" : "#0B0B0C")
                                : flat ? (light ? "#FAFAFB" : "#242428")
                                : material ? materialBase
                                : wallTheme ? (light ? wallBaseLight : wallBaseDark)
                                : themeColor
    readonly property color glass: Qt.rgba(base.r, base.g, base.b, opacity)
    readonly property color glass2: nothing ? (light ? "#FFFFFF" : "#1B1B1D")
                                  : flat ? (light ? "#FFFFFF" : "#303034")
                                  : material ? Qt.hsla(seedHue, base.hslSaturation, light ? 0.90 : 0.17, 1)
                                  : glowTiles ? Qt.rgba(base.r * 0.86 + accent.r * 0.14, base.g * 0.86 + accent.g * 0.14, base.b * 0.86 + accent.b * 0.14, Math.min(0.98, opacity + 0.14))
                                  : Qt.rgba(base.r, base.g, base.b, Math.min(0.98, opacity + 0.14))
    readonly property color accent: !nothing && (material || wallTheme) ? materialAccent : userAccent

    // Подсветка в стиле Delta (appearance.highlight): off · text — текст ярче и
    // со свечением акцента · tiles — плитки под текстом подкрашены акцентом.
    readonly property string highlight: style === "delta" ? (appearance.highlight || "off") : "off"
    readonly property bool glowText: highlight === "text"
    readonly property bool glowTiles: highlight === "tiles"
    readonly property color textGlow: Qt.rgba(accent.r, accent.g, accent.b, light ? 0.24 : 0.40)
    function tint(alpha) { return Qt.rgba(accent.r, accent.g, accent.b, alpha); }

    readonly property color fg:    nothing ? (light ? "#000000" : "#FFFFFF") : glowText ? (light ? "#0B0812" : "#FFFFFF") : light ? "#17131F" : "#ECE9F7"
    readonly property color fg2:   nothing ? (light ? "#3A3A3A" : "#C8C8C8") : glowText ? (light ? "#201B2E" : "#EDEAF8") : light ? "#433E57" : liquid ? "#E6E3F2" : "#C9C3E0"
    readonly property color fg3:   nothing ? (light ? "#6B6B6B" : "#8E8E8E") : glowText ? (light ? "#3A354A" : "#CFCAE4") : light ? "#5C576E" : liquid ? "#D2CEE3" : "#A9A3C2"
    readonly property color line:  nothing ? (light ? Qt.rgba(0, 0, 0, 0.16) : Qt.rgba(1, 1, 1, 0.16))
        : material ? "transparent"
        : glowTiles ? tint(light ? 0.45 : 0.38)
        : acrylic ? (light ? Qt.rgba(0, 0, 0, 0.08) : Qt.rgba(1, 1, 1, 0.12))
        : light ? Qt.rgba(0, 0, 0, flat ? 0.12 : 0.10) : Qt.rgba(1, 1, 1, flat ? 0.07 : liquid ? 0.16 : 0.10)
    readonly property color soft:  glowTiles ? tint(light ? 0.14 : 0.16)
        : light ? Qt.rgba(0, 0, 0, 0.05) : Qt.rgba(1, 1, 1, 0.05)
    readonly property color soft2: glowTiles ? tint(light ? 0.22 : 0.26)
        : light ? Qt.rgba(0, 0, 0, 0.09) : Qt.rgba(1, 1, 1, 0.10)
    readonly property color inv:   nothing ? (light ? "#FFFFFF" : "#000000") : light ? "#FFFFFF" : "#140F26"

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
    // цифры в доках и меню: у «Акрила» — моноширинные (часы, проценты, размеры)
    readonly property string fontNum: round ? pickFont(["Iosevka NF", "Iosevka", "JetBrains Mono", fontMono]) : font

    // Анимации: длительности в мс и кривые, общие для всех модулей.
    // k — «Скорость анимаций» (windows.animSpeed: 0.3, 0.5, 1, 2, 4; меньше —
    // быстрее): множитель всех длительностей оболочки (duration: N * Theme.anim.k)
    // и анимаций Hyprland (delta-apply).
    readonly property QtObject anim: QtObject {
        readonly property real k: {
            const v = Number(Settings.get("windows.animSpeed", 1));
            const speed = [0.3, 0.5, 1, 2, 4].indexOf(v) !== -1 ? v : 1;
            // Material 3 Expressive: движения короче и резче
            return root.material ? speed * 0.8 : speed;
        }
        // Анимация виджетов, меню и «Настроек» (docks/parts/Blob):
        // drop — капля из дока, spring — карточка выпрыгивает с пружиной,
        // fade — проявляется. auto: у Material You spring, у остальных drop.
        readonly property string panel: {
            const v = root.appearance.panelAnim;
            return v === "drop" || v === "spring" || v === "fade" ? v : root.material ? "spring" : "drop";
        }
        readonly property real panelK: {
            const v = Number(root.appearance.panelSpeed ?? 1);
            return v > 0 ? v : 1;
        }
        // Пружины Material 3 Expressive (androidx ExpressiveMotionTokens):
        // пространственные — с перелётом, эффекты (цвет, прозрачность) — без.
        readonly property var spatialFast: ({ stiffness: 800, damping: 2 * 0.6 * Math.sqrt(800) })
        readonly property var spatial: ({ stiffness: 380, damping: 2 * 0.8 * Math.sqrt(380) })
        readonly property var spatialSlow: ({ stiffness: 200, damping: 2 * 0.8 * Math.sqrt(200) })
        readonly property int fast: Math.round(160 * k)
        readonly property int normal: Math.round(280 * k)
        readonly property int slow: Math.round(460 * k)
        // круг появляется у края
        readonly property int drop: Math.round(220 * k)
        // круг растягивается в панель
        readonly property int stretch: Math.round(420 * k)
        // Emphasized из Material 3 ближе всего к OutExpo: резкий старт, долгий хвост
        readonly property int outCurve: root.material ? Easing.OutExpo : Easing.OutCubic
        readonly property int inOutCurve: Easing.InOutCubic
        readonly property int springCurve: Easing.OutBack
    }
}
