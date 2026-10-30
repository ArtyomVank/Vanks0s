import QtQuick
import qs.common

// «Жидкое стекло» поверх подложки (shaders/sheen.frag): линза — в середине
// чистое стекло, у края фон изгибается, по кромке тонкий блик. Виден только
// в стиле «Жидкое стекло». Кладётся первым ребёнком подложки — тогда
// содержимое рисуется поверх.
//     Rectangle { radius: 18; color: Theme.glass; Sheen { radius: 18; refract: true } }
//
// refract — сам рисовать преломлённые обои (виджеты: за ними обои).
// Лаунчеру и меню, которые бывают поверх окон, это не подходит: им фон даёт
// размытие Hyprland, а здесь рисуются только блик и свечение. Доки рисуют
// стекло сами, в шейдере жидкости (docks/parts/Goo).
ShaderEffect {
    id: root

    property real radius: Theme.radius
    property real strength: 1
    property bool refract: false

    readonly property size area: Qt.size(width, height)
    readonly property real frost: Theme.frost
    readonly property real lightBg: Theme.light ? 1 : 0
    // тон стекла: прозрачное — едва тонировано, матовое — заметнее
    readonly property vector4d tint: Qt.vector4d(Theme.base.r, Theme.base.g, Theme.base.b, 0.12 + 0.28 * Theme.frost)

    WallLens { id: lens; target: root; active: root.refract && Theme.liquid }
    property variant source: lens.texture
    readonly property real hasWall: lens.ready ? 1 : 0
    readonly property point origin: lens.origin
    readonly property vector4d wallRect: lens.wallRect

    anchors.fill: parent
    visible: Theme.liquid && width > 2 && height > 2
    fragmentShader: Qt.resolvedUrl("shaders/sheen.frag.qsb")
}
