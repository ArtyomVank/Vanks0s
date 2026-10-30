import QtQuick

// Рисует item (цифры часов) «стеклом» или «пустыми внутри» — по его форме
// целиком (shaders/glassface.frag), без двойных наложений линий и контуров.
// Сам item прячется, пока GlassFace видим. Кладётся рядом с item (тот же
// родитель); item рисуется сплошным непрозрачным цветом, цвет задаёт tint.
//     Text { id: digits; color: "white"; … }
//     GlassFace { item: digits; hollow: true; rim: 2; tint: Theme.accent }
ShaderEffect {
    id: root

    property Item item
    property bool hollow: false
    // ширина кромки, px
    property real rim: 2
    // заливка стекла
    property real fill: 0.2
    property color tint: "#ffffff"

    // поле вокруг: у края item кромке тоже нужно место
    readonly property real pad: Math.ceil(rim + 2)
    x: item ? item.x - pad : 0
    y: item ? item.y - pad : 0
    width: item ? item.width + 2 * pad : 0
    height: item ? item.height + 2 * pad : 0

    ShaderEffectSource {
        id: src
        sourceItem: root.visible ? root.item : null
        hideSource: root.visible
        sourceRect: root.item ? Qt.rect(-root.pad, -root.pad, root.item.width + 2 * root.pad, root.item.height + 2 * root.pad) : Qt.rect(0, 0, 0, 0)
        visible: false
        smooth: true
    }
    property variant source: src
    readonly property size texel: Qt.size(1 / Math.max(1, width), 1 / Math.max(1, height))
    readonly property real hollowK: hollow ? 1 : 0
    readonly property vector4d tintV: Qt.vector4d(tint.r, tint.g, tint.b, tint.a)

    fragmentShader: Qt.resolvedUrl("shaders/glassface.frag.qsb")
}
