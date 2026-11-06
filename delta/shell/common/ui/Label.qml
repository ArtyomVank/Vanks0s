import QtQuick
import qs.common

// Текст в стиле Delta. size: caption 12 · small 13 · body 14 · title 17 · h1 24 · display 40.
//     Label { text: "Wi-Fi"; size: "title"; tone: 2 }
// num — цифры (время, проценты): в стиле «Акрил» моноширинным шрифтом.
Text {
    property string size: "body"
    property bool num: false
    // 1 — основной, 2 — вторичный, 3 — подсказки
    property int tone: 1

    readonly property var sizes: ({ caption: 12, small: 13, body: 14, title: 17, h1: 24, display: 40 })

    color: tone === 3 ? Theme.fg3 : tone === 2 ? Theme.fg2 : Theme.fg
    font.family: num && Theme.round ? Theme.fontNum : size === "h1" || size === "display" ? Theme.fontDisplay : Theme.font
    font.pixelSize: sizes[size] ?? 14
    font.weight: size === "title" || size === "h1" || size === "display" ? Font.DemiBold : Font.Normal
    elide: Text.ElideRight
    // подсветка текста (appearance.highlight): только у основного и вторичного
    style: Theme.glowText && tone < 3 ? Text.Outline : Text.Normal
    styleColor: Theme.textGlow
    verticalAlignment: Text.AlignVCenter
}
