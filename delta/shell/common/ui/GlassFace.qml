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
    // плотность заливки стекла: 0.5 — как у часов на телефоне (цвет виден,
    // обои сквозь него тоже)
    property real fill: 0.5
    property color tint: "#ffffff"
    // мягкая тень под стеклом, радиус в px (у пустых внутри её нет)
    property real shadow: hollow ? 0 : Math.max(4, Math.min(16, (item ? item.height : 0) * 0.08))

    // поле вокруг: у края item кромке и тени тоже нужно место
    readonly property real pad: Math.ceil(Math.max(rim, shadow * 1.3) + 2)
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
    readonly property real shadowR: shadow
    // где сама форма внутри текстуры (без полей): градиент заливки — по ней
    readonly property vector4d box: Qt.vector4d(pad / Math.max(1, width), pad / Math.max(1, height),
                                                1 - pad / Math.max(1, width), 1 - pad / Math.max(1, height))

    fragmentShader: Qt.resolvedUrl("shaders/glassface.frag.qsb")
}
