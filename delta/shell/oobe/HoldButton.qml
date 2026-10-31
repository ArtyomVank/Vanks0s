import QtQuick
import qs.common
import qs.common.ui

// «Начать»: кнопку нужно зажать, она заполняется светом. Отпустили раньше —
// пружиной стекает обратно. Заполнилась — completed().
Item {
    id: root

    property string text: I18n.tr("Начать")
    property int holdTime: 1500
    property real fill: 0
    property bool done: false
    signal completed()

    implicitWidth: 320
    implicitHeight: 72

    function begin() {
        if (done) return;
        drain.stop();
        charge.duration = Math.max(60, (1 - Math.max(0, fill)) * holdTime);
        charge.restart();
        Sounds.hold("oobe-hold");
    }
    function cancel() {
        if (done) return;
        charge.stop();
        Sounds.release();
        drain.restart();
    }

    NumberAnimation {
        id: charge
        target: root; property: "fill"; to: 1
        easing.type: Easing.InOutSine
        onFinished: if (root.fill >= 0.999) { root.done = true; Sounds.release(); root.completed(); }
    }
    NumberAnimation { id: drain; target: root; property: "fill"; to: 0; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 2.4 }

    // дрожь, когда почти заполнилась
    property real jitter: 0
    FrameAnimation {
        running: root.fill > 0.6 && !root.done
        onTriggered: root.jitter = Math.sin(elapsedTime * 70) * (root.fill - 0.6) * 4
        onRunningChanged: if (!running) root.jitter = 0
    }

    // ореол
    Rectangle {
        anchors.centerIn: body
        width: body.width; height: body.height
        radius: height / 2
        color: Theme.accent
        opacity: Math.max(0, root.fill) * 0.45
        scale: 1 + Math.max(0, root.fill) * 0.35
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

    Rectangle {
        id: body
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.jitter
        width: root.width; height: root.height
        radius: height / 2
        color: Theme.soft2
        border.width: 1
        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)
        scale: (area.pressed ? 0.97 : 1) + Math.max(0, root.fill) * 0.07
        Behavior on scale { NumberAnimation { duration: 90 * Theme.anim.k } }
        clip: true

        // заливка слева направо
        Rectangle {
            height: parent.height
            width: Math.max(0, root.fill) * parent.width
            radius: parent.radius
            visible: root.fill > 0.005
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.darker(Theme.accent, 1.25) }
                GradientStop { position: 1; color: Qt.lighter(Theme.accent, 1.35) }
            }
            // блик бежит по заливке
            Rectangle {
                width: 70; height: parent.height * 2
                y: -parent.height / 2
                rotation: 20
                x: shine.x
                opacity: 0.35
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.5; color: "white" }
                    GradientStop { position: 1; color: "transparent" }
                }
                QtObject { id: shine; property real x: -80 }
                SequentialAnimation {
                    running: root.fill > 0
                    loops: Animation.Infinite
                    NumberAnimation { target: shine; property: "x"; from: -80; to: body.width; duration: 900 }
                }
            }
        }

        Row {
            anchors.centerIn: parent
            spacing: 10
            Sym {
                anchors.verticalCenter: parent.verticalCenter
                name: root.done ? "check" : "rocket"
                size: 22
                color: root.fill > 0.5 ? Theme.onAccent : Theme.accent
                rotation: Math.max(0, root.fill) * -25
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: root.text
                size: "title"
                color: root.fill > 0.5 ? Theme.onAccent : Theme.fg
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
    function keyDown() { if (!charge.running) begin(); }
    function keyUp() { cancel(); }
}
