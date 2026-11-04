import QtQuick
import Quickshell
import qs.common
import qs.common.ui
import qs.services

// Значок буфера обмена; щелчок открывает историю (menus/ClipboardMenu.qml).
// Пока модуль в доке, delta-clipboard следит за буфером.
Item {
    property bool vertical: false
    property bool full: true
    property ShellScreen screen
    property bool hidden: false

    implicitWidth: 18
    implicitHeight: 18

    Component.onCompleted: Clipboard.users++
    Component.onDestruction: Clipboard.users--

    Sym {
        anchors.centerIn: parent
        size: 18
        name: "copy"
        color: Theme.fg2
    }
}
