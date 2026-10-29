import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui

// Заглушка вместо раздела, файла которого ещё нет или который не загрузился.
ColumnLayout {
    id: root

    property string icon: "settings"
    property string text: "Раздел скоро появится"
    property string detail: "Он ещё в работе — загляните сюда после обновления."

    spacing: 14

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 260
        radius: Theme.radius - 2
        color: Theme.soft
        border.color: Theme.line

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 12
            width: parent.width - 80

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 64
                implicitHeight: 64
                radius: 32
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                Sym { anchors.centerIn: parent; name: root.icon; size: 30; color: Theme.accent }
            }
            Label { Layout.alignment: Qt.AlignHCenter; text: root.text; size: "title" }
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.detail
                tone: 3
                wrapMode: Text.WordWrap
            }
        }
    }
}
