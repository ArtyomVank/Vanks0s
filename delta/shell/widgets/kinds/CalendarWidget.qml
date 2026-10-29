pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.common
import qs.widgets.parts

// Календарь: «День» (число и день недели) или «Месяц» (сетка месяца).
Base {
    id: root

    SystemClock { id: clock; precision: SystemClock.Hours }

    readonly property var now: clock.date
    readonly property var loc: Qt.locale("ru_RU")
    function cap(s) { return s.charAt(0).toUpperCase() + s.slice(1); }
    readonly property string weekday: cap(loc.toString(now, "dddd"))
    readonly property string monthYear: cap(loc.standaloneMonthName(now.getMonth(), Locale.LongFormat)) + " " + now.getFullYear()

    // ---- день ----
    Item {
        anchors.fill: parent
        visible: !root.lock && root.mode !== "month"
        WCaption { cm: root.cm; text: root.weekday; color: root.pal.c2; width: parent.width }
        WText {
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 3 * root.cm
            text: root.now.getDate()
            px: 40 * root.cm
            display: true
            color: root.pal.c1
        }
        WText { anchors.bottom: parent.bottom; width: parent.width; text: root.monthYear; px: 8 * root.cm; color: root.pal.c3 }
    }

    // ---- месяц ----
    Item {
        id: month
        anchors.fill: parent
        visible: !root.lock && root.mode === "month"

        readonly property int first: (new Date(root.now.getFullYear(), root.now.getMonth(), 1).getDay() + 6) % 7
        readonly property int days: new Date(root.now.getFullYear(), root.now.getMonth() + 1, 0).getDate()
        readonly property int weeks: Math.ceil((first + days) / 7)
        readonly property real cellW: width / 7
        readonly property real cellH: (height - head.height - root.ch * 3) / (weeks + 1)
        readonly property real fs: Math.min(cellH * 0.55, cellW * 0.42)

        WCaption { id: head; cm: root.cm; text: root.monthYear; color: root.pal.c2; width: parent.width }
        Grid {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            columns: 7
            Repeater {
                model: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
                delegate: Item {
                    required property string modelData
                    width: month.cellW; height: month.cellH
                    WText { anchors.centerIn: parent; text: parent.modelData; px: month.fs * 0.85; color: root.pal.c3 }
                }
            }
            Repeater {
                model: month.weeks * 7
                delegate: Item {
                    id: day
                    required property int index
                    readonly property int n: index - month.first + 1
                    readonly property bool today: n === root.now.getDate()
                    width: month.cellW; height: month.cellH
                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height) * 0.92; height: width
                        radius: width / 2
                        color: Theme.accent
                        visible: day.today
                    }
                    WText {
                        anchors.centerIn: parent
                        visible: day.n >= 1 && day.n <= month.days
                        text: day.n
                        px: month.fs
                        font.weight: day.today ? Font.Bold : Font.Normal
                        color: day.today ? Theme.onAccent : root.pal.c1
                    }
                }
            }
        }
    }

    // ---- экран блокировки ----
    Item {
        anchors.fill: parent
        visible: root.lock

        // «День»: число и день недели
        Row {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.mode !== "month"
            spacing: 6 * root.cm
            WText { anchors.verticalCenter: parent.verticalCenter; text: root.now.getDate(); px: Math.min(46 * root.ch, 20 * root.cw); display: true; font.weight: Font.ExtraBold; color: root.pal.c1 }
            WText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.weekday + "\nСобытий нет"
                maximumLineCount: 2
                lineHeight: 1.2
                px: Math.min(16 * root.ch, 7 * root.cw)
                color: root.pal.c1
                opacity: 0.85
            }
        }

        // «Месяц»: та же сетка, что и на рабочем столе, но белым по стеклу
        Item {
            id: lockMonth
            anchors.fill: parent
            visible: root.mode === "month"

            readonly property int first: (new Date(root.now.getFullYear(), root.now.getMonth(), 1).getDay() + 6) % 7
            readonly property int days: new Date(root.now.getFullYear(), root.now.getMonth() + 1, 0).getDate()
            readonly property int weeks: Math.ceil((first + days) / 7)
            readonly property real cellW: width / 7
            readonly property real cellH: (height - lockHead.height - root.ch * 2) / (weeks + 1)
            readonly property real fs: Math.min(cellH * 0.55, cellW * 0.42)

            WCaption { id: lockHead; cm: root.cm; text: root.monthYear; color: root.pal.c1; width: parent.width }
            Grid {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                columns: 7
                Repeater {
                    model: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
                    delegate: Item {
                        required property string modelData
                        width: lockMonth.cellW; height: lockMonth.cellH
                        WText { anchors.centerIn: parent; text: parent.modelData; px: lockMonth.fs * 0.85; color: root.pal.c1; opacity: 0.6 }
                    }
                }
                Repeater {
                    model: lockMonth.weeks * 7
                    delegate: Item {
                        id: lday
                        required property int index
                        readonly property int n: index - lockMonth.first + 1
                        readonly property bool today: n === root.now.getDate()
                        width: lockMonth.cellW; height: lockMonth.cellH
                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height) * 0.92; height: width
                            radius: width / 2
                            color: Theme.accent
                            visible: lday.today
                        }
                        WText {
                            anchors.centerIn: parent
                            visible: lday.n >= 1 && lday.n <= lockMonth.days
                            text: lday.n
                            px: lockMonth.fs
                            font.weight: lday.today ? Font.Bold : Font.Normal
                            color: lday.today ? Theme.onAccent : root.pal.c1
                        }
                    }
                }
            }
        }
    }
}
