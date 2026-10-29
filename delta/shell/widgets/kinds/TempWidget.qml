import QtQuick
import qs.common
import qs.services
import qs.widgets.parts

// Температура видеокарты (gtemp) или процессора (ctemp): кольцо-показатель,
// волнистое или прямое (widgets/parts/Gauge).
Base {
    id: root

    readonly property bool isGpu: !item || item.id !== "ctemp"
    StatsUser { active: root.visible; gpu: root.isGpu }

    readonly property real value: isGpu ? SystemStats.gpuTemp : SystemStats.cpuTemp
    readonly property bool ok: value >= 0
    // порог «горячо» у процессоров выше, чем у видеокарт
    readonly property bool hot: ok && value >= (isGpu ? 75 : 80)
    readonly property color tone: hot ? Theme.accents[4] : root.pal.c1
    readonly property string valueText: ok ? Math.round(value) + "°" : "—"
    readonly property string note: !ok ? "нет данных" : hot ? "Горячо — под нагрузкой" : "В норме"
    readonly property string caption: isGpu ? "Темп. видеокарты" : "Темп. процессора"

    // кольцо-показатель: шкала 0–100 °C, прямое или волнистое
    Gauge {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        wavy: root.mode !== "straight"
        value: root.ok ? root.value : 0
        icon: "thermometer"
        text: root.valueText
        label: root.isGpu ? "Темп. ГП" : "Темп. ЦП"
        color: root.hot ? Theme.accents[4] : root.pal.c1
        track: root.pal.track
        textColor: root.tone
        labelColor: root.pal.c2
    }
}
