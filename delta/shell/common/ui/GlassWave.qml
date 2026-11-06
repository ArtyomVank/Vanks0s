import QtQuick
import qs.common

// Стеклянная волна по элементу target (shaders/glasswave.frag): кольцо из
// точки center расходится до краёв и преломляет то, что под ним. Пока волна
// идёт, target рисуется только через неё (hideSource).
//     GlassWave { anchors.fill: bg; target: bg }
//     wave.play(Qt.point(x, y))           // во всю силу (разблокировка)
//     wave.play(Qt.point(x, y), 0.45)     // слабее (новый виджет)
ShaderEffect {
    id: root

    property Item target: null
    // сила 0…1 и время, мс
    property real power: 1
    property int duration: 1100

    property point center: Qt.point(width / 2, height / 2)
    property real radius: 0
    property real width0: 70
    property real strength: 0

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

    function play(c, p) {
        center = c;
        power = p ?? 1;
        anim.restart();
    }

    readonly property real farthest: {
        const dx = Math.max(center.x, width - center.x), dy = Math.max(center.y, height - center.y);
        return Math.sqrt(dx * dx + dy * dy) + 220;
    }

    ParallelAnimation {
        id: anim
        NumberAnimation { target: root; property: "radius"; from: 0; to: root.farthest; duration: root.duration * Theme.anim.k; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "waveWidth"; from: root.width0 * (0.6 + 0.4 * root.power); to: root.width0 * (1.6 + root.power); duration: root.duration * Theme.anim.k; easing.type: Easing.OutQuad }
        SequentialAnimation {
            NumberAnimation { target: root; property: "strength"; from: 0; to: root.power; duration: 140 * Theme.anim.k; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "strength"; to: 0; duration: (root.duration - 140) * Theme.anim.k; easing.type: Easing.InQuad }
        }
    }
}
