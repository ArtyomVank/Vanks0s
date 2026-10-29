pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Список собственных иконок (shell/icons/*.svg), чтобы Sym знал, искать ли
// значок в теме. Новую иконку достаточно положить в shell/icons.
Singleton {
    id: root

    property var names: ({})

    function has(name) { return names[name] === true; }

    Process {
        running: true
        command: ["sh", "-c", "cd \"$1\" && ls -1 *.svg", "sh", Quickshell.shellDir + "/icons"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                for (const f of text.split("\n"))
                    if (f.endsWith(".svg")) map[f.slice(0, -4)] = true;
                root.names = map;
            }
        }
    }
}
