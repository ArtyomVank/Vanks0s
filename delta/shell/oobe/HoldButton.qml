import QtQuick
import QtQuick.Shapes
import Quickshell.Widgets
import qs.common
import qs.common.ui

// «Начать»: кнопку нужно зажать — снизу поднимается жидкость цвета акцента,
// по её поверхности бегут две волны, внутри всплывают пузырьки. Надпись под
// уровнем жидкости перекрашивается. Отпустили раньше — жидкость стекает
// обратно с пружинкой. Заполнилась — completed().
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
        Sounds.hold("oobe-fill");
    }
    // повторный запуск настройки: снова пустая
    function reset() {
        charge.stop();
        drain.stop();
        done = false;
        fill = 0;
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
    NumberAnimation { id: drain; target: root; property: "fill"; to: 0; duration: 620; easing.type: Easing.OutBack; easing.overshoot: 1.6 }

    // волна: фаза бежит, пока есть жидкость; у пустой и полной кнопки поверхность ровная
    property real phase: 0
    readonly property real level: Math.max(0, Math.min(1, fill))
    readonly property real amp: root.done ? 0 : 5 * Math.sin(Math.PI * Math.min(1, level * 1.15))
    FrameAnimation {
        running: root.fill > 0.002 && !root.done
        onTriggered: root.phase += frameTime * (4 + root.level * 5)
    }

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

        // поверхность: уровень снизу вверх; волна чуть выходит за края, чтобы у
        // полной кнопки не оставалось щели сверху
        readonly property real surface: (height + 2 * root.amp + 4) * (1 - root.level) - root.amp - 2

        function wave(shift, k, a) {
            const pts = [];
            const w = width, h = height;
            for (let x = -8; x <= w + 8; x += 6)
                pts.push(Qt.point(x, surface + a * Math.sin(x * k + root.phase + shift)));
            pts.push(Qt.point(w + 8, h + 4));
            pts.push(Qt.point(-8, h + 4));
            return pts;
        }

        Item {
            id: liquid
            anchors.fill: parent
            visible: root.fill > 0.002
            layer.enabled: visible
            layer.samples: 4

            // дальняя волна — светлее и в противофазе
            Shape {
                anchors.fill: parent
                ShapePath {
                    strokeWidth: -1
                    fillColor: Qt.rgba(Qt.lighter(Theme.accent, 1.4).r, Qt.lighter(Theme.accent, 1.4).g, Qt.lighter(Theme.accent, 1.4).b, 0.55)
                    PathPolyline { path: body.wave(Math.PI * 0.8, 0.045, root.amp * 1.2) }
                }
            }
            Shape {
                anchors.fill: parent
                ShapePath {
                    strokeWidth: -1
                    fillGradient: LinearGradient {
                        x1: 0; y1: body.surface - root.amp; x2: 0; y2: body.height
                        GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.15) }
                        GradientStop { position: 1; color: Qt.darker(Theme.accent, 1.35) }
                    }
                    PathPolyline { path: body.wave(0, 0.06, root.amp) }
                }
            }

            // пузырьки всплывают от дна к поверхности и лопаются у неё
            Repeater {
                model: 7
                delegate: Rectangle {
                    id: bub
                    required property int index
                    readonly property real seed: (index * 0.137 + 0.05) % 1
                    readonly property real run: (root.phase * (0.07 + seed * 0.05) + seed) % 1
                    readonly property real room: Math.max(0, body.height - body.surface)
                    width: 3 + seed * 5
                    height: width
                    radius: width / 2
                    x: body.width * (0.12 + ((index * 0.31) % 1) * 0.76) + Math.sin(root.phase * 1.3 + index) * 3
                    y: body.height - run * room - height
                    color: "white"
                    opacity: room > 10 && !root.done ? 0.45 * (1 - run) : 0
                }
            }
        }

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
            y: Math.max(0, body.surface)
            width: body.width
            height: Math.max(0, body.height - y)
            clip: true
            visible: root.fill > 0.002
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
    function keyDown() { if (!charge.running) begin(); }
    function keyUp() { cancel(); }
}
