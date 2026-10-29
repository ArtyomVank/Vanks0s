pragma ComponentBehavior: Bound

import QtQuick
import qs.common
import qs.widgets.parts

// Уведомления на экране блокировки: последние из ShellState.notifications
// (их публикует notify/). Сколько строк влезает — зависит от высоты виджета.
Base {
    id: root

    readonly property bool allowed: Settings.get("notifications.onLock", true)
    readonly property var list: allowed ? (ShellState.notifications || []) : []
    readonly property real rowH: 26 * ch
    readonly property int fit: Math.max(1, Math.floor((height - head.height) / (rowH + 4 * ch)))

    Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        visible: root.mode !== "count"
        spacing: 4 * root.ch

        WText {
            id: head
            text: "Уведомления · " + root.list.length
            px: 9 * root.ch
            font.weight: Font.ExtraBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.6
            color: root.pal.c1
            opacity: 0.8
        }
        Repeater {
            model: root.list.slice(0, root.fit)
            delegate: Rectangle {
                id: row
                required property var modelData
                width: parent.width
                height: root.rowH
                radius: height * 0.4
                color: Qt.rgba(1, 1, 1, 0.12)
                Row {
                    anchors { left: parent.left; right: parent.right; leftMargin: height * 0.4; rightMargin: height * 0.4; verticalCenter: parent.verticalCenter }
                    spacing: root.rowH * 0.3
                    WText {
                        id: sum
                        text: row.modelData.summary || row.modelData.app || ""
                        px: root.rowH * 0.4
                        font.weight: Font.Bold
                        color: root.pal.c1
                        width: Math.min(implicitWidth, parent.width * 0.5)
                    }
                    WText {
                        text: row.modelData.body || ""
                        px: root.rowH * 0.4
                        color: root.pal.c1
                        opacity: 0.8
                        width: parent.width - sum.width - parent.spacing
                    }
                }
            }
        }
        WText {
            visible: root.list.length === 0
            text: root.allowed ? "Новых уведомлений нет" : "Скрыты в настройках"
            px: 10 * root.ch
            color: root.pal.c1
            opacity: 0.75
        }
    }

    // «Счётчик»: крупное число и последнее уведомление
    Row {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        visible: root.mode === "count"
        spacing: 5 * root.cm

        WText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.list.length
            px: Math.min(40 * root.ch, 17 * root.cw)
            display: true
            font.weight: Font.ExtraBold
            color: root.pal.c1
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Math.min(40 * root.ch, 17 * root.cw) - parent.spacing
            WText {
                width: parent.width
                text: root.allowed ? "Уведомления" : "Скрыты"
                px: Math.min(12 * root.ch, 5 * root.cw)
                font.weight: Font.Bold
                color: root.pal.c1
                opacity: 0.85
            }
            WText {
                width: parent.width
                text: root.list.length
                    ? ((root.list[0].summary || root.list[0].app || "") + (root.list[0].body ? " · " + root.list[0].body : ""))
                    : "Новых нет"
                px: Math.min(11 * root.ch, 4.4 * root.cw)
                color: root.pal.c1
                opacity: 0.7
            }
        }
    }
}
