import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.common
import qs.common.ui
import qs.docks

// Батарея (UPower). На компьютере без батареи модуль скрыт.
Item {
    id: root

    property bool vertical: false
    property bool full: true
    property ShellScreen screen

    readonly property var dev: UPower.displayDevice
    readonly property bool hidden: !dev || !dev.isLaptopBattery || !dev.isPresent
    // в разных версиях UPower процент приходит как 0..1 или 0..100
    readonly property int percent: dev ? Math.round(dev.percentage > 1 ? dev.percentage : dev.percentage * 100) : 0
    readonly property bool charging: dev?.state === UPowerDeviceState.Charging || dev?.state === UPowerDeviceState.FullyCharged

    implicitWidth: vertical ? 20 : row.implicitWidth
    implicitHeight: 20

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4
        Sym {
            anchors.verticalCenter: parent.verticalCenter
            size: 20
            name: root.charging ? "battery-charging" : "battery"
            color: root.percent <= 15 && !root.charging ? "#ff6b6b" : Theme.fg2
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.vertical && root.full && DockService.opt("batteryPercent", true) !== false
            text: root.percent + "%"
            size: "caption"
            color: Theme.fg2
            font.weight: Font.Bold
        }
    }
}
