import QtQuick
import Quickshell
import qs.common
import qs.common.ui

// Кнопка окна приложений: знак Vanks.
Item {
    property bool vertical: false
    property bool full: true
    property ShellScreen screen
    property bool hidden: false

    implicitWidth: 24
    implicitHeight: 24

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: Theme.accent
        Label {
            anchors.centerIn: parent
            text: "V"
            color: Theme.onAccent
            font.pixelSize: 13
            font.weight: Font.ExtraBold
        }
    }
}
