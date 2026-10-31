import QtQuick
import qs.common
import qs.services
import qs.widgets.parts

// «Полосы»: спектр того, что сейчас играет (services/Spectrum — cava).
// Тонкие столбики от нижнего края; высокие ярче. Тишина — ровный ряд точек.
Base {
    id: root

    // спектр считается, только пока виджет виден
    property bool held: false
    function sync() {
        const want = visible;
        if (want === held) return;
        held = want;
        if (want) Spectrum.acquire(); else Spectrum.release();
    }
    onVisibleChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: if (held) Spectrum.release()

    readonly property int n: Spectrum.bars * 2
    readonly property var vals: Spectrum.values
    readonly property real pitch: width / n

    Repeater {
        model: root.n
        delegate: Rectangle {
            required property int index
            readonly property real v: (root.vals[index] ?? 0) / 100
            width: Math.max(1.5, root.pitch * 0.42)
            height: Math.max(width, root.height * v)
            radius: width / 2
            x: index * root.pitch + (root.pitch - width) / 2
            y: root.height - height
            color: root.pal.c1
            opacity: 0.32 + 0.68 * Math.min(1, v * 1.4)
            Behavior on height { NumberAnimation { duration: 70 * Theme.anim.k } }
        }
    }

    WText {
        anchors.centerIn: parent
        visible: Spectrum.missing
        text: "Нужна программа cava"
        px: 8 * root.cm
        color: root.pal.c2
    }
}
