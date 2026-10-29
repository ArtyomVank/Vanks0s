pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Текущая раскладка клавиатуры. Начальное значение — из `hyprctl devices`,
// дальше — по событию Hyprland `activelayout` (без опроса).
//     KbLayout.short  "RU"     KbLayout.name  "Russian"
Singleton {
    id: root

    property string name: ""
    readonly property string short: shortFor(name)
    // приходит только при настоящем переключении (для OSD)
    signal switched()

    readonly property var codes: ({
        "English": "EN", "Russian": "RU", "Ukrainian": "UA", "Belarusian": "BY", "Kazakh": "KZ",
        "German": "DE", "French": "FR", "Spanish": "ES", "Italian": "IT", "Polish": "PL",
        "Portuguese": "PT", "Turkish": "TR", "Czech": "CZ", "Japanese": "JA", "Chinese": "ZH",
        "Korean": "KO", "Georgian": "KA", "Armenian": "HY", "Hebrew": "HE", "Arabic": "AR"
    })
    readonly property var russianNames: ({
        "EN": "Английская", "RU": "Русская", "UA": "Украинская", "BY": "Белорусская", "KZ": "Казахская",
        "DE": "Немецкая", "FR": "Французская", "ES": "Испанская", "IT": "Итальянская", "PL": "Польская"
    })
    readonly property string title: russianNames[short] ?? name

    function shortFor(n) {
        if (!n) return "";
        const word = n.split(/[ (]/)[0];
        return codes[word] ?? word.slice(0, 2).toUpperCase();
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "activelayout") return;
            const data = event.data;
            const i = data.indexOf(",");
            const layout = i >= 0 ? data.slice(i + 1) : data;
            if (!layout || layout === root.name) return;
            root.name = layout;
            root.switched();
        }
    }

    Process {
        running: true
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const kbs = JSON.parse(text).keyboards || [];
                    const kb = kbs.find(k => k.main) || kbs[0];
                    if (kb && !root.name) root.name = kb.active_keymap || "";
                } catch (e) {
                    // нет hyprctl или не Hyprland — модуль просто покажет пустую строку
                }
            }
        }
    }
}
