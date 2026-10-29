import QtQuick
import qs.common
import qs.common.ui

// Текст виджета: размер задаётся в пикселях от размера виджета (px), а не
// пресетом, — так шрифт растёт и уменьшается вместе с виджетом.
//     WText { px: 24 * cm; text: "+7°"; display: true }
Label {
    property real px: 14
    // крупные цифры — шрифт заголовков (Inter Tight), как в концепте
    property bool display: false

    font.pixelSize: Math.max(1, Math.round(px))
    font.family: display ? Theme.fontDisplay : Theme.font
    font.weight: display ? Font.Bold : Font.Normal
    textFormat: Text.PlainText
    maximumLineCount: 1
    lineHeight: 1.0
}
