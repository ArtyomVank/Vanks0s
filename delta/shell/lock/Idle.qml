import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.common

// Простой: блокировка → гашение экрана → сон.
//
// Таймеры — протокол ext-idle-notify (IdleMonitor). Окна, которые просят не гасить
// экран (видео в браузере, mpv), держат idle-inhibit — IdleMonitor это учитывает.
// Дополнительно перед действием смотрим logind BlockInhibited: туда попадают
// «systemd-inhibit --what=idle» и программы, которые просят не засыпать через D-Bus.
//
// Значения в секундах, 0 — никогда. Во вложенной сессии сон только пишется в журнал
// (PowerActions.dryRun), а экран гаснет лишь у окна вложенной сессии.
Scope {
    id: root

    property bool locked: false
    signal lockRequested()

    readonly property int lockAfter: Math.max(0, Settings.get("power.lockAfter", 300))
    readonly property int screenOffAfter: Math.max(0, Settings.get("power.screenOffAfter", 600))
    readonly property int sleepAfter: Math.max(0, Settings.get("power.sleepAfter", 1800))
    // на экране блокировки экран гаснет раньше — как в Windows
    readonly property int screenOffLocked: Math.max(0, Settings.get("power.screenOffLockedAfter", 60))

    readonly property int offTimeout: {
        if (!locked || screenOffLocked === 0) return screenOffAfter;
        return screenOffAfter === 0 ? screenOffLocked : Math.min(screenOffAfter, screenOffLocked);
    }

    property bool screenIsOff: false

    IdleMonitor {
        enabled: root.lockAfter > 0 && !root.locked
        timeout: root.lockAfter
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) root.unlessInhibited("lock")
    }

    IdleMonitor {
        enabled: root.offTimeout > 0
        timeout: root.offTimeout
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle) root.unlessInhibited("screen-off");
            else if (root.screenIsOff) root.screenOn();
        }
    }

    IdleMonitor {
        enabled: root.sleepAfter > 0
        timeout: root.sleepAfter
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) root.unlessInhibited("suspend")
    }

    function screenOn() {
        screenIsOff = false;
        PowerActions.dpms(true);
    }

    function act(what) {
        console.info("[delta] простой: " + what);
        if (what === "lock") root.lockRequested();
        else if (what === "screen-off") { screenIsOff = true; PowerActions.dpms(false); }
        else if (what === "suspend" && PowerActions.canSuspend) PowerActions.run("suspend");
    }

    // проверка logind: кто-то держит блокировку «idle» — ничего не делаем
    // несколько таймеров могут сработать одновременно — копим очередь на одну проверку
    property var pending: []
    function unlessInhibited(what) {
        pending = pending.concat([what]);
        inhibitCheck.running = true;
    }
    Process {
        id: inhibitCheck
        // busctl нет или logind недоступен — печатаем «none» и действуем как обычно
        command: ["sh", "-c", "busctl --system get-property org.freedesktop.login1 /org/freedesktop/login1 " +
            "org.freedesktop.login1.Manager BlockInhibited 2>/dev/null || echo none"]
        stdout: StdioCollector {
            onStreamFinished: {
                const blocked = /(^|[":])idle([":]|$)/.test(text.trim());
                const list = root.pending;
                root.pending = [];
                if (blocked) console.info("[delta] простой: " + list.join(", ") + " — отложено, logind idle inhibitor");
                else for (const w of list) root.act(w);
            }
        }
    }
}
