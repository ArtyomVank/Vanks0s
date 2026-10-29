pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.common
import qs.common.ui
import qs.notify

// Центр уведомлений: история, «Не беспокоить», очистка.
Item {
    id: root

    implicitWidth: 380
    implicitHeight: col.implicitHeight
    signal close()

    readonly property var items: NotifyStore.items

    // «5 мин назад» обновляем раз в минуту, только пока меню открыто
    property int tick: 0
    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.tick++ }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Label { text: "Уведомления"; size: "title"; Layout.fillWidth: true }
            Label { text: "Не беспокоить"; size: "small"; tone: 2 }
            Toggle {
                checked: ShellState.dnd
                onToggled: v => ShellState.dnd = v
            }
        }

        Label {
            visible: ShellState.dnd
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Всплывающие уведомления скрыты, кроме важных. Всё приходящее остаётся здесь."
            size: "small"
            tone: 3
        }

        Rectangle {
            visible: root.items.length === 0
            Layout.fillWidth: true
            implicitHeight: 64
            radius: 14
            color: Theme.soft
            Column {
                anchors.centerIn: parent
                spacing: 6
                Sym { anchors.horizontalCenter: parent.horizontalCenter; name: ShellState.dnd ? "bell-off" : "bell"; size: 20; color: Theme.fg3 }
                Label { text: "Новых уведомлений нет"; size: "small"; tone: 3 }
            }
        }

        Repeater {
            model: ScriptModel { values: root.items; objectProp: "id" }

            delegate: Rectangle {
                id: row
                required property Notification modelData
                readonly property Notification n: modelData
                readonly property string icon: NotifyStore.iconFor(n)
                readonly property string image: NotifyStore.imageFor(n)
                readonly property bool critical: n?.urgency === NotificationUrgency.Critical
                readonly property var buttons: (n?.actions ?? []).filter(a => a && a.identifier !== "default" && a.text)
                readonly property var defaultAction: (n?.actions ?? []).find(a => a && a.identifier === "default") ?? null

                Layout.fillWidth: true
                implicitHeight: inner.implicitHeight + 20
                radius: 14
                color: hov.hovered ? Theme.soft2 : Theme.soft
                border.width: critical ? 1 : 0
                border.color: "#ff6b6b"
                Behavior on color { ColorAnimation { duration: 120 } }

                HoverHandler { id: hov }

                // нажатие по строке — действие по умолчанию (кнопки ниже его не задевают)
                MouseArea {
                    width: parent.width
                    height: inner.y + head.height + 6
                    cursorShape: row.defaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (!row.defaultAction) return;
                        row.defaultAction.invoke();
                        root.close();
                    }
                }

                ColumnLayout {
                    id: inner
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    spacing: 8

                    RowLayout {
                        id: head
                        Layout.fillWidth: true
                        spacing: 10

                        Item {
                            implicitWidth: 32
                            implicitHeight: 32
                            Layout.alignment: Qt.AlignTop
                            ClippingRectangle {
                                anchors.fill: parent
                                radius: 10
                                color: "transparent"
                                visible: row.image.length > 0
                                Image { anchors.fill: parent; source: row.image; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(64, 64) }
                            }
                            IconImage { anchors.fill: parent; visible: row.image.length === 0 && row.icon.length > 0; source: row.icon; asynchronous: true }
                            Rectangle {
                                anchors.fill: parent
                                visible: row.image.length === 0 && row.icon.length === 0
                                radius: 10
                                color: Theme.soft2
                                Sym { anchors.centerIn: parent; name: "bell"; size: 16; color: Theme.fg2 }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: row.n?.summary || row.n?.appName || ""; font.weight: Font.Bold; Layout.fillWidth: true }
                                Label {
                                    text: { root.tick; return (row.n?.appName ? row.n.appName + " · " : "") + NotifyStore.ago(NotifyStore.times[row.n?.id] ?? Date.now()); }
                                    size: "caption"; tone: 3
                                    Layout.maximumWidth: 160
                                }
                            }
                            Label {
                                visible: text.length > 0
                                text: row.n?.body ?? ""
                                textFormat: Text.StyledText
                                size: "small"; tone: 2
                                wrapMode: Text.Wrap
                                maximumLineCount: 4
                                Layout.fillWidth: true
                            }
                        }

                        // убрать уведомление
                        Rectangle {
                            implicitWidth: 24; implicitHeight: 24; radius: 12
                            Layout.alignment: Qt.AlignTop
                            color: xArea.containsMouse ? Theme.soft2 : "transparent"
                            opacity: hov.hovered ? 1 : 0.35
                            Sym { anchors.centerIn: parent; name: "close"; size: 12; color: Theme.fg2 }
                            MouseArea { id: xArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: NotifyStore.dismiss(row.n) }
                        }
                    }

                    Flow {
                        visible: row.buttons.length > 0
                        Layout.fillWidth: true
                        Layout.leftMargin: 42
                        spacing: 6
                        Repeater {
                            model: row.buttons
                            delegate: Btn {
                                required property var modelData
                                text: modelData.text
                                implicitHeight: 28
                                onClicked: { modelData.invoke(); root.close(); }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            visible: root.items.length > 0
            Layout.fillWidth: true
            Label { text: root.items.length + " " + root.plural(root.items.length); size: "small"; tone: 3; Layout.fillWidth: true }
            Btn { icon: "trash"; text: "Очистить все"; onClicked: NotifyStore.clear() }
        }
    }

    function plural(k) {
        const m10 = k % 10, m100 = k % 100;
        if (m10 === 1 && m100 !== 11) return "уведомление";
        if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return "уведомления";
        return "уведомлений";
    }
}
