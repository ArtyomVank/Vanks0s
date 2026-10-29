pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.common
import qs.common.ui
import qs.launcher.parts

// Меню раскладки: раскладки из input.layouts, текущая подсвечена.
// В Lua-конфиге Hyprland 0.56 диспетчера смены раскладки нет (hl.dsp.*),
// поэтому переключаем командой `hyprctl switchxkblayout all <номер>` —
// сразу на всех клавиатурах, чтобы они не расходились.
Item {
    id: root

    implicitWidth: 280
    implicitHeight: col.implicitHeight
    signal close()

    readonly property var layouts: {
        const l = Settings.get("input.layouts", ["us", "ru"]);
        return Array.isArray(l) && l.length ? l : ["us"];
    }
    readonly property var names: ({
        us: "English (US)", gb: "English (UK)", ru: "Русский", ua: "Українська", by: "Беларуская",
        kz: "Қазақша", de: "Deutsch", fr: "Français", es: "Español", it: "Italiano", pl: "Polski",
        cz: "Čeština", tr: "Türkçe", pt: "Português", br: "Português (BR)", jp: "日本語", cn: "中文",
        kr: "한국어", am: "Հայերեն", ge: "ქართული", il: "עברית", ara: "العربية", fi: "Suomi", se: "Svenska"
    })
    function code(l) {
        const c = String(l).split("(")[0].trim();
        return c === "us" || c === "gb" ? "EN" : c.slice(0, 2).toUpperCase();
    }

    property int active: -1
    function refresh() { if (!devices.running) devices.running = true; }
    Process {
        id: devices
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const kb = JSON.parse(text).keyboards || [];
                    const main = kb.find(k => k.main) ?? kb[0];
                    if (main && main.active_layout_index !== undefined) root.active = main.active_layout_index;
                } catch (e) {}
            }
        }
    }
    Component.onCompleted: refresh()
    onVisibleChanged: if (visible) refresh()
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "activelayout") root.refresh(); }
    }

    Process { id: switcher }
    function pick(i) {
        active = i;
        switcher.command = ["hyprctl", "switchxkblayout", "all", String(i)];
        switcher.running = true;
    }

    readonly property string keys: {
        const o = String(Settings.get("input.switchKeys", "grp:alt_shift_toggle"));
        const map = { alt_shift_toggle: "Alt + Shift", ctrl_shift_toggle: "Ctrl + Shift", win_space_toggle: "Super + Пробел",
                      caps_toggle: "Caps Lock", alt_space_toggle: "Alt + Пробел", ctrl_alt_toggle: "Ctrl + Alt", lalt_lshift_toggle: "Левые Alt + Shift" };
        const m = o.match(/grp:([a-z_]+)/);
        return m && map[m[1]] ? map[m[1]] : "";
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 6

        MenuTitle { text: "Язык ввода" }

        Repeater {
            model: root.layouts
            delegate: MenuRow {
                id: lay
                required property string modelData
                required property int index
                active: root.active === index
                title: root.names[String(modelData).split("(")[0].trim()] ?? modelData
                subtitle: root.code(modelData) + " · " + modelData
                onClicked: root.pick(index)

                Sym { visible: lay.active; name: "check"; size: 18; color: Theme.accent }
            }
        }

        Label {
            visible: root.keys.length > 0
            text: "Переключение: " + root.keys
            size: "caption"; tone: 3
            Layout.leftMargin: 4
            Layout.topMargin: 2
        }
        Btn {
            Layout.alignment: Qt.AlignLeft
            kind: "ghost"
            icon: "keyboard"
            text: "Раскладки…"
            implicitHeight: 32
            onClicked: { ShellState.openSettings("keyboard", null); root.close(); }
        }
    }
}
