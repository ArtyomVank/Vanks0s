import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.common
import qs.common.ui
import qs.docks

// Батарея (UPower). На компьютере без батареи модуль скрыт.
// Колесо — яркость экрана, как над кнопкой питания.
Item {
    id: root

    function wheel(dir, delta) { DockService.adjustBrightness((delta ? delta / 120 : dir) * 0.05); }

    property bool vertical: false
    property bool full: true
    property ShellScreen screen

    readonly property var dev: UPower.displayDevice
    readonly property bool hidden: !dev || !dev.isLaptopBattery || !dev.isPresent
    // в разных версиях UPower процент приходит как 0..1 или 0..100
    readonly property int percent: dev ? Math.round(dev.percentage > 1 ? dev.percentage : dev.percentage * 100) : 0
    readonly property bool charging: dev?.state === UPowerDeviceState.Charging || dev?.state === UPowerDeviceState.FullyCharged

    // «Акрил»: чип батареи залит акцентом (ModuleGrid читает chipAccent)
    readonly property bool chipAccent: Theme.acrylic && !vertical && full
    readonly property color ink: chipAccent ? Theme.onAccent : Theme.fg2
    implicitWidth: vertical ? 20 : row.implicitWidth + (chipAccent ? 10 : 0)
    implicitHeight: 20

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4
        Sym {
            anchors.verticalCenter: parent.verticalCenter
            size: 20
            name: root.charging ? "battery-charging" : "battery"
            color: root.percent <= 15 && !root.charging && !root.chipAccent ? "#ff6b6b" : root.ink
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.vertical && root.full && DockService.opt("batteryPercent", true) !== false
            text: root.percent + "%"
            num: true
            size: "caption"
            color: root.ink
            font.weight: Font.Bold
        }
    }
}
