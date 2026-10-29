import QtQuick

// Рисует «жидкость» шейдером shaders/goo.frag: полоску края, каплю и тело,
// слитые мягким минимумом. Все размеры — в пикселях этого элемента.
//     Goo { band: Qt.rect(…); drop: Qt.vector4d(cx, cy, rx, ry); body: Qt.rect(…); bodyR: 20; color: Theme.accent }
ShaderEffect {
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

    blending: true
    fragmentShader: Qt.resolvedUrl("shaders/goo.frag.qsb")
}
