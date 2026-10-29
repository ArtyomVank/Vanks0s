pragma Singleton

import QtQuick
import Quickshell
import qs.settings

// Учётные записи из AccountsService (общие для «Профиля» и «Пользователей»).
// Чтение — helpers/accounts; изменения — через Exec (пробный режим в проверках).
Singleton {
    id: root

    property var users: []
    readonly property var me: users.find(u => u.me) || ({ userName: Quickshell.env("USER") || "", realName: "", icon: "", admin: false, path: "" })
    readonly property string displayName: me.realName || me.userName
    property bool loaded: false
    // аватар только что сохранён: показываем его, пока AccountsService не ответит
    property string pendingIcon: ""
    readonly property string icon: pendingIcon || me.icon || ""

    function refresh() {
        Exec.read(["bash", Exec.helper("accounts")], (code, out) => {
            try { root.users = JSON.parse(out); } catch (e) { console.warn("[delta-settings] AccountsService: " + e); }
            root.loaded = true;
        });
    }

    // busctl call … User.<method> <сигнатура> <аргументы>
    function callUser(path, method, sig, args, label, done) {
        Exec.run(["busctl", "call", "org.freedesktop.Accounts", path, "org.freedesktop.Accounts.User", method, sig].concat(args),
                 { label: label, done: done });
    }

    Component.onCompleted: refresh()
}
