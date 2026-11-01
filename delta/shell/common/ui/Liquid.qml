import QtQuick
import QtQuick.Shapes
import qs.common

// Жидкость, которая поднимается снизу вверх: level 0…1, по поверхности бегут
// две волны, внутри всплывают пузырьки. По форме кнопки её обрезает родитель
// (ClippingRectangle). surface — высота поверхности: под ней надпись можно
// перекрасить. still — заполнилась: волны и пузырьки затихают.
//     Liquid { anchors.fill: parent; level: charge.level; still: charge.done }
Item {
    id: root

    property real level: 0
    property bool still: false
    property color color: Theme.accent
    property real waveHeight: 5

    // у пустой и полной кнопки поверхность ровная
    readonly property real amp: still ? 0 : waveHeight * Math.sin(Math.PI * Math.min(1, level * 1.15))
    // волна чуть выходит за края, чтобы у полной кнопки не оставалось щели сверху
    readonly property real surface: (height + 2 * amp + 4) * (1 - level) - amp - 2
    property real phase: 0

    visible: level > 0.002
    layer.enabled: visible
    layer.samples: 4

    FrameAnimation {
        running: root.visible && !root.still
        onTriggered: root.phase += frameTime * (4 + root.level * 5)
    }

    // k — частота на пиксель: на узкой кнопке волн столько же, сколько на широкой
    function wave(shift, k, a) {
        const pts = [];
        const w = width, h = height, kk = k * 320 / Math.max(120, w);
        for (let x = -8; x <= w + 8; x += 6)
            pts.push(Qt.point(x, surface + a * Math.sin(x * kk + phase + shift)));
        pts.push(Qt.point(w + 8, h + 4));
        pts.push(Qt.point(-8, h + 4));
        return pts;
    }

    // дальняя волна — светлее и в противофазе
    Shape {
        anchors.fill: parent
        ShapePath {
            strokeWidth: -1
            fillColor: Qt.rgba(Qt.lighter(root.color, 1.4).r, Qt.lighter(root.color, 1.4).g, Qt.lighter(root.color, 1.4).b, 0.55)
            PathPolyline { path: root.wave(Math.PI * 0.8, 0.045, root.amp * 1.2) }
        }
    }
    Shape {
        anchors.fill: parent
        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0; y1: root.surface - root.amp; x2: 0; y2: root.height
                GradientStop { position: 0; color: Qt.lighter(root.color, 1.15) }
                GradientStop { position: 1; color: Qt.darker(root.color, 1.35) }
            }
            PathPolyline { path: root.wave(0, 0.06, root.amp) }
        }
    }

    // пузырьки всплывают от дна к поверхности и лопаются у неё
    Repeater {
        model: 7
        delegate: Rectangle {
            required property int index
            readonly property real seed: (index * 0.137 + 0.05) % 1
            readonly property real run: (root.phase * (0.07 + seed * 0.05) + seed) % 1
            readonly property real room: Math.max(0, root.height - root.surface)
            width: (3 + seed * 5) * Math.min(1, root.height / 72 + 0.3)
            height: width
            radius: width / 2
            x: root.width * (0.12 + ((index * 0.31) % 1) * 0.76) + Math.sin(root.phase * 1.3 + index) * 3
            y: root.height - run * room - height
            color: "white"
            opacity: room > 10 && !root.still ? 0.45 * (1 - run) : 0
        }
    }
}
