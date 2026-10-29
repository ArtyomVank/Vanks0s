import QtQuick
import qs.common
import qs.common.ui

// Однострочное поле ввода в стиле Delta (в common/ui такого пока нет).
//     Field { text: city; placeholder: "Город"; onAccepted: v => … }
Rectangle {
    id: root

    property alias text: input.text
    property string placeholder
    property string icon
    signal accepted(string value)

    function focusInput() { input.forceActiveFocus(); }

    implicitWidth: 200
    implicitHeight: 32
    radius: height / 2
    color: Theme.soft2
    border.width: input.activeFocus ? 1.5 : 1
    border.color: input.activeFocus ? Theme.accent : Theme.line

    Sym {
        id: sym
        visible: root.icon.length > 0
        name: root.icon
        size: 16
        color: Theme.fg3
        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
    }

    TextInput {
        id: input
        anchors {
            left: sym.visible ? sym.right : parent.left; right: parent.right
            leftMargin: sym.visible ? 6 : 12; rightMargin: 12; verticalCenter: parent.verticalCenter
        }
        color: Theme.fg
        selectionColor: Theme.accent
        selectedTextColor: Theme.onAccent
        font.family: Theme.font
        font.pixelSize: 13
        clip: true
        selectByMouse: true
        onAccepted: root.accepted(text)

        Label {
            anchors.fill: parent
            visible: input.text.length === 0
            text: root.placeholder
            size: "small"
            tone: 3
        }
    }

    HoverHandler { cursorShape: Qt.IBeamCursor }
    TapHandler { onTapped: input.forceActiveFocus() }
}
