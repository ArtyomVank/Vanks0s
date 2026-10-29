pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.common
import qs.common.ui
import qs.docks.parts

// Всплывающее уведомление: шарик выпадает из верхнего дока и раскрывается
// в карточку; по таймеру (наведение его останавливает) сворачивается обратно.
Item {
    id: root

    required property var modelData
    required property int index
    property real dirX: 0
    property real dirY: -1
    // окно карточек: край дока, размер и место на экране — капля новой
    // карточки выходит прямо из края верхнего дока (он сам вздувается)
    property string edge: "top"
    property real winW: 0
    property real winH: 0
    property point winOffset: Qt.point(0, 0)
    property string screenName: ""
    readonly property var rec: modelData
    readonly property Notification n: rec.n

    // Копия данных: карточка доигрывает закрытие и после уничтожения уведомления.
    property string summary
    property string body
    property string app
    property string icon
    property string image
    property int urgency: NotificationUrgency.Normal
    property var actions: []
    property bool canReply: false
    property string replyHint
    Binding on summary { when: root.n !== null; value: root.n.summary; restoreMode: Binding.RestoreNone }
    Binding on body { when: root.n !== null; value: root.n.body; restoreMode: Binding.RestoreNone }
    Binding on app { when: root.n !== null; value: root.n.appName; restoreMode: Binding.RestoreNone }
    Binding on icon { when: root.n !== null; value: NotifyStore.iconFor(root.n); restoreMode: Binding.RestoreNone }
    Binding on image { when: root.n !== null; value: NotifyStore.imageFor(root.n); restoreMode: Binding.RestoreNone }
    Binding on urgency { when: root.n !== null; value: root.n.urgency; restoreMode: Binding.RestoreNone }
    Binding on actions { when: root.n !== null; value: root.n.actions; restoreMode: Binding.RestoreNone }
    Binding on canReply { when: root.n !== null; value: root.n.hasInlineReply; restoreMode: Binding.RestoreNone }
    Binding on replyHint { when: root.n !== null; value: root.n.inlineReplyPlaceholder; restoreMode: Binding.RestoreNone }

    readonly property bool critical: urgency === NotificationUrgency.Critical
    readonly property var buttons: actions.filter(a => a && a.identifier !== "default" && a.text)
    readonly property var defaultAction: actions.find(a => a && a.identifier === "default") ?? null

    width: 400
    height: card.height + 10

    // время показа: своё от приложения (expireTimeout — в мс, как в спецификации), иначе по важности
    readonly property int timeout: {
        const own = n ? n.expireTimeout : 0;
        if (own > 0) return Math.max(2000, Math.min(30000, own));
        return urgency === NotificationUrgency.Low ? 4000 : Settings.get("notifications.timeout", 6) * 1000;
    }

    property bool leaving: false
    function leave() {
        if (leaving) return;
        leaving = true;
        card.open = false;
    }
    onIndexChanged: if (index >= NotifyStore.maxPopups) leave()
    Connections {
        target: root.n
        function onClosed() { root.leave(); }
        // уведомление заменили — показываем заново полный срок
        function onSummaryChanged() { life.restart(); }
        function onBodyChanged() { life.restart(); }
    }

    // открыли центр уведомлений — карточки там же, всплывающие убираем
    Connections {
        target: ShellState
        function onMenuChanged() { if (ShellState.menu === "notifications") root.leave(); }
    }

    Timer {
        id: life
        interval: root.timeout
        running: !root.critical && card.settled && !hover.hovered && !reply.input.activeFocus
        onTriggered: root.leave()
    }

    Blob {
        id: card
        x: (root.width - width) / 2
        width: 360
        height: Math.max(74, box.implicitHeight + 28)
        open: true
        dirX: root.dirX
        dirY: root.dirY
        radiusOpen: 24
        ballColor: root.critical ? "#E5484D" : Theme.accent
        // источник — край дока (4 px за краем окна), напротив карточки
        srcX: root.edge === "left" ? -4 - root.x - x : root.edge === "right" ? root.winW + 4 - root.x - x : NaN
        srcY: root.edge === "top" ? -4 - root.y - y : root.edge === "bottom" ? root.winH + 4 - root.y - y : NaN
        pullKey: root.screenName && !root.critical ? root.screenName + "/top:@toast" : ""
        screenOffset: root.winOffset
        onClosed: NotifyStore.dropPopup(root.rec.key)

        HoverHandler { id: hover }

        // нажатие по карточке — действие по умолчанию; кнопки ниже его не задевают
        MouseArea {
            x: box.x + head.x
            y: box.y + head.y
            width: head.width
            height: head.height
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.defaultAction) root.defaultAction.invoke();
                root.leave();
            }
        }

        ColumnLayout {
            id: box
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 10

            RowLayout {
                id: head
                Layout.fillWidth: true
                spacing: 12

                // картинка (аватар) или значок приложения
                Item {
                    implicitWidth: 38
                    implicitHeight: 38
                    Layout.alignment: Qt.AlignTop
                    ClippingRectangle {
                        anchors.fill: parent
                        radius: 12
                        color: "transparent"
                        visible: root.image.length > 0
                        Image { anchors.fill: parent; source: root.image; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(76, 76) }
                    }
                    IconImage {
                        visible: root.image.length === 0 && root.icon.length > 0
                        anchors.fill: parent
                        source: root.icon
                        asynchronous: true
                    }
                    Rectangle {
                        visible: root.image.length === 0 && root.icon.length === 0
                        anchors.fill: parent
                        radius: 12
                        color: Theme.soft2
                        Sym { anchors.centerIn: parent; name: root.critical ? "warning" : "bell"; size: 20; color: root.critical ? "#ff6b6b" : Theme.fg2 }
                    }
                    // маленький значок приложения поверх аватара
                    IconImage {
                        visible: root.image.length > 0 && root.icon.length > 0
                        width: 16; height: 16
                        anchors { right: parent.right; bottom: parent.bottom; margins: -3 }
                        source: root.icon
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Label {
                            Layout.fillWidth: true
                            text: root.summary || root.app
                            font.weight: Font.Bold
                            color: root.critical ? "#ff8a8a" : Theme.fg
                        }
                        Label { text: root.app && root.summary ? root.app : "сейчас"; size: "caption"; tone: 3; Layout.maximumWidth: 110; Layout.rightMargin: 20 }
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: root.body.length > 0
                        text: root.body
                        textFormat: Text.StyledText
                        size: "small"
                        tone: 2
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                    }
                }
            }

            // кнопки действий
            Flow {
                visible: root.buttons.length > 0
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: root.buttons
                    delegate: Btn {
                        required property var modelData
                        text: modelData.text
                        implicitHeight: 30
                        onClicked: { modelData.invoke(); root.leave(); }
                    }
                }
            }

            // быстрый ответ
            RowLayout {
                visible: root.canReply
                Layout.fillWidth: true
                spacing: 6
                Field {
                    id: reply
                    Layout.fillWidth: true
                    implicitHeight: 34
                    placeholder: root.replyHint || "Ответить…"
                    onAccepted: send.clicked()
                }
                Btn {
                    id: send
                    icon: "send"
                    kind: "accent"
                    implicitHeight: 34
                    enabled: reply.text.trim().length > 0
                    onClicked: {
                        if (!enabled || !root.n) return;
                        root.n.sendInlineReply(reply.text.trim());
                        root.leave();
                    }
                }
            }
        }

        // закрыть (убрать и из истории)
        Rectangle {
            width: 22; height: 22; radius: 11
            anchors { right: parent.right; top: parent.top; margins: 8 }
            color: Theme.soft2
            opacity: hover.hovered ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            Sym { anchors.centerIn: parent; name: "close"; size: 12; color: Theme.fg2 }
            MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: { NotifyStore.dismiss(root.n); root.leave(); } }
        }
    }
}
