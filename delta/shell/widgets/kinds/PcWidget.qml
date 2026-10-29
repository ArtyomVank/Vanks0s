pragma ComponentBehavior: Bound

import QtQuick
import qs.common
import qs.services
import qs.widgets.parts

// «Показатели ПК»: четыре кольца-показателя (волнистые или прямые) или список с полосами.
Base {
    id: root

    StatsUser { active: root.visible; gpu: true }

    readonly property color hot: Theme.accents[4]
    function pct(v) { return v >= 0 ? Math.round(v) + "%" : "—"; }
    function deg(v) { return v >= 0 ? Math.round(v) + "°" : "—"; }

    readonly property bool list: mode === "list"
    // [подпись, короткая подпись, значение 0–100 или -1, текст, цвет, значок]
    readonly property var rows: [
        ["Процессор", "ЦП", SystemStats.cpu, pct(SystemStats.cpu), Theme.accent, "cpu"],
        ["Видеокарта", "ГП", SystemStats.gpu, pct(SystemStats.gpu), Theme.accent, "gpu"],
        ["ОЗУ", "ОЗУ", SystemStats.ram, pct(SystemStats.ram), Theme.accent, "memory"],
        SystemStats.hasGpuTemp || !SystemStats.hasCpuTemp
            ? ["Темп. ГП", "Темп.", SystemStats.gpuTemp, deg(SystemStats.gpuTemp), hot, "thermometer"]
            : ["Темп. ЦП", "Темп.", SystemStats.cpuTemp, deg(SystemStats.cpuTemp), hot, "thermometer"]
    ]

    WCaption { id: cap; cm: root.cm; text: "Показатели ПК"; color: root.pal.c2 }

    // ---- список ----
    Column {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: root.list
        spacing: 5 * root.ch
        Repeater {
            model: root.rows
            delegate: Item {
                id: row
                required property var modelData
                width: parent.width
                height: Math.min(8.5 * root.ch, 3.6 * root.cw) * 1.25
                WText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30 * root.cw
                    text: row.modelData[0]
                    px: Math.min(8.5 * root.ch, 3.6 * root.cw)
                    color: root.pal.c1
                }
                Meter {
                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 33 * root.cw; right: parent.right; rightMargin: 16 * root.cw }
                    height: 5 * root.ch
                    value: Math.max(0, row.modelData[2])
                    fill: row.modelData[4]
                    color: root.pal.track
                }
                WText {
                    anchors { verticalCenter: parent.verticalCenter; right: parent.right }
                    text: row.modelData[3]
                    px: Math.min(8.5 * root.ch, 3.6 * root.cw)
                    font.weight: Font.Bold
                    color: root.pal.c1
                    horizontalAlignment: Text.AlignRight
                }
            }
        }
    }

    // ---- кольца ----
    Row {
        anchors { left: parent.left; right: parent.right; top: cap.bottom; bottom: parent.bottom; topMargin: 2 * root.ch }
        visible: !root.list
        Repeater {
            model: root.rows
            delegate: Item {
                id: cell
                required property var modelData
                width: parent.width / 4
                height: parent.height
                Gauge {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 2 * root.cw, parent.height)
                    height: width
                    wavy: root.mode !== "straight"
                    value: Math.max(0, cell.modelData[2])
                    icon: cell.modelData[5]
                    text: cell.modelData[3]
                    label: cell.modelData[1]
                    color: cell.modelData[4] === root.hot && cell.modelData[2] >= 75 ? root.hot : root.pal.c1
                    track: root.pal.track
                    textColor: root.pal.c1
                    labelColor: root.pal.c2
                }
            }
        }
    }
}
