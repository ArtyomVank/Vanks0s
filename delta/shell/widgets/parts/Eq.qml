pragma ComponentBehavior: Bound

import QtQuick
import qs.common

// Маленький «эквалайзер» из четырёх столбиков, пока играет музыка.
// На паузе столбики замирают — анимация не крутится зря.
Row {
    id: root

    property bool playing: false
    property color color: Theme.accent

    spacing: width * 0.12
    Repeater {
        model: 4
        delegate: Rectangle {
            id: bar
            required property int index
            width: (root.width - root.spacing * 3) / 4
            height: root.height
            radius: width / 2
            color: root.color
            transformOrigin: Item.Bottom
            scale: 0.4
            SequentialAnimation on scale {
                running: root.playing && root.visible
                loops: Animation.Infinite
                PauseAnimation { duration: bar.index * 150 }
                NumberAnimation { to: 1; duration: 450; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.3; duration: 450; easing.type: Easing.InOutSine }
            }
        }
    }
}
