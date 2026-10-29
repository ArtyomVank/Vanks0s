import QtQuick
import Quickshell
import qs.common
import qs.common.ui

// Питание: меню выключения, сна и учётной записи (menus/PowerMenu.qml).
Item {
    property bool vertical: false
    property bool full: true
    property ShellScreen screen
    property bool hidden: false

    implicitWidth: 18
    implicitHeight: 18
    Sym { anchors.centerIn: parent; name: "power"; size: 18; color: Theme.fg2 }
}
