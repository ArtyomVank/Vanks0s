import QtQuick
import Quickshell
import qs.common
import qs.common.ui
import qs.docks

// Текущая раскладка: «RU», «EN».
Item {
    property bool vertical: false
    property bool full: true
    property ShellScreen screen
    readonly property bool hidden: KbLayout.short.length === 0

    implicitWidth: Math.max(20, lbl.implicitWidth)
    implicitHeight: 20

    Label {
        id: lbl
        anchors.centerIn: parent
        text: KbLayout.short
        size: "small"
        color: Theme.fg
        font.weight: Font.Bold
    }
}
