import QtQuick
import Quickshell
import qs.common
import qs.common.ui
import qs.docks

// Часы и дата. Сбоку экрана — часы в две строки. Настройки (Доки → Модули):
// docks.top.opts.calendarDate — дата рядом, calendarSeconds — секунды.
Item {
    id: root

    property bool vertical: false
    property bool full: true
    property ShellScreen screen
    property bool hidden: false

    readonly property bool showDate: DockService.opt("calendarDate", true) !== false
    // «Акрил» по умолчанию с секундами (они бледнее) и месяцем целиком
    readonly property bool seconds: DockService.opt("calendarSeconds", Theme.acrylic) === true
    SystemClock { id: clock; precision: root.seconds ? SystemClock.Seconds : SystemClock.Minutes }

    readonly property var days: ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
    readonly property var months: ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]
    readonly property date now: clock.date
    readonly property string time: Qt.formatTime(now, seconds ? "HH:mm:ss" : "HH:mm")
    readonly property var monthsFull: ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    readonly property string day: I18n.ru ? (Theme.acrylic ? days[now.getDay()].charAt(0).toUpperCase() + days[now.getDay()].slice(1) + ", " + now.getDate() + " " + monthsFull[now.getMonth()]
                                                           : days[now.getDay()] + ", " + now.getDate() + " " + months[now.getMonth()])
        : Qt.locale(I18n.locale).toString(now, "ddd, d MMM").replace(/\.(?=,|$)/g, "")

    implicitWidth: vertical ? col.implicitWidth : row.implicitWidth
    implicitHeight: vertical ? col.implicitHeight : 20

    Row {
        id: row
        visible: !root.vertical
        anchors.centerIn: parent
        spacing: 8
        Row {
            anchors.verticalCenter: parent.verticalCenter
            Label { text: root.time.slice(0, 5); num: true; size: "small"; color: Theme.fg; font.weight: Font.Bold; font.features: { "tnum": 1 } }
            Label { visible: root.seconds; text: root.time.slice(5); num: true; size: "small"; color: Theme.acrylic ? Theme.fg3 : Theme.fg; font.weight: Font.Bold; font.features: { "tnum": 1 } }
        }
        Label { visible: root.full && root.showDate; text: root.day; size: "small"; tone: 2; font.weight: Font.Medium }
    }
    Column {
        id: col
        visible: root.vertical
        anchors.centerIn: parent
        Label { anchors.horizontalCenter: parent.horizontalCenter; text: root.time.slice(0, 2); num: true; size: "small"; font.weight: Font.Bold }
        Label { anchors.horizontalCenter: parent.horizontalCenter; text: root.time.slice(3, 5); num: true; size: "small"; tone: 2; font.weight: Font.Bold }
    }
}
