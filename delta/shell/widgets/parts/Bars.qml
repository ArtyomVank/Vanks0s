pragma ComponentBehavior: Bound

import QtQuick
import qs.common

// График «столбцы» по истории (0–100). Число столбцов зависит от ширины,
// промежутки и скругления — от размера, поэтому график масштабируется.
//     Bars { values: SystemStats.gpuHist }
Item {
    id: root

    property var values: []
    property color color: Theme.accent
    // ширина столбца с промежутком, в пикселях
    property real pitch: 12

    readonly property int count: Math.max(6, Math.min(24, Math.floor(width / pitch)))
    readonly property real gap: width / count * 0.22
    readonly property var shown: {
        const v = values.slice(-count);
        while (v.length < count) v.unshift(0);
        return v;
    }

    Row {
        anchors.fill: parent
        spacing: root.gap
        Repeater {
            model: root.count
            delegate: Item {
                id: bar
                required property int index
                width: (root.width - root.gap * (root.count - 1)) / root.count
                height: root.height
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: Math.max(parent.height * 0.06, parent.height * (root.shown[bar.index] || 0) / 100)
                    radius: Math.min(width / 2, 3 * width / 8)
                    color: root.color
                    opacity: 0.85
                    Behavior on height { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }
                }
            }
        }
    }
}
