import QtQuick
import Quickshell
import qs.common
import qs.common.ui
import qs.docks

// Питание: меню выключения, сна и учётной записи (menus/PowerMenu.qml).
// Колесо — яркость экрана (если её есть чем менять), уровень — в острове.
Item {
    function wheel(dir, delta) { DockService.adjustBrightness((delta ? delta / 120 : dir) * 0.05); }
    property bool vertical: false
    property bool full: true
    property ShellScreen screen
    property bool hidden: false

    implicitWidth: 18
    implicitHeight: 18
    Sym { anchors.centerIn: parent; name: "power"; size: 18; color: Theme.fg2 }
}
