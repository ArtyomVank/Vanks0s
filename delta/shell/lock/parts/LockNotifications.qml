pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.common

// Последние уведомления на экране блокировки (ShellState.notifications от notify/).
// Как виджет «Уведомления» в концепте: заголовок со счётчиком и строки на светлом стекле.
Column {
    id: root

    property var items: ShellState.notifications || []
    property int max: 4

    spacing: 6
    visible: items.length > 0

    Text {
        text: "Уведомления · " + root.items.length
        color: "#ffffff"
        opacity: 0.8
        font.family: Theme.font
        font.pixelSize: 12
        font.weight: Font.ExtraBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
        leftPadding: 4
    }

    Repeater {
        model: root.items.slice(0, root.max)
        delegate: Rectangle {
            id: row
            required property var modelData
            width: root.width
            height: col.implicitHeight + 18
            radius: 14
            color: Qt.rgba(1, 1, 1, 0.12)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            IconImage {
                id: icon
                anchors { left: parent.left; leftMargin: 12; top: parent.top; topMargin: 11 }
                implicitSize: 22
                visible: source.toString().length > 0
                source: {
                    const i = row.modelData.appIcon || "";
                    return i.length === 0 ? "" : i.startsWith("/") ? "file://" + i : i.indexOf("://") !== -1 ? i : Quickshell.iconPath(i, true);
                }
            }
            Column {
                id: col
                anchors { left: icon.visible ? icon.right : parent.left; leftMargin: 12; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 2
                Row {
                    width: parent.width
                    spacing: 8
                    Text {
                        width: Math.min(implicitWidth, parent.width - when.implicitWidth - 8)
                        text: row.modelData.summary || row.modelData.app || ""
                        color: "#ffffff"
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }
                    Text {
                        id: when
                        text: {
                            const t = row.modelData.time;
                            return t ? Qt.formatTime(new Date(t), "HH:mm") : "";
                        }
                        color: "#ffffff"
                        opacity: 0.6
                        font.family: Theme.font
                        font.pixelSize: 12
                        anchors.baseline: parent.children[0].baseline
                    }
                }
                Text {
                    width: parent.width
                    visible: text.length > 0
                    // в теле бывает разметка — на экране блокировки показываем только текст
                    text: String(row.modelData.body || "").replace(/<[^>]*>/g, "")
                    textFormat: Text.PlainText
                    color: "#ffffff"
                    opacity: 0.8
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    font.family: Theme.font
                    font.pixelSize: 13
                }
            }
        }
    }
}
