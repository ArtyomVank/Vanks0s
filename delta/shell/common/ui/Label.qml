import QtQuick
import qs.common

// Текст в стиле Delta. size: caption 12 · small 13 · body 14 · title 17 · h1 24 · display 40.
//     Label { text: "Wi-Fi"; size: "title"; tone: 2 }
Text {
    property string size: "body"
    // 1 — основной, 2 — вторичный, 3 — подсказки
    property int tone: 1

    readonly property var sizes: ({ caption: 12, small: 13, body: 14, title: 17, h1: 24, display: 40 })

    color: tone === 3 ? Theme.fg3 : tone === 2 ? Theme.fg2 : Theme.fg
    font.family: size === "h1" || size === "display" ? Theme.fontDisplay : Theme.font
    font.pixelSize: sizes[size] ?? 14
    font.weight: size === "title" || size === "h1" || size === "display" ? Font.DemiBold : Font.Normal
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
}
