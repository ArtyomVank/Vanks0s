import QtQuick
import Quickshell
import Quickshell.Networking
import qs.common
import qs.common.ui

// Сеть: Wi-Fi или кабель; без NetworkManager — перечёркнутый значок.
Item {
    property bool vertical: false
    property bool full: true
    property ShellScreen screen
    property bool hidden: false

    readonly property var devices: Networking.devices.values
    readonly property bool wired: devices.some(d => d.type === DeviceType.Wired && d.connected)
    readonly property bool wifi: devices.some(d => d.type === DeviceType.Wifi && d.connected)

    implicitWidth: 18
    implicitHeight: 18
    Sym {
        anchors.centerIn: parent
        size: 18
        name: parent.wifi ? "wifi" : parent.wired ? "ethernet" : "wifi-off"
        color: parent.wifi || parent.wired ? Theme.fg2 : Theme.fg3
    }
}
