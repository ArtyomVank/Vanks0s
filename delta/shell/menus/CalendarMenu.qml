pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.launcher.parts

// Календарь: сетка месяца с понедельника, сегодня подсвечено, листание месяцев.
Item {
    id: root

    implicitWidth: 320
    implicitHeight: col.implicitHeight
    signal close()

    property date now: new Date()
    // смещение показанного месяца от текущего
    property int offset: 0
    onVisibleChanged: if (visible) { now = new Date(); offset = 0; }

    // в полночь «сегодня» переезжает
    Timer {
        interval: 60000
        repeat: true
        running: root.visible
        onTriggered: root.now = new Date()
    }

    readonly property var months: ["январь", "февраль", "март", "апрель", "май", "июнь", "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"]
    readonly property var monthsGen: ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    readonly property var weekdays: ["воскресенье", "понедельник", "вторник", "среда", "четверг", "пятница", "суббота"]

    readonly property int year: new Date(now.getFullYear(), now.getMonth() + offset, 1).getFullYear()
    readonly property int month: new Date(now.getFullYear(), now.getMonth() + offset, 1).getMonth()

    readonly property var cells: {
        const first = (new Date(year, month, 1).getDay() + 6) % 7;
        const days = new Date(year, month + 1, 0).getDate();
        const prevDays = new Date(year, month, 0).getDate();
        const out = [];
        // соседние месяцы бледно — сетка всегда из целых недель
        for (let i = first - 1; i >= 0; i--) out.push({ d: prevDays - i, other: true });
        for (let d = 1; d <= days; d++) out.push({ d, other: false });
        let n = 1;
        while (out.length % 7 !== 0) out.push({ d: n++, other: true });
        return out;
    }
    function isToday(c) {
        return !c.other && c.d === now.getDate() && month === now.getMonth() && year === now.getFullYear();
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 10

        // сегодняшняя дата крупно
        ColumnLayout {
            spacing: 0
            Label { text: root.now.getDate() + " " + root.monthsGen[root.now.getMonth()]; size: "h1"; font.weight: Font.Bold }
            Label {
                text: root.weekdays[root.now.getDay()].charAt(0).toUpperCase() + root.weekdays[root.now.getDay()].slice(1) + ", " + root.now.getFullYear()
                size: "small"; tone: 3
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Label {
                text: root.months[root.month].charAt(0).toUpperCase() + root.months[root.month].slice(1) + (root.year !== root.now.getFullYear() ? " " + root.year : "")
                font.weight: Font.Bold
                Layout.fillWidth: true
            }
            Btn { visible: root.offset !== 0; text: "Сегодня"; implicitHeight: 28; kind: "ghost"; onClicked: root.offset = 0 }
            Btn { icon: "chevron-left"; iconSize: 16; implicitHeight: 28; kind: "ghost"; border.width: 0; onClicked: root.offset-- }
            Btn { icon: "chevron-right"; iconSize: 16; implicitHeight: 28; kind: "ghost"; border.width: 0; onClicked: root.offset++ }
        }

        Grid {
            id: grid
            Layout.fillWidth: true
            columns: 7
            rowSpacing: 2
            columnSpacing: 2
            readonly property real cell: Math.floor((col.width - 6 * columnSpacing) / 7)

            Repeater {
                model: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
                delegate: Label {
                    required property string modelData
                    required property int index
                    width: grid.cell
                    height: 26
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    size: "caption"
                    tone: 3
                    font.weight: index >= 5 ? Font.DemiBold : Font.Normal
                }
            }
            Repeater {
                model: root.cells
                delegate: Rectangle {
                    id: day
                    required property var modelData
                    required property int index
                    readonly property bool today: root.isToday(modelData)
                    width: grid.cell
                    height: 32
                    radius: 9
                    color: today ? Theme.accent : dayHover.hovered && !modelData.other ? Theme.soft2 : "transparent"
                    Label {
                        anchors.centerIn: parent
                        text: day.modelData.d
                        size: "small"
                        color: day.today ? Theme.onAccent : day.modelData.other ? Theme.fg3 : day.index % 7 >= 5 ? Theme.fg : Theme.fg2
                        opacity: day.modelData.other ? 0.5 : 1
                        font.weight: day.today ? Font.Bold : Font.Normal
                    }
                    HoverHandler { id: dayHover }
                }
            }
        }
    }

    // колесо листает месяцы
    WheelHandler {
        onWheel: e => root.offset += e.angleDelta.y > 0 ? -1 : 1
    }
}
