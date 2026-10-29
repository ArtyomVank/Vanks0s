pragma ComponentBehavior: Bound

import QtQuick
import qs.common
import qs.common.ui

// Сочетание клавиш «клавишами»: KeyCaps { keys: ["Super", "S"] }
Row {
    id: root

    property var keys: []

    spacing: 4

    Repeater {
        model: root.keys
        delegate: Rectangle {
            required property string modelData
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: Math.max(26, k.implicitWidth + 14)
            implicitHeight: 26
            radius: 7
            color: Theme.soft2
            border.color: Theme.line
            Label { id: k; anchors.centerIn: parent; text: parent.modelData; size: "caption"; font.weight: Font.DemiBold }
        }
    }
}
