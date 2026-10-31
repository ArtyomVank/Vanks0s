pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Действия питания и экран: сон, гибернация, перезагрузка, выключение, выход,
// гашение экрана. Общие для меню питания, экрана блокировки и экрана входа.
//
// Во вложенной сессии (DELTA_NESTED) и с DELTA_DRY_RUN=1 ничего не выполняется,
// только пишется в журнал: отладка не должна усыплять или выключать компьютер.
Singleton {
    id: root

    readonly property bool dryRun: Quickshell.env("DELTA_DRY_RUN") === "1"
        || (Quickshell.env("DELTA_NESTED") || "").length > 0
        || Quickshell.env("DELTA_GREETER_MOCK") === "1"

    // logind отвечает "yes" / "no" / "na" / "challenge"; гибернацию показываем только при "yes"
    property bool canSuspend: true
    property bool canHibernate: false

    // Просьба заблокировать экран — её ловит lock/Lock.qml (меню не знает про WlSessionLock).
    signal lockRequested()

    readonly property var labels: ({
        lock: "Блокировка", logout: "Выход", suspend: "Сон", hibernate: "Гибернация",
        reboot: "Перезагрузка", poweroff: "Выключение"
    })
    // для этих действий спрашиваем подтверждение
    readonly property var destructive: ["logout", "reboot", "poweroff"]
    function needsConfirm(action) { return destructive.indexOf(action) !== -1; }

    function commandFor(action) {
        switch (action) {
        case "suspend":   return ["systemctl", "suspend"];
        case "hibernate": return ["systemctl", "hibernate"];
        case "reboot":    return ["systemctl", "reboot"];
        case "poweroff":  return ["systemctl", "poweroff"];
        // выход — это завершение Hyprland: оболочка и приложения закроются вместе с ним.
        // При автовходе («Входить без пароля») вместо экрана входа — снова
        // «Добро пожаловать» и экран блокировки, как при включении (delta-relogin)
        case "logout":    return ["sh", "-c", '[ "$(delta-autologin status 2>/dev/null)" = "$(id -un)" ] && pkexec /usr/bin/delta-relogin; hyprctl dispatch "hl.dsp.exit()"'];
        }
        return null;
    }

    function run(action) {
        if (action === "lock") { lockRequested(); return; }
        const cmd = commandFor(action);
        if (!cmd) { console.warn("[delta] неизвестное действие питания: " + action); return; }
        if (dryRun) { console.info("[delta] (проверка) " + action + ": " + cmd.join(" ")); return; }
        Quickshell.execDetached(cmd);
    }

    // Гашение экрана — через Hyprland. Синтаксис Lua-эпохи:
    //   hyprctl dispatch 'hl.dsp.dpms({ action = "off" })'
    // Во вложенной сессии гаснет только её окно, поэтому это выполняется и при проверке.
    function dpms(on) {
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.dpms({ action = \"" + (on ? "on" : "off") + "\" })"]);
    }

    function refresh() { canProc.running = true; }

    Process {
        id: canProc
        running: true
        command: ["sh", "-c",
            "for m in CanSuspend CanHibernate; do " +
            "gdbus call --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1 " +
            "--method org.freedesktop.login1.Manager.$m 2>/dev/null || echo \"('na',)\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                root.canSuspend = (lines[0] || "").indexOf("'yes'") !== -1;
                root.canHibernate = (lines[1] || "").indexOf("'yes'") !== -1;
            }
        }
    }
}
