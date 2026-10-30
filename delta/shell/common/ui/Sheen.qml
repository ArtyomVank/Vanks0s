import QtQuick
import qs.common

// «Жидкое стекло» поверх подложки (shaders/sheen.frag): скос-линза с
// бликом и переливом по кромке, матовость (Theme.frost) и капли, стекающие
// рывками (appearance.drops). Виден только в стиле «Жидкое стекло».
// Кладётся первым ребёнком подложки — тогда содержимое рисуется поверх.
//     Rectangle { radius: 18; color: Theme.glass; Sheen { radius: 18 } }
ShaderEffect {
    id: root

    property real radius: Theme.radius
    property real strength: 1
    // маленьким плиткам (кнопки, превью) капли ни к чему
    property bool withDrops: width >= 120 && height >= 60
    readonly property size area: Qt.size(width, height)
    readonly property real frost: Theme.frost
    readonly property real time: LiquidClock.time
    readonly property real drops: withDrops && LiquidClock.drops ? 1 : 0
    // у каждой панели свой рисунок капель — от её размера
    readonly property real seed: (Math.round(width) * 7 + Math.round(height) * 13) % 97
    readonly property real lightBg: Theme.light ? 1 : 0

    anchors.fill: parent
    visible: Theme.liquid && width > 2 && height > 2
    fragmentShader: Qt.resolvedUrl("shaders/sheen.frag.qsb")

    Component.onCompleted: LiquidClock.users++
    Component.onDestruction: LiquidClock.users--
}
