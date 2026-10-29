import QtQuick
import Quickshell
import qs.common
import qs.common.ui
import qs.notify

// Колокольчик с числом непрочитанных; в «Не беспокоить» — перечёркнутый.
Item {
    property bool vertical: false
    property bool full: true
    property ShellScreen screen
    property bool hidden: false

    implicitWidth: 18
    implicitHeight: 18

    Sym {
        anchors.centerIn: parent
        size: 18
        name: ShellState.dnd ? "bell-off" : "bell"
        color: Theme.fg2
    }
    Rectangle {
        visible: NotifyStore.unread > 0 && !ShellState.dnd
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
