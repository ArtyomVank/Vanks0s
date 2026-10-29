import QtQuick
import Quickshell.Widgets
import qs.common
import qs.common.ui

// Аватар в круге: картинка (обрезка по центру) или инициалы на цвете.
//     Avatar { size: 96; source: "/home/u/.face"; name: "Артём" }
Item {
    id: root

    property int size: 64
    property string source: ""
    property string name: ""
    property color tint: Theme.accent
    // показать картинку целиком без круга (для снимка в файл)
    property bool square: false

    readonly property bool hasImage: img.status === Image.Ready
    readonly property string initials: {
        const parts = String(name || "").trim().split(/\s+/).filter(p => p.length);
        if (!parts.length) return "?";
        return (parts[0][0] + (parts.length > 1 ? parts[1][0] : "")).toUpperCase();
    }

    implicitWidth: size
    implicitHeight: size

    ClippingRectangle {
        anchors.fill: parent
        radius: root.square ? 0 : width / 2
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            visible: !root.hasImage
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.lighter(root.tint, 1.25) }
                GradientStop { position: 1; color: Qt.darker(root.tint, 1.35) }
            }
            Text {
                anchors.centerIn: parent
                text: root.initials
                color: Theme.onColor(root.tint)
                font.family: Theme.fontDisplay
                font.pixelSize: root.size * 0.38
                font.weight: Font.DemiBold
            }
        }
        Image {
            id: img
            anchors.fill: parent
            source: root.source.length ? (root.source.startsWith("/") ? "file://" + root.source : root.source) : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(root.size * 2, root.size * 2)
            asynchronous: true
            cache: false
            smooth: true
        }
    }
}
