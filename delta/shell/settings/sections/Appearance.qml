pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.common
import qs.common.ui
import qs.settings
import qs.settings.parts

// Оформление: тема, акцент, стекло, скругления, шрифт, значки, курсор и
// перенос всего этого на приложения GTK/Qt (helpers/theme-apply).
ColumnLayout {
    id: root

    property string title: "Оформление"
    property string icon: "palette"
    property string keywords: "тема цвет акцент тёмная светлая прозрачность стекло скругление шрифт значки курсор gtk qt"
    spacing: 18

    readonly property var a: Settings.s.appearance || ({})
    property var iconThemes: []
    property var cursorThemes: []

    // --- тема ---
    Card {
        title: "Тема"

        Item {
            Layout.fillWidth: true
            implicitHeight: grid.implicitHeight + 24
            GridLayout {
                id: grid
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                columns: 8
                columnSpacing: 8
                rowSpacing: 8
                Repeater {
                    model: Theme.themes
                    delegate: Rectangle {
                        id: tile
                        required property var modelData
                        readonly property bool sel: Theme.current.id === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: 74
                        radius: 14
                        color: hov.hovered ? Theme.soft2 : "transparent"
                        border.width: 2
                        border.color: sel ? Theme.accent : Theme.line
                        Behavior on border.color { ColorAnimation { duration: Theme.anim.fast } }

                        Rectangle {
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 7 }
                            height: 38
                            radius: 9
                            color: Qt.rgba(tile.modelData.rgb[0] / 255, tile.modelData.rgb[1] / 255, tile.modelData.rgb[2] / 255, 1)
                            border.color: Qt.rgba(0.5, 0.5, 0.55, 0.35)
                            Rectangle { width: 12; height: 12; radius: 6; color: tile.modelData.accent || Theme.accent; anchors { right: parent.right; bottom: parent.bottom; margins: 6 } }
                            Sym { visible: tile.sel; anchors.centerIn: parent; name: "check"; size: 16; color: tile.modelData.light ? "#17131F" : "#ffffff" }
                        }
                        Label {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 8; rightMargin: 6; bottomMargin: 7 }
                            text: tile.modelData.name
                            size: "caption"
                            font.weight: Font.Bold
                        }
                        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.pickTheme(tile.modelData) }

                        // своя тема: при наведении — изменить и удалить
                        Row {
                            visible: tile.modelData.custom === true && hov.hovered
                            anchors { right: parent.right; top: parent.top; margins: 3 }
                            spacing: 3
                            z: 2
                            Repeater {
                                model: [{ icon: "edit", act: "edit" }, { icon: "close", act: "del" }]
                                delegate: Rectangle {
                                    id: mini
                                    required property var modelData
                                    width: 20; height: 20; radius: 10
                                    color: mini.modelData.act === "del" ? "#E5484D" : Theme.inv
                                    border.color: Theme.line
                                    Sym { anchors.centerIn: parent; name: mini.modelData.icon; size: 11; color: mini.modelData.act === "del" ? "#ffffff" : Theme.fg }
                                    TapHandler {
                                        onTapped: mini.modelData.act === "del" ? root.deleteTheme(tile.modelData.id) : themeDlg.openFor(tile.modelData)
                                    }
                                }
                            }
                        }
                    }
                }

                // создать свою тему
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 74
                    radius: 14
                    color: addHov.hovered ? Theme.soft2 : "transparent"
                    border.width: 2
                    border.color: Theme.line
                    Column {
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 30; height: 30; radius: 15
                            color: Theme.soft2
                            Sym { anchors.centerIn: parent; name: "plus"; size: 16 }
                        }
                        Label { anchors.horizontalCenter: parent.horizontalCenter; text: "Своя тема"; size: "caption"; font.weight: Font.Bold }
                    }
                    HoverHandler { id: addHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: themeDlg.openFor(null) }
                }
            }
        }
    }

    // --- темы: выбор, свои ---
    function pickTheme(t) {
        Settings.set("appearance.theme", t.id);
        // у готовых сочетаний и своих тем — свой акцент и стекло
        if (t.accent) Settings.set("appearance.accent", t.accent);
        if (t.glass !== undefined) Settings.set("appearance.glass", t.glass);
    }
    function hexOf(rgb) { return "#" + rgb.map(c => Math.round(c).toString(16).padStart(2, "0")).join("").toUpperCase(); }
    function rgbOf(hex) { const c = Qt.color(hex); return [Math.round(c.r * 255), Math.round(c.g * 255), Math.round(c.b * 255)]; }
    function saveTheme(t) {
        const list = Theme.customThemes.map(x => ({ id: x.id, name: x.name, rgb: x.rgb, light: x.light, accent: x.accent, glass: x.glass }));
        const i = list.findIndex(x => x.id === t.id);
        if (i >= 0) list[i] = t; else list.push(t);
        Settings.set("appearance.customThemes", list);
        pickTheme(t);
    }
    function deleteTheme(id) {
        const list = Theme.customThemes.filter(x => x.id !== id).map(x => ({ id: x.id, name: x.name, rgb: x.rgb, light: x.light, accent: x.accent, glass: x.glass }));
        Settings.set("appearance.customThemes", list);
        if (Theme.current.id === id) Settings.set("appearance.theme", "graphite");
        Nav.toast("Тема удалена");
    }

    Dialog {
        id: themeDlg
        title: editId ? "Изменить тему" : "Своя тема"
        subtitle: "Выберите цвет панелей и акцент — превью покажет, как это будет выглядеть"
        cardWidth: 460

        property string editId: ""
        property string base: "#1C2230"
        property string accentHex: "#7C5CFF"
        property real glass: 0.7
        readonly property bool isLight: Theme.luminance(Qt.color(base)) > 0.5
        readonly property color glassColor: { const c = Qt.color(base); return Qt.rgba(c.r, c.g, c.b, glass); }
        readonly property color ink: isLight ? "#17131F" : "#ECE9F7"

        function openFor(t) {
            editId = t ? t.id : "";
            base = t ? root.hexOf(t.rgb) : root.hexOf(Theme.current.rgb);
            accentHex = t && t.accent ? t.accent : String(Theme.accent).toUpperCase();
            glass = t && t.glass !== undefined ? t.glass : Theme.opacity;
            nameF.text = t ? t.name : "";
            open();
            nameF.focusInput();
        }
        function save() {
            const name = nameF.text.trim() || "Моя тема";
            root.saveTheme({ id: editId || "custom-" + Date.now().toString(36), name: name, rgb: root.rgbOf(base),
                             light: isLight, accent: accentHex, glass: Math.round(glass * 100) / 100 });
            close();
        }

        // превью: кусочек обоев, док и кнопка в цветах темы
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 120
            radius: 16
            clip: true
            gradient: Gradient {
                GradientStop { position: 0; color: "#3A4A6B" }
                GradientStop { position: 1; color: "#C98A6B" }
            }
            Rectangle {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
                width: 250; height: 50; radius: 25
                color: themeDlg.glassColor
                border.color: themeDlg.isLight ? Qt.rgba(0, 0, 0, 0.1) : Qt.rgba(1, 1, 1, 0.1)
                Row {
                    anchors.centerIn: parent
                    spacing: 10
                    Repeater {
                        model: 4
                        delegate: Rectangle {
                            required property int index
                            width: 30; height: 30; radius: 9
                            color: index === 0 ? themeDlg.accentHex : Qt.rgba(themeDlg.ink.r, themeDlg.ink.g, themeDlg.ink.b, 0.16)
                        }
                    }
                }
            }
            Rectangle {
                anchors { left: parent.left; top: parent.top; margins: 14 }
                width: 150; height: 40; radius: 12
                color: themeDlg.glassColor
                Label { anchors.centerIn: parent; text: "Привет!"; color: themeDlg.ink; font.weight: Font.DemiBold }
            }
            Rectangle {
                anchors { right: parent.right; top: parent.top; margins: 14 }
                width: 90; height: 32; radius: 16
                color: themeDlg.accentHex
                Label { anchors.centerIn: parent; text: "Кнопка"; color: Theme.onColor(Qt.color(themeDlg.accentHex)); size: "small"; font.weight: Font.DemiBold }
            }
        }

        Field { id: nameF; Layout.fillWidth: true; icon: "palette"; placeholder: "Название, например «Моя ночь»"; maxLength: 24; onAccepted: themeDlg.save() }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Repeater {
                model: [{ key: "base", label: "Панели" }, { key: "accent", label: "Акцент" }]
                delegate: Rectangle {
                    id: pick
                    required property var modelData
                    readonly property string hex: modelData.key === "base" ? themeDlg.base : themeDlg.accentHex
                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: 12
                    color: pickHov.hovered ? Theme.soft2 : Theme.soft
                    border.color: Theme.line
                    RowLayout {
                        anchors { fill: parent; margins: 10 }
                        spacing: 10
                        Rectangle { implicitWidth: 28; implicitHeight: 28; radius: 14; color: pick.hex; border.color: Qt.rgba(0.5, 0.5, 0.55, 0.4) }
                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            Label { Layout.fillWidth: true; text: pick.modelData.label; font.weight: Font.DemiBold }
                            Label { Layout.fillWidth: true; text: pick.hex; size: "caption"; tone: 3 }
                        }
                    }
                    HoverHandler { id: pickHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            themeColor.target = pick.modelData.key;
                            themeColor.title = pick.modelData.key === "base" ? "Цвет панелей" : "Акцент";
                            themeColor.subtitle = pick.modelData.key === "base" ? "Доки, меню и окна" : "Кнопки, выделение, рамка окна";
                            themeColor.openWith(pick.hex);
                        }
                    }
                }
            }
        }

        SliderRow {
            Layout.fillWidth: true
            icon: "eye"
            title: "Прозрачность панелей"
            from: 0.3; to: 1; step: 0.01
            value: themeDlg.glass
            format: v => Math.round(v * 100) + " %"
            onCommit: v => themeDlg.glass = v
        }

        buttons: [
            Btn { text: "Отмена"; onClicked: themeDlg.close() },
            Btn { text: themeDlg.editId ? "Сохранить" : "Создать тему"; kind: "accent"; onClicked: themeDlg.save() }
        ]
    }
    ColorDialog {
        id: themeColor
        property string target: "base"
        onPicked: hex => { if (target === "base") themeDlg.base = hex; else themeDlg.accentHex = hex; }
    }

    // --- цвет и стекло ---
    Card {
        title: "Цвет и стекло"

        SettingRow {
            icon: "palette"
            title: "Цвет оформления"
            subtitle: "Кнопки, выделение и рамка окна"
            RowLayout {
                spacing: 8
                Repeater {
                    model: Theme.accents
                    delegate: Rectangle {
                        id: sw
                        required property string modelData
                        readonly property bool sel: String(Theme.accent).toLowerCase() === modelData.toLowerCase()
                        implicitWidth: 26
                        implicitHeight: 26
                        radius: 13
                        color: modelData
                        // двойное кольцо выбранного цвета, как в концепте
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width + 8; height: width; radius: width / 2
                            color: "transparent"
                            border.width: 2
                            border.color: Theme.fg
                            visible: sw.sel
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Settings.set("appearance.accent", sw.modelData) }
                    }
                }
                // свой цвет
                Rectangle {
                    readonly property bool custom: Theme.accents.every(c => c.toLowerCase() !== String(Theme.accent).toLowerCase())
                    implicitWidth: 26
                    implicitHeight: 26
                    radius: 13
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#ff5e5e" }
                        GradientStop { position: 0.5; color: "#5effa0" }
                        GradientStop { position: 1; color: "#5e8bff" }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 14; height: 14; radius: 7
                        color: parent.custom ? Theme.accent : Theme.inv
                        Sym { anchors.centerIn: parent; visible: !parent.parent.custom; name: "plus"; size: 12; color: Theme.fg }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 8; height: width; radius: width / 2
                        color: "transparent"; border.width: 2; border.color: Theme.fg
                        visible: parent.custom
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: colorDlg.openWith(Theme.accent) }
                }
            }
        }

        SliderRow {
            icon: "eye"
            title: "Непрозрачность доков и окон"
            subtitle: "Меньше — сквозь панели больше видно обои"
            from: 0.2; to: 0.98; step: 0.01
            value: Theme.opacity
            live: true
            format: v => Math.round(v * 100) + " %"
            onCommit: v => Settings.set("appearance.glass", Math.round(v * 100) / 100)
        }

        SliderRow {
            icon: "grid"
            title: "Скругление углов"
            subtitle: "Доки, меню и карточки"
            from: 0; to: 32; step: 1
            value: Theme.radius
            unit: " px"
            live: true
            onCommit: v => Settings.set("appearance.radius", Math.round(v))
        }

        SettingRow {
            icon: "font"
            title: "Шрифт"
            subtitle: Theme.font === (root.a.font || "Inter") ? "Интерфейс Delta и приложения GTK/Qt" : "«" + (root.a.font || "") + "» не найден, используется " + Theme.font
            Select {
                text: Theme.font
                onClicked: fontPicker.openWith()
            }
        }
    }

    // --- значки и курсор ---
    Card {
        title: "Значки и курсор"

        SettingRow {
            icon: "apps"
            title: "Значки приложений"
            subtitle: root.iconThemes.length ? "Тема значков для доков, меню и приложений" : "Темы значков не найдены"
            Select {
                text: root.title2(root.iconThemes, root.a.iconTheme || "Papirus-Dark")
                enabled: root.iconThemes.length > 0
                onClicked: iconPicker.openWith()
            }
        }
        SettingRow {
            icon: "cursor"
            title: "Курсор"
            Select {
                text: root.title2(root.cursorThemes, root.a.cursorTheme || "Adwaita")
                enabled: root.cursorThemes.length > 0
                onClicked: cursorPicker.openWith()
            }
        }
        SettingRow {
            icon: "scale"
            title: "Размер курсора"
            Chips {
                model: [24, 32, 40, 48, 64].map(n => ({ value: n, label: String(n) }))
                current: root.a.cursorSize ?? 24
                onPicked: v => Settings.set("appearance.cursorSize", v)
            }
        }
    }

    // --- приложения ---
    Card {
        title: "Приложения"

        SettingRow {
            icon: "windows"
            title: "Применять к приложениям GTK и Qt"
            subtitle: "Программы будут в тех же цветах, что и Delta"
            Toggle {
                checked: root.a.applyApps ?? true
                onToggled: v => Settings.set("appearance.applyApps", v)
            }
        }
        SettingRow {
            icon: "refresh"
            title: "Применить сейчас"
            subtitle: root.applyState
            Btn { text: "Применить"; enabled: !root.applying; onClicked: root.applyApps() }
        }
    }

    // ---------------------------------------------------------------- логика

    function title2(list, name) {
        const t = list.find(x => x.value === name);
        return t ? t.label : name;
    }

    property bool applying: false
    property string applyState: "Программы подхватят изменения при следующем запуске, многие — сразу"

    function applyApps() {
        const t = Theme.current;
        applying = true;
        Exec.run(["bash", Exec.helper("theme-apply"),
                  "--scheme", Theme.light ? "light" : "dark",
                  "--icons", a.iconTheme || "Papirus-Dark",
                  "--cursor", a.cursorTheme || "Adwaita",
                  "--cursor-size", String(a.cursorSize ?? 24),
                  "--accent", String(Theme.accent),
                  "--base", t.rgb.join(","),
                  "--font", Theme.font], {
            label: "оформление для GTK/Qt",
            selfDry: true,
            toast: false,
            done: (code, out, err) => {
                applying = false;
                if (out.length) console.info("[delta-settings] theme-apply:\n" + out.trim());
                applyState = code === 0 ? (Exec.dryRun ? "Пробный режим: команды записаны в журнал" : "Применено к приложениям")
                                        : "Не удалось: " + (err.trim() || ("код " + code));
            }
        });
    }

    // Сами изменения переносит на приложения оболочка (appearance/ThemeSync):
    // она видит их, даже если «Настройки» закрыты. Здесь — только кнопка.

    Process {
        running: true
        command: ["bash", Exec.helper("list-themes")]
        stdout: StdioCollector {
            onStreamFinished: {
                const icons = [], cursors = [];
                for (const line of text.split("\n")) {
                    const p = line.split("\t");
                    if (p.length < 3) continue;
                    const item = { value: p[1], label: p[2], sub: p[2] !== p[1] ? p[1] : "" };
                    (p[0] === "cursor" ? cursors : icons).push(item);
                }
                const by = (x, y) => x.label.localeCompare(y.label);
                root.iconThemes = icons.sort(by);
                root.cursorThemes = cursors.sort(by);
            }
        }
    }

    ColorDialog { id: colorDlg; onPicked: hex => Settings.set("appearance.accent", hex) }

    Picker {
        id: fontPicker
        title: "Шрифт интерфейса"
        searchHint: "Название шрифта"
        current: Theme.font
        model: Theme.families.filter(f => !/^(Noto Color Emoji|.*Symbols?|.*Emoji.*|Cursor|D050000L)$/.test(f))
                             .map(f => ({ value: f, label: f, font: f }))
        onPicked: v => Settings.set("appearance.font", v)
    }
    Picker {
        id: iconPicker
        title: "Тема значков"
        current: root.a.iconTheme || "Papirus-Dark"
        model: root.iconThemes
        onPicked: v => Settings.set("appearance.iconTheme", v)
    }
    Picker {
        id: cursorPicker
        title: "Тема курсора"
        current: root.a.cursorTheme || "Adwaita"
        model: root.cursorThemes
        onPicked: v => Settings.set("appearance.cursorTheme", v)
    }

    Connections {
        target: Nav
        function onAction(name, arg) {
            if (name === "appearance.color") colorDlg.openWith(arg || Theme.accent);
            else if (name === "appearance.font") fontPicker.openWith(arg);
            else if (name === "appearance.newTheme") themeDlg.openFor(null);
            else if (name === "appearance.icons") iconPicker.openWith(arg);
            else if (name === "appearance.apply") root.applyApps();
        }
    }
}
