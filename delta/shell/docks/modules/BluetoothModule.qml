import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.common
import qs.common.ui

// Bluetooth: без адаптера модуль скрыт; выключенный — бледный значок,
// подключённые устройства — точка акцента.
Item {
    property bool vertical: false
    property bool full: true
    property ShellScreen screen

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool hidden: adapter === null
    readonly property bool on: adapter?.enabled ?? false
    readonly property bool linked: on && (adapter?.devices?.values ?? []).some(d => d.connected)

    implicitWidth: 18
    implicitHeight: 18
    Sym {
        anchors.centerIn: parent
        size: 18
        name: "bluetooth"
        color: parent.on ? Theme.fg2 : Theme.fg3
        opacity: parent.on ? 1 : 0.6
    }
    Rectangle {
        visible: parent.linked
        width: 6; height: 6; radius: 3
        anchors { right: parent.right; top: parent.top; rightMargin: -3; topMargin: -2 }
        color: Theme.accent
    }
}
