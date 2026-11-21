pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Delta Link: служба delta-link serve, пока он включён (link.enabled).
// Телефон с Vanks Launcher шлёт уведомления, буфер обмена, файлы и заряд;
// здесь — острова о звонках, принятых файлах и привязке. Окно настроек
// (sections/Link.qml) говорит со службой само: delta-link status/pair/….
//
//   Link.enabled   включён в «Настройках»
//   Link.running   служба запущена
//   Link.devices   [{ id, name, model, online, battery, charging }]
//
// Во вложенной сессии служба не запускается (порт занят настоящей), если
// не задан свой порт: DELTA_LINK_PORT.
Singleton {
    id: root

    readonly property bool nested: (Quickshell.env("DELTA_NESTED") || "") !== ""
    readonly property bool enabled: Settings.get("link.enabled", false) === true
    readonly property bool allowed: !nested || (Quickshell.env("DELTA_LINK_PORT") || "") !== ""
    readonly property bool running: daemon.running
    property var devices: []
    readonly property var online: devices.filter(d => d.online)

    function deviceName(name) { return name || I18n.tr("Телефон"); }

    Process {
        id: daemon
        running: root.enabled && root.allowed
        command: ["delta-link", "serve"]
        // конец stdin — выход службы: выключили или оболочка закрылась
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                let e;
                try { e = JSON.parse(line); } catch (err) { return; }
                if (e.ev === "status") root.devices = e.devices || [];
                else if (e.ev === "paired")
                    ShellState.island({ kind: "link", icon: "phone", color: "#30D158", ms: 3500,
                                        title: I18n.tr("Телефон привязан"), text: root.deviceName(e.name) });
                else if (e.ev === "call")
                    ShellState.island({ kind: "link-call", icon: "phone-call", color: "#30D158", ms: 9000,
                                        title: e.title || I18n.tr("Звонок"), text: I18n.tr("Звонок на ") + root.deviceName(e.device) });
                else if (e.ev === "received")
                    ShellState.island({ kind: "transfer", icon: "download", color: "#30D158", ms: 3500,
                                        title: I18n.tr("Файл с телефона"), text: e.name });
                else if (e.ev === "error") console.warn("delta-link: " + e.error);
            }
        }
        onExited: {
            root.devices = [];
            if (root.enabled && root.allowed) restart.start();
        }
    }
    // служба упала — ещё раз через 10 секунд; привязка, чтобы выключатель снова работал
    Timer { id: restart; interval: 10000; onTriggered: daemon.running = Qt.binding(() => root.enabled && root.allowed) }
}
