import QtQuick
import QtQuick.Shapes
import qs.common
import qs.common.ui

// «Добро пожаловать — подождите»: тёмный экран с кольцом загрузки — первое,
// что видно после загрузки системы. Его показывают экран входа (greeter.qml)
// и экран блокировки при запуске сессии (Lock.qml). done = true — надпись
// гаснет, полсекунды тёмный экран, reveal() — пора въезжать экрану входа,
// и заставка тает. Цвет — как фон Hyprland (background_color 0x14141a).
Rectangle {
    id: root

    property string name: ""
    property bool done: false
    signal reveal()

    color: "#14141a"
    visible: opacity > 0

    SequentialAnimation {
        running: root.done
        NumberAnimation { target: col; property: "opacity"; to: 0; duration: 400; easing.type: Easing.InOutQuad }
        PauseAnimation { duration: 500 }
        ScriptAction { script: root.reveal() }
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: 500; easing.type: Easing.InOutQuad }
    }

    Column {
        id: col
        anchors.centerIn: parent
        spacing: 22

        // кольцо: дуга бежит по кругу
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 46; height: 46
            Shape {
                anchors.fill: parent
                layer.enabled: true
                layer.samples: 4
                ShapePath {
                    strokeWidth: 4
                    strokeColor: Qt.rgba(1, 1, 1, 0.12)
                    fillColor: "transparent"
                    PathAngleArc { centerX: 23; centerY: 23; radiusX: 20; radiusY: 20; startAngle: 0; sweepAngle: 360 }
                }
                ShapePath {
                    strokeWidth: 4
                    strokeColor: "#ECE9F7"
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 23; centerY: 23; radiusX: 20; radiusY: 20; startAngle: -90; sweepAngle: 100 }
                }
                RotationAnimator on rotation {
                    from: 0; to: 360; duration: 1100
                    loops: Animation.Infinite
                    running: root.visible && col.opacity > 0
                }
            }
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.name ? I18n.tr("Добро пожаловать,") + " " + root.name : I18n.tr("Добро пожаловать")
            size: "h1"
            color: "#ECE9F7"
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr("Подождите…")
            color: "#A9A3C2"
        }
    }
}
