import QtQuick
import qs.common
import qs.common.ui

// Рисует «жидкость» шейдером shaders/goo.frag: полоску края, каплю и тело,
// слитые мягким минимумом. Все размеры — в пикселях этого элемента.
//     Goo { band: Qt.rect(…); drop: Qt.vector4d(cx, cy, rx, ry); body: Qt.rect(…); bodyR: 20; color: Theme.accent }
// glass — в стиле «Жидкое стекло» залить фигуру линзой с обоями за ней
// (shaders/goo-glass.frag): стекло повторяет форму при любой деформации.
ShaderEffect {
    id: root

    // имена совпадают с uniform'ами шейдера
    property rect band: Qt.rect(0, 0, 0, 0)
    property vector4d drop: Qt.vector4d(0, 0, 0, 0)
    property rect body: Qt.rect(0, 0, 0, 0)
    property real bodyR: 0
    property real k: 14
    property real glow: 0
    property color color: "white"
    // выпуклость под курсором и обводка — у панели в покое (Island)
    property vector4d drop2: Qt.vector4d(0, 0, 0, 0)
    property color strokeColor: "transparent"
    property real strokeW: 1

    readonly property size area: Qt.size(width, height)
    readonly property vector4d fill: Qt.vector4d(color.r, color.g, color.b, color.a)
    readonly property vector4d stroke: Qt.vector4d(strokeColor.r, strokeColor.g, strokeColor.b, strokeColor.a)

    // --- жидкое стекло ---
    property bool glass: false
    readonly property bool useGlass: glass && Theme.liquid
    property real bezel: 16
    readonly property real frost: Theme.frost
    readonly property real lightBg: Theme.light ? 1 : 0
    WallLens { id: lens; target: root; active: root.useGlass }
    property variant source: lens.texture
    readonly property real hasWall: lens.ready ? 1 : 0
    readonly property point origin: lens.origin
    readonly property vector4d wallRect: lens.wallRect

    blending: true
    fragmentShader: Qt.resolvedUrl(useGlass ? "shaders/goo-glass.frag.qsb" : "shaders/goo.frag.qsb")
}
