import QtQuick
import QtQuick.Shapes
import qs.common
import qs.common.ui

// «Добро пожаловать — подождите»: тёмный экран с кольцом загрузки. Его
// показывает экран входа после пароля и оболочка, пока грузится рабочий стол:
// вместо чёрного экрана и второй блокировки — одна заставка, как в Windows.
// Цвет — как фон Hyprland (background_color 0x14141a в обоих конфигах), чтобы
// стык между композитором экрана входа и сессией был незаметен.
Rectangle {
    id: root

    property string name: ""

    color: "#14141a"

    Column {
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
                    running: root.visible
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
