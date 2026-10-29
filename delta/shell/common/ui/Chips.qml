pragma ComponentBehavior: Bound

import QtQuick
import qs.common

// Выбор одного из вариантов («чипы», как в концепте).
//     Chips { model: [{ value: "full", label: "Полный" }, { value: "compact", label: "Компактный" }]
//             current: Settings.get("docks.apps.length", "compact")
//             onPicked: v => Settings.set("docks.apps.length", v) }
Flow {
    id: root

    property var model: []
    property var current
    signal picked(var value)

    spacing: 6

    Repeater {
        model: root.model
        delegate: Rectangle {
            id: chip
            required property var modelData
            readonly property bool sel: modelData.value === root.current

            implicitWidth: lbl.implicitWidth + 24
            implicitHeight: 30
            radius: 15
            color: sel ? Theme.accent : Theme.soft2
            border.width: sel ? 0 : 1
            border.color: Theme.line
            Behavior on color { ColorAnimation { duration: Theme.anim.fast } }

            Label {
                id: lbl
                anchors.centerIn: parent
                text: chip.modelData.label
                size: "small"
                color: chip.sel ? Theme.onAccent : Theme.fg
                font.weight: Font.Medium
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.picked(chip.modelData.value) }
        }
    }
}
