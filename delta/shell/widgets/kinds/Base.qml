import QtQuick
import qs.widgets

// Общее у содержимого виджетов. Карточка (WidgetCard) отдаёт данные виджета,
// цвета и единицы cw/ch/cm — 1 % ширины, высоты и меньшей стороны карточки
// (как cqw, cqh, cqmin в концепте). Все размеры внутри — только через них,
// поэтому содержимое масштабируется вместе с виджетом, а не «уезжает».
// Без карточки (меню, превью) единицы считаются от собственного размера.
Item {
    property Item card: null

    property var item: card ? card.item : ({})
    property string place: card ? card.place : "desktop"
    readonly property bool lock: place === "lock"
    property bool editing: card ? card.editing : false
    // цвета текста: на стекле — из темы, без фона и на экране блокировки — белые
    property QtObject pal: card ? card.pal : white
    readonly property QtObject white: QtObject {
        property color c1: "#ffffff"
        property color c2: Qt.rgba(1, 1, 1, 0.88)
        property color c3: Qt.rgba(1, 1, 1, 0.78)
        property color track: Qt.rgba(1, 1, 1, 0.2)
    }
    property real cw: (card ? card.width : width) / 100
    property real ch: (card ? card.height : height) / 100
    property real cm: Math.min(cw, ch)

    readonly property string mode: (item && item.mode) || WidgetTypes.defaultMode(place, item ? item.id : "")
}
