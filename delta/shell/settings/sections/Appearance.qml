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
        title: "Тема — цвет доков, меню и окон"

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
                            Rectangle { width: 12; height: 12; radius: 6; color: Theme.accent; anchors { right: parent.right; bottom: parent.bottom; margins: 6 } }
                            Sym { visible: tile.sel; anchors.centerIn: parent; name: "check"; size: 16; color: tile.modelData.light ? "#17131F" : "#ffffff" }
                        }
                        Label {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 8; rightMargin: 6; bottomMargin: 7 }
                            text: tile.modelData.name
                            size: "caption"
                            font.weight: Font.Bold
                        }
                        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Settings.set("appearance.theme", tile.modelData.id) }
                    }
                }
            }
        }
    }

    // --- цвет и стекло ---
    Card {
        title: "Цвет и стекло"

        SettingRow {
            icon: "palette"
            title: "Цвет оформления"
            subtitle: "Капли, кнопки, выделение, рамка активного окна"
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
            subtitle: "Чем меньше, тем больше видно обои сквозь панели"
            from: 0.2; to: 0.98; step: 0.01
            value: Theme.opacity
            live: true
            format: v => Math.round(v * 100) + " %"
            onCommit: v => Settings.set("appearance.glass", Math.round(v * 100) / 100)
        }

        SliderRow {
            icon: "grid"
            title: "Скругление углов"
            subtitle: "Доки, меню, карточки. Углы окон приложений — в разделе «Окна»"
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
            subtitle: "Тёмная или светлая схема, акцент, значки, курсор и шрифт в программах (adw-gtk3, qt6ct)"
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
            else if (name === "appearance.icons") iconPicker.openWith(arg);
            else if (name === "appearance.apply") root.applyApps();
        }
    }
}
