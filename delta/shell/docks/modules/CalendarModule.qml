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
    readonly property bool seconds: DockService.opt("calendarSeconds", false) === true
    SystemClock { id: clock; precision: root.seconds ? SystemClock.Seconds : SystemClock.Minutes }

    readonly property var days: ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
    readonly property var months: ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]
    readonly property date now: clock.date
    readonly property string time: Qt.formatTime(now, seconds ? "HH:mm:ss" : "HH:mm")
    readonly property string day: days[now.getDay()] + ", " + now.getDate() + " " + months[now.getMonth()]

    implicitWidth: vertical ? col.implicitWidth : row.implicitWidth
    implicitHeight: vertical ? col.implicitHeight : 20

    Row {
        id: row
        visible: !root.vertical
        anchors.centerIn: parent
        spacing: 8
        Label { text: root.time; size: "small"; color: Theme.fg; font.weight: Font.Bold; font.features: { "tnum": 1 } }
        Label { visible: root.full && root.showDate; text: root.day; size: "small"; tone: 2; font.weight: Font.Medium }
    }
    Column {
        id: col
        visible: root.vertical
        anchors.centerIn: parent
        Label { anchors.horizontalCenter: parent.horizontalCenter; text: root.time.slice(0, 2); size: "small"; font.weight: Font.Bold }
        Label { anchors.horizontalCenter: parent.horizontalCenter; text: root.time.slice(3, 5); size: "small"; tone: 2; font.weight: Font.Bold }
    }
}
