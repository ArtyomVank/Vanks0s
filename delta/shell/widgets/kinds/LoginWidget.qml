import QtQuick
import Quickshell
import qs.common
import qs.common.ui
import qs.widgets

// Поле входа на экране блокировки (id «login»). Настоящее поле — аватар, имя
// и пароль — рисует LockSurface по центру этих клеток; здесь только его
// набросок для редактора: видно, где окажется вход, и его можно передвинуть.
// Вне редактора — пусто. Убрать и изменить размер нельзя (WidgetTypes.fixed).
Base {
    id: root

    visible: editing
    readonly property real s: Math.min(cw * 100 / 420, ch * 100 / 260)

    Column {
        anchors.centerIn: parent
        spacing: 10 * root.s

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 72 * root.s; height: width
            radius: width / 2
            color: Qt.rgba(1, 1, 1, 0.16)
            border.width: 2
            border.color: Qt.rgba(1, 1, 1, 0.5)
            Sym { anchors.centerIn: parent; name: "user"; size: Math.round(parent.width * 0.5); color: "#ffffff" }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Quickshell.env("USER") || I18n.tr("Вход")
            color: "#ffffff"
            font.family: Theme.font
            font.pixelSize: Math.max(11, 17 * root.s)
            font.weight: Font.Bold
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 300 * root.s; height: 44 * root.s
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.14)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.35)
            Row {
                anchors { left: parent.left; leftMargin: 16 * root.s; verticalCenter: parent.verticalCenter }
                spacing: 8 * root.s
                Sym { anchors.verticalCenter: parent.verticalCenter; name: "lock"; size: Math.round(16 * root.s); color: Qt.rgba(1, 1, 1, 0.7) }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Пароль")
                    color: Qt.rgba(1, 1, 1, 0.7)
                    font.family: Theme.font
                    font.pixelSize: Math.max(10, 14 * root.s)
                }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr("Только передвинуть")
            color: Qt.rgba(1, 1, 1, 0.6)
            font.family: Theme.font
            font.pixelSize: Math.max(10, 12 * root.s)
        }
    }
}
