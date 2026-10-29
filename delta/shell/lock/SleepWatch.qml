import QtQuick
import Quickshell
import Quickshell.Io

// Блокировка перед сном и по команде logind (loginctl lock-session).
//
// Пока оболочка работает, она держит «отложенную» блокировку сна logind
// (systemd-inhibit --mode=delay): при закрытии крышки или «Сне» logind шлёт
// PrepareForSleep(true) и ждёт (до InhibitDelayMaxSec, обычно 5 с), пока мы
// не отпустим блокировку. Мы успеваем показать экран блокировки, отпускаем —
// и компьютер засыпает уже заблокированным, без мелькания рабочего стола
// при пробуждении. После пробуждения (PrepareForSleep(false)) берём снова.
//
// Сигналы слушаем через gdbus monitor — в Quickshell нет общего D-Bus API.
// Во вложенной сессии блокировку сна не берём: она задержала бы сон основной системы.
Scope {
    id: root

    property bool enabled: true     // power.lockBeforeSleep
    property bool dryRun: false
    signal sleeping()               // заблокировать сейчас
    signal resumed()
    signal lockSignal()             // logind: Session.Lock

    property bool holdDelay: true
    function release() { holdDelay = false; }

    // путь D-Bus своей сессии: /org/freedesktop/login1/session/<id в кодировке sd-bus>
    readonly property string sessionId: Quickshell.env("XDG_SESSION_ID") || ""
    function busEscape(s) {
        let out = "";
        for (let i = 0; i < s.length; i++) {
            const c = s[i];
            if (/[A-Za-z0-9]/.test(c) && !(i === 0 && /[0-9]/.test(c))) out += c;
            else out += "_" + c.charCodeAt(0).toString(16).padStart(2, "0");
        }
        return out;
    }
    readonly property string sessionPath: sessionId.length ? "/org/freedesktop/login1/session/" + busEscape(sessionId) : ""

    Process {
        id: inhibitor
        running: root.enabled && !root.dryRun && root.holdDelay
        command: ["systemd-inhibit", "--what=sleep", "--mode=delay", "--who=Delta",
            "--why=Блокировка экрана перед сном", "sleep", "infinity"]
    }

    property int failures: 0
    Process {
        id: monitor
        running: true
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1"]
        stdout: SplitParser {
            onRead: line => {
                // "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (true,)"
                if (line.indexOf(".Manager.PrepareForSleep") !== -1) {
                    if (line.indexOf("(true") !== -1) {
                        console.info("[delta] logind: уходим в сон");
                        if (root.enabled) root.sleeping();
                        else root.release();
                    } else {
                        console.info("[delta] logind: пробуждение");
                        root.holdDelay = true;
                        root.resumed();
                    }
                } else if (root.sessionPath.length && line.startsWith(root.sessionPath + ":")
                           && line.indexOf(".Session.Lock ") !== -1) {
                    root.lockSignal();
                }
            }
        }
        // gdbus упал или системная шина перезапустилась — переподключаемся, но не бесконечно
        onExited: if (++root.failures < 5) restart.start()
    }
    Timer { id: restart; interval: 5000; onTriggered: monitor.running = true }
}
