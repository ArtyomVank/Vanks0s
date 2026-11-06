import QtQuick
import Quickshell
import qs.common
import qs.common.ui
import qs.notify

// Колокольчик с числом непрочитанных; в «Не беспокоить» — перечёркнутый.
// В «Акриле» число стоит рядом, моноширинное, а не кружком на значке.
Item {
    id: root
    property bool vertical: false
    property bool full: true
    property ShellScreen screen
    property bool hidden: false

    readonly property bool countBeside: Theme.acrylic && !vertical && full
    readonly property bool hasUnread: NotifyStore.unread > 0 && !ShellState.dnd
    implicitWidth: countBeside && hasUnread ? 18 + 6 + inl.implicitWidth : 18
    implicitHeight: 18

    Sym {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        size: 18
        name: ShellState.dnd ? "bell-off" : "bell"
        color: Theme.fg2
    }
    Label {
        id: inl
        visible: root.countBeside && root.hasUnread
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        text: NotifyStore.unread > 99 ? "99+" : NotifyStore.unread
        font.family: Theme.fontMono
        font.pixelSize: 13
        font.weight: Font.Bold
        color: Theme.accent
    }
    Rectangle {
        visible: !root.countBeside && root.hasUnread
        anchors { horizontalCenter: parent.right; verticalCenter: parent.top; horizontalCenterOffset: -2; verticalCenterOffset: 2 }
        width: Math.max(16, cnt.implicitWidth + 8)
        height: 16
        radius: 8
        color: Theme.accent
        Label {
            id: cnt
            anchors.centerIn: parent
            text: NotifyStore.unread > 99 ? "99+" : NotifyStore.unread
            color: Theme.onAccent
            font.pixelSize: 10
            font.weight: Font.Bold
        }
    }
}
