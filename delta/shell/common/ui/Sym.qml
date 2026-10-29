import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.common

// Иконка Delta. `name` — файл из shell/icons без .svg (wifi, volume, …);
// если такого нет, берётся иконка из темы значков. Перекрашивается в `color`.
//     Sym { name: "wifi"; size: 18; color: Theme.accent }
Item {
    id: root

    property string name
    property int size: 18
    property color color: Theme.fg

    implicitWidth: size
    implicitHeight: size

    readonly property bool own: name.length > 0 && name.indexOf("/") === -1 && Icons.has(name)

    Image {
        id: img
        anchors.fill: parent
        visible: false
        source: root.own ? Quickshell.shellDir + "/icons/" + root.name + ".svg" : ""
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        smooth: true
    }
    MultiEffect {
        anchors.fill: parent
        visible: root.own
        source: img
        colorization: 1
        colorizationColor: root.color
        brightness: 1
    }

    IconImage {
        anchors.fill: parent
        visible: !root.own && root.name.length > 0
        source: visible ? Quickshell.iconPath(root.name, true) : ""
        implicitSize: root.size
    }
}
