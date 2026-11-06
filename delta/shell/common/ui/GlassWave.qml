import QtQuick
import qs.common

// Стеклянная волна по элементу target (shaders/glasswave.frag): кольцо из
// точки center расходится до краёв и преломляет то, что под ним. Пока волна
// идёт, target рисуется только через неё (hideSource). Волна тяжёлая: толчок
// в центре, медленный разгон гребня, широкое тело и долгое затухание.
//     GlassWave { anchors.fill: bg; target: bg }
//     wave.play(Qt.point(x, y))           // во всю силу (разблокировка)
//     wave.play(Qt.point(x, y), 0.6)      // слабее (новый виджет)
ShaderEffect {
    id: root

    property Item target: null
    // сила 0…1 и время, мс
    property real power: 1
    property int duration: 1500

    property point center: Qt.point(width / 2, height / 2)
    property real radius: 0
    property real width0: 110
    property real strength: 0
    property real thump: 0

    readonly property vector2d res: Qt.vector2d(width, height)
    readonly property real rim: 1
    // ширина гребня растёт вместе с кольцом
    property real waveWidth: width0
    property var src: ShaderEffectSource {
        sourceItem: root.target
        hideSource: anim.running
        live: true
    }

    visible: anim.running
    fragmentShader: Qt.resolvedUrl("shaders/glasswave.frag.qsb")

    // ms — своя длительность этого раза (иначе duration)
    property int playMs: duration
    function play(c, p, ms) {
        center = c;
        power = p ?? 1;
        playMs = ms ?? duration;
        anim.restart();
    }

    readonly property real farthest: {
        const dx = Math.max(center.x, width - center.x), dy = Math.max(center.y, height - center.y);
        return Math.sqrt(dx * dx + dy * dy) + 220;
    }

    ParallelAnimation {
        id: anim
        // разгон чуть с задержкой — масса; потом гребень катится и тормозит
        NumberAnimation { target: root; property: "radius"; from: 0; to: root.farthest; duration: root.playMs * Theme.anim.k; easing.type: Easing.InOutQuad }
        SequentialAnimation {
            NumberAnimation { target: root; property: "thump"; from: 0; to: root.power; duration: 110 * Theme.anim.k; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "thump"; to: 0; duration: 420 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
        }
        NumberAnimation { target: root; property: "waveWidth"; from: root.width0 * (0.6 + 0.4 * root.power); to: root.width0 * (1.6 + root.power); duration: root.playMs * Theme.anim.k; easing.type: Easing.OutQuad }
        SequentialAnimation {
            NumberAnimation { target: root; property: "strength"; from: 0; to: root.power; duration: 220 * Theme.anim.k; easing.type: Easing.OutQuad }
            PauseAnimation { duration: 260 * Theme.anim.k }
            NumberAnimation { target: root; property: "strength"; to: 0; duration: (root.playMs - 480) * Theme.anim.k; easing.type: Easing.InQuad }
        }
    }
}
