import QtQuick
import qs.common

// Блик «жидкого стекла» поверх подложки: светлая кромка, свечение у края и
// отблеск сверху (shaders/sheen.frag). Виден только в стиле «Жидкое стекло».
// Кладётся первым ребёнком подложки — тогда содержимое рисуется поверх.
//     Rectangle { radius: 18; color: Theme.glass; Sheen { radius: 18 } }
ShaderEffect {
    property real radius: Theme.radius
    property real strength: 1
    readonly property size area: Qt.size(width, height)

    anchors.fill: parent
    visible: Theme.liquid && width > 2 && height > 2
    fragmentShader: Qt.resolvedUrl("shaders/sheen.frag.qsb")
}
