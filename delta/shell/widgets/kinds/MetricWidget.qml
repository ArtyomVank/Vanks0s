import QtQuick
import qs.common
import qs.services
import qs.widgets
import qs.widgets.parts

// Один показатель: процессор, память, видеокарта или диск.
// Кольцо-показатель, волнистое или прямое (widgets/parts/Gauge) — и на
// рабочем столе, и на экране блокировки.
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
}
