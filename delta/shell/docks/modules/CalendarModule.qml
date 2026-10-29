import QtQuick
import Quickshell
import qs.common
import qs.common.ui

// Часы и дата. Сбоку экрана — часы в две строки.
Item {
    id: root

    property bool vertical: false
    property bool full: true
    property ShellScreen screen
    property bool hidden: false

    SystemClock { id: clock; precision: SystemClock.Minutes }

    readonly property var days: ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
    readonly property var months: ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]
    readonly property date now: clock.date
    readonly property string time: Qt.formatTime(now, "HH:mm")
    readonly property string day: days[now.getDay()] + ", " + now.getDate() + " " + months[now.getMonth()]

    implicitWidth: vertical ? col.implicitWidth : row.implicitWidth
    implicitHeight: vertical ? col.implicitHeight : 20

    Row {
        id: row
        visible: !root.vertical
        anchors.centerIn: parent
        spacing: 8
        Label { text: root.time; size: "small"; color: Theme.fg; font.weight: Font.Bold; font.features: { "tnum": 1 } }
        Label { visible: root.full; text: root.day; size: "small"; tone: 2; font.weight: Font.Medium }
    }
    Column {
        id: col
        visible: root.vertical
        anchors.centerIn: parent
        Label { anchors.horizontalCenter: parent.horizontalCenter; text: root.time.slice(0, 2); size: "small"; font.weight: Font.Bold }
        Label { anchors.horizontalCenter: parent.horizontalCenter; text: root.time.slice(3); size: "small"; tone: 2; font.weight: Font.Bold }
    }
}
