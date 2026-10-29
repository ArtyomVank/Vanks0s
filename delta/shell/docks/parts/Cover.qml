import QtQuick
import Quickshell.Widgets
import qs.common

// Круглая обложка трека; без картинки — градиент акцента, как .art в концепте.
Item {
    id: root

    property int size: 30
    property string source
    property real radius: size / 2

    implicitWidth: size
    implicitHeight: size

    ClippingRectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.5) }
                GradientStop { position: 1; color: Qt.darker(Theme.accent, 1.6) }
            }
        }
        Image {
            anchors.fill: parent
            visible: status === Image.Ready
            source: root.source
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(root.size * 2, root.size * 2)
        }
    }
}
