import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui

// Плашка-предупреждение внутри Card. kind: "warn" (оранжевая) · "info" · "error".
//     Note { text: "HDR в Hyprland пока экспериментальный."; kind: "warn" }
Item {
    id: root

    property string text
    property string kind: "warn"
    readonly property color tint: kind === "error" ? "#ff6b6b" : kind === "warn" ? "#F09A2B" : Theme.accent

    implicitHeight: box.implicitHeight + 20
    Layout.fillWidth: true

    Rectangle {
        anchors { fill: parent; leftMargin: 12; rightMargin: 12; topMargin: 6; bottomMargin: 6 }
        radius: 10
        color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.12)
        border.width: 1
        border.color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.35)
    }
    RowLayout {
        id: box
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 24; rightMargin: 24 }
        spacing: 10
        Sym {
            name: root.kind === "info" ? "info" : "warning"
            size: 18
            color: root.tint
            Layout.alignment: Qt.AlignTop
        }
        Label {
            text: root.text
            size: "small"
            tone: 2
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }
}
