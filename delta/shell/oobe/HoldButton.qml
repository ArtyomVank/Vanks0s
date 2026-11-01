import QtQuick
import Quickshell.Widgets
import qs.common
import qs.common.ui

// «Начать»: кнопку нужно зажать — снизу поднимается жидкость цвета акцента
// (common/ui/Liquid), надпись под её уровнем перекрашивается. Отпустили
// раньше — жидкость стекает обратно с пружинкой. Заполнилась — completed().
Item {
    id: root

    property string text: I18n.tr("Начать")
    property alias holdTime: charge.holdTime
    readonly property alias fill: charge.fill
    readonly property alias done: charge.done
    signal completed()

    implicitWidth: 320
    implicitHeight: 72

    function begin() { charge.begin(); }
    // повторный запуск настройки: снова пустая
    function reset() { charge.reset(); }
    function cancel() { charge.cancel(); }

    HoldCharge { id: charge; onCompleted: root.completed() }
    readonly property real level: charge.level

    // дрожь, когда почти заполнилась
    property real jitter: 0
    FrameAnimation {
        running: root.fill > 0.7 && !root.done
        onTriggered: root.jitter = Math.sin(elapsedTime * 70) * (root.fill - 0.7) * 4
        onRunningChanged: if (!running) root.jitter = 0
    }

    // ореол
    Rectangle {
        anchors.centerIn: body
        width: body.width; height: body.height
        radius: height / 2
        color: Theme.accent
        opacity: root.level * 0.4
        scale: 1 + root.level * 0.3
    }
    Rectangle {
        anchors.centerIn: body
        width: body.width; height: body.height
        radius: height / 2
        color: "transparent"
        border.width: 2
        border.color: Theme.accent
        opacity: root.done ? 0 : 0.5 * (1 - breathe.t)
        scale: 1 + breathe.t * 0.22
        QtObject { id: breathe; property real t: 0 }
        SequentialAnimation {
            running: !root.done && area.pressed === false
            loops: Animation.Infinite
            NumberAnimation { target: breathe; property: "t"; from: 0; to: 1; duration: 1600; easing.type: Easing.OutCubic }
            PauseAnimation { duration: 300 * Theme.anim.k }
        }
    }

    ClippingRectangle {
        id: body
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.jitter
        width: root.width; height: root.height
        radius: height / 2
        color: Theme.soft2
        border.width: 1
        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)
        scale: (area.pressed ? 0.97 : 1) + root.level * 0.06
        Behavior on scale { NumberAnimation { duration: 90 * Theme.anim.k } }

        Liquid { id: liquid; anchors.fill: parent; level: root.level; still: root.done }

        // надпись над жидкостью — обычным цветом
        Row {
            id: caption
            anchors.centerIn: parent
            spacing: 10
            Sym {
                anchors.verticalCenter: parent.verticalCenter
                name: root.done ? "check" : "rocket"
                size: 22
                color: Theme.accent
                rotation: root.done ? 0 : root.level * -25
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: root.text
                size: "title"
            }
        }
        // та же надпись под уровнем жидкости — на её цвете
        Item {
            x: 0
            y: Math.max(0, liquid.surface)
            width: body.width
            height: Math.max(0, body.height - y)
            clip: true
            visible: liquid.visible
            Row {
                x: caption.x
                y: caption.y - parent.y
                spacing: caption.spacing
                Sym {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.done ? "check" : "rocket"
                    size: 22
                    color: Theme.onAccent
                    rotation: root.done ? 0 : root.level * -25
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.text
                    size: "title"
                    color: Theme.onAccent
                }
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: body
        cursorShape: Qt.PointingHandCursor
        onPressed: root.begin()
        onReleased: root.cancel()
        onCanceled: root.cancel()
    }
    // с клавиатуры: зажать пробел или Enter
    function keyDown() { if (!charge.charging) begin(); }
    function keyUp() { cancel(); }
}
