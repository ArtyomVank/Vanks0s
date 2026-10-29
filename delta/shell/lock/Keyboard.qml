pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Раскладка и Caps Lock основной клавиатуры — для подсказок у поля пароля.
// В QML нет состояния Caps Lock, поэтому спрашиваем Hyprland (hyprctl devices):
// при показе экрана, при смене раскладки и после нажатия Caps Lock.
Singleton {
    id: root

    property string layout: ""        // "RU", "EN", …
    property bool capsLock: false
    property int count: 0             // сколько раскладок настроено

    // коды xkb, которые не совпадают с привычной подписью
    readonly property var names: ({ us: "EN", gb: "EN", ua: "UA", by: "BY", kz: "KZ" })

    function refresh() { if (!proc.running) proc.running = true; }
    // состояние Caps Lock в Hyprland меняется чуть позже самого нажатия
    function refreshSoon() { later.restart(); }
    function next() {
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "next"]);
        later.restart();
    }

    Timer { id: later; interval: 120; onTriggered: root.refresh() }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") root.refresh();
        }
    }

    Process {
        id: proc
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                let kb = null;
                try {
                    const list = JSON.parse(text).keyboards || [];
                    kb = list.find(k => k.main) || list[0] || null;
                } catch (e) { return; }
                if (!kb) return;
                const codes = String(kb.layout || "").split(",").map(s => s.trim()).filter(s => s.length);
                const code = codes[kb.active_layout_index ?? 0] || codes[0] || "";
                root.count = codes.length;
                root.layout = (root.names[code] || code.slice(0, 2)).toUpperCase();
                root.capsLock = kb.capsLock === true;
            }
        }
    }
}
