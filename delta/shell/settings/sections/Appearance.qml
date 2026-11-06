pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.common
import qs.common.ui
import qs.settings
import qs.settings.parts

// Оформление: акцент, стекло, скругления, шрифт, значки, курсор и перенос
// всего этого на приложения GTK/Qt (helpers/theme-apply). Стиль и тема —
// в разделе «Стили и темы» (Styles.qml).
ColumnLayout {
    id: root

    property string title: I18n.tr("Оформление")
    property string icon: "palette"
    property string keywords: "цвет акцент прозрачность стекло скругление шрифт значки курсор gtk qt"
    spacing: 18

    readonly property var a: Settings.s.appearance || ({})
    property var iconThemes: []
    property var cursorThemes: []

    // --- цвет и стекло ---
    Card {
        title: I18n.tr("Цвет и стекло")

        SettingRow {
            icon: "palette"
            title: I18n.tr("Цвет оформления")
            subtitle: Theme.wallTheme ? I18n.tr("В теме «Цвет обоев» он берётся из обоев")
                                      : I18n.tr("Кнопки, выделение и рамка окна")
            RowLayout {
                spacing: 8
                enabled: !Theme.wallTheme
                opacity: enabled ? 1 : 0.5
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

        // матовость — сила размытия под стеклом (Delta и жидкое стекло); у
        // жидкого стекла она же задаёт подложку вместо прозрачности
        SliderRow {
            visible: Theme.liquid || (!Theme.flat && !Theme.material)
            icon: "eye"
            title: I18n.tr("Матовость стекла")
            subtitle: Theme.liquid ? I18n.tr("Меньше — прозрачное стекло, больше — молочное, сильнее размыто")
                                   : I18n.tr("Меньше — обои за панелями чёткие, больше — сильнее размыты")
            from: 0; to: 1; step: 0.01
            value: Theme.frost
            live: true
            format: v => Math.round(v * 100) + " %"
            onCommit: v => Settings.set("appearance.frost", Math.round(v * 100) / 100)
        }
        SliderRow {
            visible: !Theme.liquid && !Theme.material
            icon: "eye"
            title: I18n.tr("Непрозрачность доков и окон")
            subtitle: Theme.flat ? I18n.tr("В стиле GNOME панели всегда сплошные") : I18n.tr("Меньше — сквозь панели больше видно обои")
            enabled: !Theme.flat
            opacity: enabled ? 1 : 0.5
            from: 0.2; to: 0.98; step: 0.01
            value: Theme.opacity
            live: true
            format: v => Math.round(v * 100) + " %"
            onCommit: v => Settings.set("appearance.glass", Math.round(v * 100) / 100)
        }

        SliderRow {
            icon: "grid"
            title: I18n.tr("Скругление углов")
            subtitle: I18n.tr("Доки, меню и карточки")
            from: 0; to: 32; step: 1
            value: Theme.radius
            unit: " px"
            live: true
            onCommit: v => Settings.set("appearance.radius", Math.round(v))
        }

        SettingRow {
            icon: "font"
            title: I18n.tr("Шрифт")
            subtitle: Theme.font === (root.a.font || "Inter") ? "Интерфейс Delta и приложения GTK/Qt" : "«" + (root.a.font || "") + "» не найден, используется " + Theme.font
            Select {
                text: Theme.font
                onClicked: fontPicker.openWith()
            }
        }
    }

    // --- значки и курсор ---
    Card {
        title: I18n.tr("Значки и курсор")

        SettingRow {
            icon: "apps"
            title: I18n.tr("Значки приложений")
            subtitle: root.iconThemes.length ? "Тема значков для доков, меню и приложений" : "Темы значков не найдены"
            Select {
                text: root.title2(root.iconThemes, root.a.iconTheme || "Papirus-Dark")
                enabled: root.iconThemes.length > 0
                onClicked: iconPicker.openWith()
            }
        }
        SettingRow {
            icon: "cursor"
            title: I18n.tr("Курсор")
            Select {
                text: root.title2(root.cursorThemes, root.a.cursorTheme || "Adwaita")
                enabled: root.cursorThemes.length > 0
                onClicked: cursorPicker.openWith()
            }
        }
        SettingRow {
            icon: "scale"
            title: I18n.tr("Размер курсора")
            Chips {
                model: [24, 32, 40, 48, 64].map(n => ({ value: n, label: String(n) }))
                current: root.a.cursorSize ?? 24
                onPicked: v => Settings.set("appearance.cursorSize", v)
            }
        }
    }

    // --- приложения ---
    Card {
        title: I18n.tr("Приложения")

        SettingRow {
            icon: "windows"
            title: I18n.tr("Применять к приложениям GTK и Qt")
            subtitle: I18n.tr("Программы будут в тех же цветах, что и Delta")
            Toggle {
                checked: root.a.applyApps ?? true
                onToggled: v => Settings.set("appearance.applyApps", v)
            }
        }
        SettingRow {
            icon: "refresh"
            title: I18n.tr("Применить сейчас")
            subtitle: root.applyState
            Btn { text: I18n.tr("Применить"); enabled: !root.applying; onClicked: root.applyApps() }
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
                  "--base", Theme.baseRgb,
                  "--radius", String(Settings.get("windows.rounding", 16)),
                  "--font", Theme.font], {
            label: I18n.tr("оформление для GTK/Qt"),
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
        title: I18n.tr("Шрифт интерфейса")
        searchHint: "Название шрифта"
        current: Theme.font
        model: Theme.families.filter(f => !/^(Noto Color Emoji|.*Symbols?|.*Emoji.*|Cursor|D050000L)$/.test(f))
                             .map(f => ({ value: f, label: f, font: f }))
        onPicked: v => Settings.set("appearance.font", v)
    }
    Picker {
        id: iconPicker
        title: I18n.tr("Тема значков")
        current: root.a.iconTheme || "Papirus-Dark"
        model: root.iconThemes
        onPicked: v => Settings.set("appearance.iconTheme", v)
    }
    Picker {
        id: cursorPicker
        title: I18n.tr("Тема курсора")
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
