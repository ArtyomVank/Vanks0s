pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.display
import qs.display.parts
import "../../display/layout.js" as L

// Раздел «Экран»: расположение, режим, масштаб, поворот, VRR, HDR, повтор,
// яркость и ночной свет.
//
// Параметры мониторов сначала копятся в черновике (draft) и применяются
// кнопкой «Применить»: на лету, с окном «Оставить?» и откатом через 15 с
// (Displays.apply). Яркость, основной экран и ночной свет меняются сразу.
ColumnLayout {
    id: page

    property string title: I18n.tr("Экран")
    property string icon: "monitor"
    property string keywords: "монитор разрешение частота масштаб поворот расположение основной hdr vrr 10 бит icc зеркало яркость ночной свет"

    spacing: 18

    property var base: ({})
    property var draft: ({})
    property string selected: ""
    readonly property bool dirty: JSON.stringify(draft) !== JSON.stringify(base)

    readonly property var mon: Displays.monitors.find(m => m.name === selected) || null
    readonly property var cfg: draft[selected] || null

    function clone(v) { return JSON.parse(JSON.stringify(v)); }
    function shortName(m) { return m.model || m.name; }

    // черновик заново из текущего состояния (после применения, отката, подключения)
    function reload() {
        base = Displays.configs();
        draft = clone(base);
        if (!draft[selected]) selected = Displays.primaryName || (Displays.monitors.length ? Displays.monitors[0].name : "");
    }
    property string knownNames: ""
    Connections {
        target: Displays
        function onMonitorsChanged() {
            const names = Displays.monitors.map(m => m.name).sort().join(",");
            // правки пользователя не теряем из-за постороннего обновления
            if (!page.dirty || Displays.pending || names !== page.knownNames) page.reload();
            page.knownNames = names;
        }
    }
    // Hyprland не шлёт событий, когда правило монитора меняют через eval или
    // hyprctl reload без смены набора, поэтому, пока раздел виден, изредка опрашиваем.
    Timer { interval: 4000; running: page.visible && !Displays.pending; repeat: true; onTriggered: Displays.refresh() }
    Component.onCompleted: { knownNames = Displays.monitors.map(m => m.name).sort().join(","); reload(); }

    // --- правка черновика --------------------------------------------------

    function shown(d) { return Object.keys(d).filter(n => d[n].enabled && !d[n].mirror); }
    function rectsOf(d) {
        return shown(d).map(n => {
            const s = L.logicalSize(d[n]);
            return { name: n, x: d[n].x, y: d[n].y, w: s.w, h: s.h };
        });
    }
    function writeBack(d, rects) {
        for (const r of rects) { d[r.name].x = r.x; d[r.name].y = r.y; }
        return d;
    }

    function edit(name, patch) {
        const d = clone(draft);
        if (!d[name]) return;
        const before = d[name];
        const was = L.logicalSize(before);
        const wasShown = before.enabled && !before.mirror;
        Object.assign(d[name], patch);
        const c = d[name];
        if (patch.mode) c.scale = L.nearestScale(L.validScales(c.mode.w, c.mode.h), c.scale);
        if (patch.hdr === true) c.tenBit = true;
        // экран выключили или он стал повтором — те, кто повторял его, тоже повторяют уже нечто невидимое
        if (patch.enabled === false || patch.mirror)
            for (const n in d) if (d[n].mirror === name) d[n].mirror = "";

        const isShown = c.enabled && !c.mirror;
        const now = L.logicalSize(c);
        let rects = rectsOf(d);
        if (isShown && wasShown && (now.w !== was.w || now.h !== was.h)) {
            rects = L.resized(rects, name, was.w, was.h);
        } else if (isShown !== wasShown) {
            // появившийся экран приставляем к остальным, исчезнувший — убираем разрыв
            const anchor = shown(d).find(n => n !== name && n === Displays.primaryName) || shown(d).find(n => n !== name) || name;
            rects = L.fixup(rects, anchor, 0);
        }
        draft = writeBack(d, rects);
    }

    function dropAt(name, x, y) {
        const d = clone(draft);
        draft = writeBack(d, L.drop(rectsOf(d), name, x, y, arrange.snap));
    }

    function apply() {
        if (!dirty) return;
        Displays.apply(draft, base);
    }
    // для проверки через IPC (dev-display)
    function openResolution() { resDrop.open(); }
    function reset() { draft = clone(base); Displays.error = ""; }

    // --- данные для элементов ---------------------------------------------

    readonly property var resolutionModel: {
        if (!mon) return [];
        const pref = mon.modes.length ? mon.modes[0] : null;
        return L.resolutions(mon.modes).map(r => ({
            value: r.w + "x" + r.h,
            label: r.w + " × " + r.h,
            hint: pref && pref.w === r.w && pref.h === r.h ? "родное" : aspect(r.w, r.h)
        }));
    }
    function aspect(w, h) {
        const g = (a, b) => b ? g(b, a % b) : a;
        const d = g(w, h);
        const a = w / d + ":" + h / d;
        return ({ "16:9": "16:9", "16:10": "16:10", "8:5": "16:10", "4:3": "4:3", "5:4": "5:4", "64:27": "21:9", "43:18": "21:9", "12:5": "21:9", "32:9": "32:9", "3:2": "3:2" })[a] || "";
    }
    readonly property var rateModel: cfg && mon ? L.rates(mon.modes, cfg.mode.w, cfg.mode.h).map(hz => ({ value: hz, label: L.hzLabel(hz) })) : []
    readonly property var scaleModel: cfg ? L.validScales(cfg.mode.w, cfg.mode.h).map(s => ({ value: s, label: L.scaleLabel(s) })) : []
    readonly property var logical: cfg ? L.logicalSize(cfg) : ({ w: 0, h: 0 })
    readonly property var mirrorModel: {
        const out = [{ value: "", label: I18n.tr("Нет") }];
        for (const m of Displays.monitors) {
            const c = draft[m.name];
            if (m.name === selected || !c || !c.enabled || c.mirror) continue;
            out.push({ value: m.name, label: shortName(m), hint: m.name });
        }
        return out;
    }
    readonly property bool lastShown: cfg !== null && cfg.enabled && !cfg.mirror && shown(draft).length === 1
    readonly property var canvasRects: {
        const out = [];
        for (const r of rectsOf(draft)) {
            const m = Displays.byName(r.name);
            const c = draft[r.name];
            out.push(Object.assign(r, {
                title: m ? shortName(m) : r.name,
                sub: c.mode.w + "×" + c.mode.h + (c.scale !== 1 ? " · " + L.scaleLabel(c.scale) : ""),
                primary: r.name === Displays.primaryName
            }));
        }
        return out;
    }
    // выключенные и повторяющие экраны на холсте не видны — перечисляем под ним
    readonly property var hiddenNote: {
        const parts = [];
        for (const m of Displays.monitors) {
            const c = draft[m.name];
            if (!c) continue;
            if (!c.enabled) parts.push(shortName(m) + " выключен");
            else if (c.mirror) parts.push(shortName(m) + " повторяет " + (Displays.byName(c.mirror) ? shortName(Displays.byName(c.mirror)) : c.mirror));
        }
        return parts.join(" · ");
    }

    // --- расположение ----------------------------------------------------------

    Card {
        title: I18n.tr("Расположение")

        Item {
            Layout.fillWidth: true
            implicitHeight: col.implicitHeight + 28

            ColumnLayout {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 12

                Chips {
                    visible: Displays.monitors.length > 1
                    Layout.fillWidth: true
                    model: Displays.monitors.map(m => ({ value: m.name, label: page.shortName(m) }))
                    current: page.selected
                    onPicked: v => page.selected = v
                }

                Arrangement {
                    id: arrange
                    Layout.fillWidth: true
                    implicitHeight: Displays.monitors.length > 1 ? 250 : 190
                    rects: page.canvasRects
                    selected: page.selected
                    onSelect: name => page.selected = name
                    onDropped: (name, x, y) => page.dropAt(name, x, y)
                }

                Label {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: page.hiddenNote
                    size: "small"
                    tone: 3
                    wrapMode: Text.WordWrap
                }
                Label {
                    Layout.fillWidth: true
                    visible: Displays.monitors.length > 1
                    text: I18n.tr("Перетащите мониторы так, как они стоят на столе. Значок дока — основной экран.")
                    size: "small"
                    tone: 3
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // --- применить / сбросить ---------------------------------------------------

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: bar.implicitHeight + 20
        radius: Theme.radius - 4
        color: page.dirty ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12) : Theme.soft
        border.width: 1
        border.color: page.dirty ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : Theme.line
        Behavior on color { ColorAnimation { duration: Theme.anim.fast } }

        RowLayout {
            id: bar
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 10 }
            spacing: 8
            Sym {
                name: Displays.error ? "warning" : page.dirty ? "edit" : "check"
                size: 18
                color: Displays.error ? "#ff6b6b" : page.dirty ? Theme.accent : Theme.fg3
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Displays.error ? Displays.error
                    : Displays.pending ? "Ждём подтверждения…"
                    : page.dirty ? "Есть изменения. После применения будет 15 секунд, чтобы их отменить."
                    : "Параметры мониторов сохранены"
                size: "small"
                tone: page.dirty || Displays.error ? 1 : 3
            }
            Btn { text: I18n.tr("Сбросить"); kind: "ghost"; enabled: page.dirty && !Displays.pending; onClicked: page.reset() }
            Btn { text: I18n.tr("Применить"); kind: "accent"; enabled: page.dirty && !Displays.pending; onClicked: page.apply() }
        }
    }

    // --- выбранный монитор ------------------------------------------------------

    Card {
        visible: page.cfg !== null
        title: page.mon ? (page.mon.description || page.mon.name) : ""

        SettingRow {
            icon: "power"
            title: I18n.tr("Включён")
            subtitle: page.lastShown ? "Единственный работающий экран выключить нельзя" : page.mon ? page.mon.name : ""
            Toggle {
                checked: page.cfg ? page.cfg.enabled : false
                enabled: page.cfg !== null && (!page.cfg.enabled || !page.lastShown)
                onToggled: v => page.edit(page.selected, { enabled: v })
            }
        }

        Maybe {
            show: page.cfg !== null && page.cfg.enabled
            SettingRow {
                icon: "dock"
                title: I18n.tr("Основной экран")
                subtitle: Displays.primaryName === page.selected ? "Доки и уведомления — на этом экране" : "Доки показываются на основном экране"
                Btn {
                    text: Displays.primaryName === page.selected ? "Основной" : "Сделать основным"
                    active: Displays.primaryName === page.selected
                    enabled: Displays.primaryName !== page.selected && page.cfg !== null && !page.cfg.mirror
                    onClicked: Displays.setPrimary(page.selected)
                }
            }
        }

        Maybe {
            show: Brightness.has(page.selected) && page.cfg !== null && page.cfg.enabled
            SettingRow {
                icon: "sun"
                title: I18n.tr("Яркость")
                subtitle: Brightness.devices[page.selected] && Brightness.devices[page.selected].kind === "ddc"
                    ? "Через DDC/CI — монитор применяет с небольшой задержкой" : ""
                wide: true
                Slider {
                    value: Brightness.valueFor(page.selected)
                    onMoved: v => Brightness.setFor(page.selected, v)
                }
            }
        }

        Maybe {
            show: page.cfg !== null && page.cfg.enabled && !page.cfg.mirror
            SettingRow {
                icon: "monitor"
                title: I18n.tr("Разрешение")
                Dropdown {
                    id: resDrop
                    model: page.resolutionModel
                    current: page.cfg ? page.cfg.mode.w + "x" + page.cfg.mode.h : ""
                    onPicked: v => {
                        const p = v.split("x"), w = parseInt(p[0]), h = parseInt(p[1]);
                        const rs = L.rates(page.mon.modes, w, h);
                        const hz = rs.find(r => Math.abs(r - page.cfg.mode.hz) < 0.5) ?? rs[0];
                        page.edit(page.selected, { mode: { w: w, h: h, hz: hz } });
                    }
                }
            }
        }

        Maybe {
            show: page.cfg !== null && page.cfg.enabled && !page.cfg.mirror && page.rateModel.length > 0
            SettingRow {
                icon: "refresh-rate"
                title: I18n.tr("Частота обновления")
                wide: true
                Chips {
                    model: page.rateModel
                    current: page.cfg ? page.cfg.mode.hz : 0
                    onPicked: v => page.edit(page.selected, { mode: { w: page.cfg.mode.w, h: page.cfg.mode.h, hz: v } })
                }
            }
        }

        Maybe {
            show: page.cfg !== null && page.cfg.enabled && !page.cfg.mirror
            SettingRow {
                icon: "scale"
                title: I18n.tr("Масштаб")
                subtitle: I18n.tr("Всё на экране будет как при ") + page.logical.w + " × " + page.logical.h
                wide: true
                Chips {
                    model: page.scaleModel
                    current: page.cfg ? page.cfg.scale : 1
                    onPicked: v => page.edit(page.selected, { scale: v })
                }
            }
        }

        Maybe {
            show: page.cfg !== null && page.cfg.enabled && !page.cfg.mirror
            SettingRow {
                icon: "rotate"
                title: I18n.tr("Поворот")
                wide: true
                RowLayout {
                    spacing: 14
                    Chips {
                        model: [{ value: 0, label: "0°" }, { value: 1, label: "90°" }, { value: 2, label: "180°" }, { value: 3, label: "270°" }]
                        current: page.cfg ? page.cfg.transform % 4 : 0
                        onPicked: v => page.edit(page.selected, { transform: v + (page.cfg.transform >= 4 ? 4 : 0) })
                    }
                    Item { Layout.fillWidth: true }
                    Label { text: I18n.tr("Отразить"); size: "small"; tone: 2 }
                    Toggle {
                        checked: page.cfg ? page.cfg.transform >= 4 : false
                        onToggled: v => page.edit(page.selected, { transform: page.cfg.transform % 4 + (v ? 4 : 0) })
                    }
                }
            }
        }

        Maybe {
            show: page.cfg !== null && page.cfg.enabled && !page.cfg.mirror
            SettingRow {
                icon: "refresh-rate"
                title: I18n.tr("Переменная частота (VRR)")
                subtitle: I18n.tr("Игры идут плавнее, без разрывов картинки. Нужен монитор с FreeSync или G-Sync")
                wide: true
                Chips {
                    model: [{ value: 0, label: I18n.tr("Выкл") }, { value: 1, label: I18n.tr("Вкл") }, { value: 2, label: I18n.tr("Только полноэкранные") }, { value: 3, label: I18n.tr("Игры и видео") }]
                    current: page.cfg ? page.cfg.vrr : 0
                    onPicked: v => page.edit(page.selected, { vrr: v })
                }
            }
        }

        Maybe {
            show: page.cfg !== null && page.cfg.enabled && page.mirrorModel.length > 1
            SettingRow {
                icon: "windows"
                title: I18n.tr("Повторять экран")
                subtitle: page.cfg && page.cfg.mirror ? "Показывает то же, что и выбранный монитор" : "Показывать то же изображение, что на другом мониторе"
                Dropdown {
                    model: page.mirrorModel
                    current: page.cfg ? page.cfg.mirror : ""
                    onPicked: v => page.edit(page.selected, { mirror: v })
                }
            }
        }
    }

    // --- цвет и HDR ---------------------------------------------------------------

    Card {
        visible: page.cfg !== null && page.cfg.enabled && !page.cfg.mirror
        title: I18n.tr("Цвет")

        Maybe {
            show: page.mon !== null && page.mon.hdr.hdr
            SettingRow {
                icon: "hdr"
                title: "HDR"
                subtitle: page.mon && page.mon.hdr.maxLuminance > 0 ? "Монитор заявляет яркость до " + page.mon.hdr.maxLuminance + " кд/м²" : "Монитор поддерживает HDR"
                Toggle {
                    checked: page.cfg ? page.cfg.hdr : false
                    onToggled: v => page.edit(page.selected, { hdr: v })
                }
            }
        }
        Maybe {
            show: page.cfg !== null && page.cfg.hdr
            Note {
                kind: "warn"
                text: I18n.tr("HDR в Hyprland пока экспериментальный: возможны неверные цвета и мерцание. 10 бит на канал ломают часть программ записи экрана.")
            }
        }
        Maybe {
            show: page.cfg !== null && page.cfg.hdr
            SettingRow {
                icon: "sun"
                title: I18n.tr("Яркость обычной картинки: ") + (page.cfg ? Math.round(page.cfg.sdrBrightness * 100) : 100) + " %"
                subtitle: I18n.tr("Как выглядят окна и рабочий стол в режиме HDR")
                wide: true
                Slider {
                    from: 0.5; to: 2; step: 0.05
                    value: page.cfg ? page.cfg.sdrBrightness : 1
                    onMoved: v => page.edit(page.selected, { sdrBrightness: Math.round(v * 100) / 100 })
                }
            }
        }
        Maybe {
            show: page.cfg !== null && page.cfg.hdr
            SettingRow {
                icon: "palette"
                title: I18n.tr("Насыщенность обычной картинки: ") + (page.cfg ? Math.round(page.cfg.sdrSaturation * 100) : 100) + " %"
                wide: true
                Slider {
                    from: 0.5; to: 1.5; step: 0.05
                    value: page.cfg ? page.cfg.sdrSaturation : 1
                    onMoved: v => page.edit(page.selected, { sdrSaturation: Math.round(v * 100) / 100 })
                }
            }
        }
        Maybe {
            show: Displays.anyHdr
            SettingRow {
                icon: "hdr"
                title: I18n.tr("Авто-HDR в полноэкранных играх")
                subtitle: I18n.tr("HDR включается сам, когда вы запускаете игру или видео в HDR")
                Toggle {
                    checked: Settings.get("display.autoHdr", false) === true
                    onToggled: v => Displays.setAutoHdr(v)
                }
            }
        }

        SettingRow {
            icon: "palette"
            title: I18n.tr("10 бит на канал")
            subtitle: page.cfg && page.cfg.hdr ? "В режиме HDR всегда включено" : "Плавнее градиенты. Может сломать запись экрана в части программ"
            Toggle {
                checked: page.cfg ? page.cfg.tenBit : false
                enabled: page.cfg !== null && !page.cfg.hdr
                onToggled: v => page.edit(page.selected, { tenBit: v })
            }
        }
        Maybe {
            show: page.cfg !== null && !page.cfg.hdr
            SettingRow {
                icon: "palette"
                title: I18n.tr("Цветовой охват")
                subtitle: page.cfg && page.cfg.cm === "wide" ? "BT.2020 — только для мониторов с широким охватом" : page.cfg && page.cfg.cm === "edid" ? "Основные цвета из EDID — бывают неточными" : "sRGB подходит почти всем мониторам"
                wide: true
                Chips {
                    model: [{ value: "srgb", label: "sRGB" }, { value: "auto", label: I18n.tr("Авто") }, { value: "wide", label: I18n.tr("Широкий") }, { value: "edid", label: I18n.tr("Из EDID") }]
                    current: page.cfg ? page.cfg.cm : "srgb"
                    onPicked: v => page.edit(page.selected, { cm: v })
                }
            }
        }
        SettingRow {
            icon: "file"
            title: I18n.tr("Цветовой профиль (ICC)")
            subtitle: page.cfg && page.cfg.hdr && page.cfg.icc ? "С HDR профиль не используется" : "Полный путь к файлу .icc или .icm; пусто — без профиля"
            wide: true
            RowLayout {
                spacing: 8
                TextField {
                    Layout.fillWidth: true
                    mono: true
                    text: page.cfg ? page.cfg.icc : ""
                    placeholder: I18n.tr("/usr/share/color/icc/монитор.icc")
                    invalid: text.length > 0 && !text.startsWith("/")
                    onEdited: v => page.edit(page.selected, { icc: v.trim() })
                }
                Btn {
                    icon: "close"
                    visible: page.cfg !== null && page.cfg.icc.length > 0
                    onClicked: page.edit(page.selected, { icc: "" })
                }
            }
        }
    }

    // --- ночной свет ----------------------------------------------------------------

    Card {
        title: I18n.tr("Ночной свет")

        Maybe {
            show: NightLight.checked && !NightLight.usable
            Note {
                kind: "info"
                text: I18n.tr("Для ночного света нужна программа hyprsunset — её нет в системе. Установите пакет hyprsunset: он делает цвета теплее и не попадает на снимки и записи экрана.")
            }
        }
        SettingRow {
            icon: "night-light"
            title: I18n.tr("Ночной свет")
            subtitle: !NightLight.usable ? "Недоступно без hyprsunset"
                : !NightLight.enabled ? "Тёплые цвета вечером — меньше нагрузка на глаза"
                : NightLight.active ? "Сейчас включён" : "Включится по расписанию"
            Toggle {
                checked: NightLight.enabled
                enabled: NightLight.usable
                onToggled: v => Settings.set("display.nightLight.enabled", v)
            }
        }
        SettingRow {
            icon: "thermometer"
            title: I18n.tr("Теплота: ") + NightLight.temperature + " K"
            subtitle: I18n.tr("Левее — теплее, глазам спокойнее")
            wide: true
            Slider {
                enabled: NightLight.usable
                from: 2500; to: 6000; step: 100
                value: NightLight.temperature
                onMoved: v => Settings.set("display.nightLight.temperature", Math.round(v))
            }
        }
        SettingRow {
            icon: "clock"
            title: I18n.tr("Расписание")
            subtitle: NightLight.schedule === "sun"
                ? (NightLight.sunToday
                    ? "Сегодня закат в " + NightLight.fmt(NightLight.sunToday.sunset) + ", рассвет в " + NightLight.fmt(NightLight.sunToday.sunrise)
                      + (NightLight.location && NightLight.location.source === "zone" ? " (по часовому поясу " + NightLight.zone + ")" : "")
                    : "Координаты неизвестны — с 20:00 до 07:00")
                : NightLight.schedule === "time" ? "Каждый день в заданные часы" : "Пока ночной свет включён"
            wide: true
            RowLayout {
                spacing: 8
                Chips {
                    model: [{ value: "sun", label: I18n.tr("Закат — рассвет") }, { value: "time", label: I18n.tr("По времени") }, { value: "always", label: I18n.tr("Всегда") }]
                    current: NightLight.schedule
                    onPicked: v => { if (NightLight.usable) Settings.set("display.nightLight.schedule", v); }
                }
                Item { Layout.fillWidth: true }
                // часы — только для «По времени»
                RowLayout {
                    visible: NightLight.schedule === "time"
                    spacing: 6
                    Label { text: I18n.tr("с"); tone: 2 }
                    TextField {
                        implicitWidth: 70
                        enabled: NightLight.usable
                        text: NightLight.from
                        invalid: !/^\d{1,2}:\d{2}$/.test(text)
                        onEdited: v => { if (/^\d{1,2}:\d{2}$/.test(v.trim())) Settings.set("display.nightLight.from", v.trim()); }
                    }
                    Label { text: I18n.tr("до"); tone: 2 }
                    TextField {
                        implicitWidth: 70
                        enabled: NightLight.usable
                        text: NightLight.to
                        invalid: !/^\d{1,2}:\d{2}$/.test(text)
                        onEdited: v => { if (/^\d{1,2}:\d{2}$/.test(v.trim())) Settings.set("display.nightLight.to", v.trim()); }
                    }
                }
            }
        }
    }
}
