import QtQuick
import Quickshell.Widgets
import qs.common

// Круглый аватар: картинка или первая буква имени на акцентном круге.
//     Avatar { source: Account.avatar; name: Account.name; size: 80 }
ClippingRectangle {
    id: root

    property string source        // путь к файлу
    property string name
    property int size: 80
    property int revision: 0      // сменить, чтобы перечитать файл
    property real ring: 0         // ширина светлой обводки

    implicitWidth: size
    implicitHeight: size
    radius: size / 2
    color: Theme.accent
    border.width: ring
    border.color: Qt.rgba(1, 1, 1, 0.25)

    Text {
        anchors.centerIn: parent
        visible: img.status !== Image.Ready
        text: (root.name || "?").charAt(0).toUpperCase()
        color: Theme.onAccent
        font.family: Theme.fontDisplay
        font.weight: Font.ExtraBold
        font.pixelSize: Math.round(root.size * 0.4)
    }

    Image {
        id: img
        anchors.fill: parent
        source: root.source.length ? "file://" + root.source + "?" + root.revision : ""
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
    }
}
