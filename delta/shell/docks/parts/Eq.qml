import QtQuick
import qs.common

// Маленький эквалайзер из четырёх полосок (как .eq в концепте).
// Анимация идёт только пока playing — на паузе полоски замирают.
Row {
    id: root

    property bool playing: true
    property int barHeight: 16
    property color color: Theme.accent

    spacing: 3
    height: barHeight

    Repeater {
        model: 4
        delegate: Rectangle {
            id: bar
            required property int index
            width: 3
            height: root.barHeight
            radius: 1.5
            color: root.color
            anchors.bottom: parent.bottom
            transform: Scale { id: sc; origin.y: bar.height; yScale: 0.25 }

            SequentialAnimation {
                running: root.playing && root.visible
                loops: Animation.Infinite
                PauseAnimation { duration: bar.index * 150 }
                SequentialAnimation {
                    loops: Animation.Infinite
                    NumberAnimation { target: sc; property: "yScale"; to: 1; duration: 450; easing.type: Easing.InOutSine }
                    NumberAnimation { target: sc; property: "yScale"; to: 0.25; duration: 450; easing.type: Easing.InOutSine }
                }
            }
        }
    }
}
