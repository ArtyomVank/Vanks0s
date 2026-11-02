pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Что сейчас скачивается: файлы с телефона, браузер, магазин (delta-transfers).
// Показывает верхний док (docks/TransferPill.qml), а о конце загрузки сообщает
// остров.
Singleton {
    id: root

    // [{ id, kind: phone | browser | store, name, done, total, speed }]
    property var items: []
    readonly property bool active: items.length > 0
    // док раскрыт: полоса, сколько скачано и скорость
    property bool expanded: false
    onActiveChanged: if (!active) expanded = false

    readonly property real done: items.reduce((a, i) => a + i.done, 0)
    // размер неизвестен хотя бы у одной загрузки — общего процента нет
    readonly property real total: items.every(i => i.total > 0) ? items.reduce((a, i) => a + i.total, 0) : 0
    readonly property real speed: items.reduce((a, i) => a + i.speed, 0)
    readonly property int percent: total > 0 ? Math.min(100, Math.floor(done * 100 / total)) : -1
    readonly property string name: items.length > 1 ? I18n.tr("Файлов: ") + items.length : (items[0]?.name ?? "")
    readonly property string source: {
        const k = items.length === 1 ? items[0].kind : "";
        return k === "phone" ? I18n.tr("С телефона") : k === "store" ? I18n.tr("Магазин") : k === "browser" ? I18n.tr("Браузер") : "";
    }

    function bytes(n) {
        const units = [I18n.tr("Б"), I18n.tr("КБ"), I18n.tr("МБ"), I18n.tr("ГБ")];
        let i = 0;
        while (n >= 1024 && i < units.length - 1) { n /= 1024; i++; }
        return n.toLocaleString(Qt.locale(), "f", i >= 2 && n < 100 ? 1 : 0) + " " + units[i];
    }

    Process {
        id: watch
        running: true
        command: ["delta-transfers", "watch"]
        stdout: SplitParser {
            onRead: line => {
                let e;
                try { e = JSON.parse(line); } catch (err) { return; }
                if (e.items) root.items = e.items;
                else if (e.event === "done")
                    ShellState.island({ kind: "transfer", icon: "check", color: "#30D158", ms: 3500,
                                        title: I18n.tr("Успешная загрузка"), text: e.name });
            }
        }
        // упал — без загрузок в доке жить можно, но попробуем ещё раз
        onExited: restart.start()
    }
    Timer { id: restart; interval: 10000; onTriggered: watch.running = true }
}
