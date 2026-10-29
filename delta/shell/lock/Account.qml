pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Текущий пользователь: логин, отображаемое имя, аватар, администратор ли.
// Аватар ищем там же, где GNOME/SDDM: AccountsService, затем ~/.face.
// Имя — из GECOS (его меняют «Настройки» → Профиль через AccountsService).
Singleton {
    id: root

    readonly property string user: Quickshell.env("USER") || ""
    property string realName: ""
    readonly property string name: realName.length ? realName : user
    property string avatar: ""          // путь к файлу или ""
    property bool admin: false
    // меняется при каждом перечитывании — чтобы Image не брал старую картинку из кэша
    property int revision: 0

    function refresh() { info.running = true; }

    Process {
        id: info
        running: true
        // строка 1 — GECOS, строка 2 — путь к аватару, строка 3 — группы
        command: ["sh", "-c",
            "u=$1; getent passwd \"$u\" | cut -d: -f5 | cut -d, -f1; a=; " +
            "for f in \"/var/lib/AccountsService/icons/$u\" \"$HOME/.face\" \"$HOME/.face.icon\"; do " +
            "[ -r \"$f\" ] && [ -s \"$f\" ] && { a=$f; break; }; done; echo \"$a\"; id -Gn \"$u\" 2>/dev/null",
            "sh", root.user]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n");
                root.realName = (l[0] || "").trim();
                root.avatar = (l[1] || "").trim();
                root.admin = /(^|\s)(wheel|sudo|admin)(\s|$)/.test(l[2] || "");
                root.revision++;
            }
        }
    }
}
