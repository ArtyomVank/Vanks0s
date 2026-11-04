pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// История буфера обмена для модуля верхнего дока. За буфером следит delta-clipboard
// (cliphist), только пока модуль в доке. В памяти — начало списка; вся история в базе.
Singleton {
    id: root

    readonly property int limit: 2000
    readonly property int max: Math.max(1, Math.min(limit, Number(Settings.get("clipboard.max", 200)) || 200))
    property int users: 0
    property var items: []
    property int total: 0
    readonly property int shown: 200

    function setMax(n) {
        const v = Math.max(1, Math.min(limit, Math.round(Number(n) || 0)));
        Settings.set("clipboard.max", v);
        apply.command = ["delta-clipboard", "max", String(v)];
        apply.running = true;
    }
    function copy(id) {
        Quickshell.execDetached(["delta-clipboard", "copy", id]);
    }
    function remove(id) {
        act.command = ["delta-clipboard", "delete", id];
        act.running = true;
    }
    function wipe() {
        act.command = ["delta-clipboard", "wipe"];
        act.running = true;
    }
    function refresh() { debounce.restart(); }

    // значение из настроек пишется и при первом запуске: delta-clipboard не читает настройки
    onUsersChanged: if (users > 0 && !apply.running) {
        apply.command = ["delta-clipboard", "max", String(max)];
        apply.running = true;
    }

    Process {
        id: watcher
        running: root.users > 0
        command: ["delta-clipboard", "watch"]
        stdout: SplitParser { onRead: root.refresh() }
    }
    Timer {
        id: debounce
        interval: 200
        onTriggered: lister.running = true
    }
    Process {
        id: lister
        command: ["delta-clipboard", "list", String(root.shown)]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const v = JSON.parse(text);
                    root.items = v.items;
                    root.total = v.total;
                } catch (e) {}
            }
        }
    }
    Process { id: apply; onExited: root.refresh() }
    Process { id: act; onExited: root.refresh() }
}
