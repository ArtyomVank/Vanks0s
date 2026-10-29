import QtQuick
import qs.common
import qs.common.ui

// Поле ввода в стиле Delta (в common/ui такого пока нет).
//     Field { placeholder: "Команда"; onAccepted: … }
Rectangle {
    id: root

    property alias text: input.text
    property string placeholder
    property string icon
    property alias input: input
    signal accepted()

    implicitWidth: 240
    implicitHeight: 38
    radius: 12
    color: Theme.soft2
    border.width: 1
    border.color: input.activeFocus ? Theme.accent : Theme.line
    Behavior on border.color { ColorAnimation { duration: Theme.anim.fast } }

    function focusField() { input.forceActiveFocus(); }

    Sym {
        id: sym
        visible: root.icon.length > 0
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        name: root.icon
        size: 16
        color: Theme.fg3
    }

    TextInput {
        id: input
        anchors { left: sym.visible ? sym.right : parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: sym.visible ? 8 : 12; rightMargin: 12 }
        color: Theme.fg
        selectionColor: Theme.accent
        selectedTextColor: Theme.onAccent
        font.family: Theme.font
        font.pixelSize: 14
        clip: true
        selectByMouse: true
        onAccepted: root.accepted()

        Label {
            anchors.fill: parent
            visible: input.text.length === 0
            text: root.placeholder
            tone: 3
        }
    }

    HoverHandler { cursorShape: Qt.IBeamCursor }
    TapHandler { onTapped: input.forceActiveFocus() }
}
