import QtQuick
import qs.common

// Полоса заполнения (0–100), высота задаётся снаружи.
//     Meter { height: 8; value: 58 }
Rectangle {
    id: root

    property real value: 0
    property color fill: Theme.accent

    radius: height / 2
    color: Theme.soft2
    clip: true

    Rectangle {
        height: parent.height
        radius: parent.radius
        width: Math.max(parent.value > 0 ? height : 0, parent.width * Math.max(0, Math.min(100, root.value)) / 100)
        color: root.fill
        Behavior on width { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }
    }
}
