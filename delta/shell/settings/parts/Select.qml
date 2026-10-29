import QtQuick
import qs.common
import qs.common.ui

// Кнопка-значение для строки настроек: показывает текущий выбор и открывает
// список (Picker) по клику.
//     Select { text: tzName; onClicked: tzPicker.openWith() }
Rectangle {
    id: root

    property string text
    property string icon
    property bool enabled: true
    property int maxWidth: 300
    signal clicked()

    implicitHeight: 34
    implicitWidth: Math.min(maxWidth, row.implicitWidth + 26)
    radius: 12
    color: hov.hovered && enabled ? Theme.soft2 : Theme.soft
    border.color: Theme.line
    border.width: 1
    opacity: enabled ? 1 : 0.45
    Behavior on color { ColorAnimation { duration: Theme.anim.fast } }

    Row {
        id: row
        anchors { left: parent.left; leftMargin: 13; verticalCenter: parent.verticalCenter }
        spacing: 8
        Sym { visible: root.icon.length > 0; name: root.icon; size: 18; anchors.verticalCenter: parent.verticalCenter }
        Label {
            id: lbl
            text: root.text
            width: Math.min(implicitWidth, root.maxWidth - 50 - (root.icon.length ? 26 : 0))
            anchors.verticalCenter: parent.verticalCenter
        }
        Sym { name: "chevron-down"; size: 14; color: Theme.fg3; anchors.verticalCenter: parent.verticalCenter }
    }

    HoverHandler { id: hov; cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler { enabled: root.enabled; onTapped: root.clicked() }
}
