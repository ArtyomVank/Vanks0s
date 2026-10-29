import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui

// GitHub — пока заголовок на будущее (репозиторий и синхронизация настроек).
ColumnLayout {
    id: root

    property string title: "GitHub"
    property string icon: "github"
    property string keywords: "репозиторий синхронизация github"
    spacing: 18

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 190
        radius: Theme.radius - 2
        color: Theme.soft
        border.color: Theme.line

        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width - 80
            spacing: 12
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 64; implicitHeight: 64; radius: 32
                color: Theme.soft2
                Sym { anchors.centerIn: parent; name: "github"; size: 32 }
            }
            Label { Layout.alignment: Qt.AlignHCenter; text: "Скоро: репозиторий и синхронизация"; size: "title" }
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                tone: 3
                text: "Здесь появится ссылка на исходники Vanks OS и перенос настроек Delta между компьютерами."
            }
        }
    }
}
