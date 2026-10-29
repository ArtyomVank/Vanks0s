import QtQuick
import qs.common
import qs.services
import qs.widgets
import qs.widgets.parts

// Один показатель: процессор, память, видеокарта или диск.
// Рабочий стол: кольцо-показатель, волнистое или прямое (widgets/parts/Gauge).
// На экране блокировки — «23% Нагрузка процессора», кольцо или полоса.
Base {
    id: root

    readonly property string kind: item ? item.id : "cpu"
    StatsUser { active: root.visible; gpu: root.kind === "gpu"; disk: root.kind === "disk" }

    readonly property real value: kind === "gpu" ? SystemStats.gpu
                                : kind === "ram" ? SystemStats.ram
                                : kind === "disk" ? SystemStats.disk
                                : SystemStats.cpu
    readonly property bool ok: value >= 0
    readonly property var hist: kind === "gpu" ? SystemStats.gpuHist : kind === "ram" ? SystemStats.ramHist : SystemStats.cpuHist
    readonly property string valueText: ok ? Math.round(value) + "%" : "—"
    readonly property string caption: (WidgetTypes.info("desktop", kind) || { short: "" }).short
    readonly property string details: !ok ? "нет данных"
        : kind === "ram" ? SystemStats.pair(SystemStats.ramUsed, SystemStats.ramTotal)
        : kind === "disk" ? SystemStats.pair(SystemStats.diskUsed, SystemStats.diskTotal)
        : ""
    readonly property string lockText: kind === "ram" ? "Оперативная\nпамять" : kind === "gpu" ? "Нагрузка\nвидеокарты" : kind === "disk" ? "Диск\nзанят" : "Нагрузка\nпроцессора"

    // ---- рабочий стол: кольцо-показатель, прямое или волнистое ----
    readonly property string icon: kind === "gpu" ? "gpu" : kind === "ram" ? "memory" : kind === "disk" ? "disk" : "cpu"
    readonly property string gaugeLabel: kind === "gpu" ? "ГП" : kind === "ram" ? "ОЗУ" : kind === "disk" ? "Диск" : "ЦП"
    // память — сколько занято, остальное — проценты
    readonly property string gaugeText: !ok ? "—"
        : kind === "ram" && SystemStats.ramUsed > 0 ? SystemStats.bytes(SystemStats.ramUsed).replace(" ГБ", "G").replace(" МБ", "M")
        : valueText
    Gauge {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        visible: !root.lock
        wavy: root.mode !== "straight"
        value: root.ok ? root.value : 0
        icon: root.icon
        text: root.gaugeText
        label: root.gaugeLabel
        color: root.pal.c1
        track: root.pal.track
        textColor: root.pal.c1
        labelColor: root.pal.c2
    }

    // ---- экран блокировки: число · кольцо · полоса ----
    Item {
        anchors.fill: parent
        visible: root.lock

        Row {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.mode === "number" || root.mode === ""
            spacing: 6 * root.cm
            WText { anchors.verticalCenter: parent.verticalCenter; text: root.valueText; px: Math.min(34 * root.ch, 15 * root.cw); font.weight: Font.ExtraBold; color: root.pal.c1 }
            WText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.lockText
                maximumLineCount: 2
                lineHeight: 1.1
                px: Math.min(15 * root.ch, 6.5 * root.cw)
                color: root.pal.c1
                opacity: 0.85
            }
        }

        Item {
            anchors.fill: parent
            visible: root.mode === "ring"
            WText {
                id: lockCap
                width: parent.width
                text: root.caption
                px: Math.min(10 * root.ch, 4 * root.cw)
                font.weight: Font.ExtraBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.6
                color: root.pal.c1
                opacity: 0.8
            }
            Ring {
                anchors { horizontalCenter: parent.horizontalCenter; top: lockCap.bottom; bottom: parent.bottom }
                width: Math.min(parent.height - lockCap.height, parent.width)
                value: root.ok ? root.value : 0
                color: root.pal.c1
                track: root.pal.track
                WText { anchors.centerIn: parent; text: root.valueText; px: Math.min(18 * root.ch, 7 * root.cw); display: true; color: root.pal.c1 }
            }
        }

        Item {
            anchors.fill: parent
            visible: root.mode === "bar"
            Column {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 5 * root.cm
                WText { text: root.caption; px: Math.min(11 * root.ch, 4.4 * root.cw); font.weight: Font.ExtraBold; color: root.pal.c1; opacity: 0.85 }
                WText { text: root.valueText; px: Math.min(30 * root.ch, 13 * root.cw); display: true; font.weight: Font.ExtraBold; color: root.pal.c1 }
                Meter { width: parent.width; height: Math.max(4, 6 * root.cm); value: root.ok ? root.value : 0; color: root.pal.track; fill: root.pal.c1 }
            }
        }
    }
}
