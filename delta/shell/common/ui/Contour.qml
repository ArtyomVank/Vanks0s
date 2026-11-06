import QtQuick
import qs.common

// «Акрил»: светящийся контур поверх стеклянной подложки (shaders/contour.frag)
// — тонкая кромка света сверху слева, тёплый отсвет акцента снизу справа и
// мягкий свет у верхнего края. Обычно его кладёт Sheen; отдельно — так:
//     Rectangle { radius: 20; color: Theme.glass; Contour { radius: 20 } }
ShaderEffect {
    property real radius: Theme.radius
    property real strength: 1
    // показать независимо от стиля (превью стиля в «Стилях и темах»)
    property bool force: false

    readonly property size area: Qt.size(width, height)
    readonly property real lightBg: Theme.light ? 1 : 0
    readonly property vector4d warm: Qt.vector4d(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.light ? 0.35 : 0.55)

    anchors.fill: parent
    visible: (force || Theme.acrylic) && width > 2 && height > 2
    fragmentShader: Qt.resolvedUrl("shaders/contour.frag.qsb")
}
