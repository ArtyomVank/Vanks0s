import QtQuick
import qs.common
import qs.common.ui

// Поле ввода в стиле Delta (в common/ui такого пока нет).
//     Field { placeholder: "Имя"; text: name; onAccepted: save(text) }
// password: true — точки вместо символов и кнопка «показать».
Rectangle {
    id: root

    property alias text: input.text
    property string placeholder
    property string icon
    property bool password: false
    property bool error: false
    property bool clearable: false
    property alias input: input
    property int maxLength: 256
    signal accepted()
    signal edited()

    function focusInput() { input.forceActiveFocus(); }

    implicitWidth: 260
    implicitHeight: 38
    radius: 12
    color: Theme.soft2
    border.width: 1
    border.color: error ? "#ff6b6b" : input.activeFocus ? Theme.accent : Theme.line
    Behavior on border.color { ColorAnimation { duration: Theme.anim.fast } }

    property bool reveal: false

    Sym {
        id: sym
        visible: root.icon.length > 0
        name: root.icon
        size: 16
        color: Theme.fg3
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
    }

    TextInput {
        id: input
        anchors {
            left: sym.visible ? sym.right : parent.left; leftMargin: sym.visible ? 8 : 12
            right: tail.visible ? tail.left : parent.right; rightMargin: tail.visible ? 6 : 12
            verticalCenter: parent.verticalCenter
        }
        color: Theme.fg
        selectionColor: Theme.accent
        selectedTextColor: Theme.onAccent
        font.family: Theme.font
        font.pixelSize: 14
        clip: true
        maximumLength: root.maxLength
        echoMode: root.password && !root.reveal ? TextInput.Password : TextInput.Normal
        passwordCharacter: "•"
        onAccepted: root.accepted()
        onTextEdited: root.edited()
        Keys.onEscapePressed: event => { if (root.clearable && text.length) { text = ""; root.edited(); } else event.accepted = false; }

        Label {
            anchors.fill: parent
            visible: input.text.length === 0
            text: root.placeholder
            tone: 3
        }
    }

    Sym {
        id: tail
        visible: root.password || (root.clearable && input.text.length > 0)
        name: root.password ? (root.reveal ? "eye-off" : "eye") : "close"
        size: 16
        color: tailHover.hovered ? Theme.fg : Theme.fg3
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        HoverHandler { id: tailHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            onTapped: {
                if (root.password) root.reveal = !root.reveal;
                else { input.text = ""; root.edited(); }
            }
        }
    }

    TapHandler { onTapped: input.forceActiveFocus() }
    HoverHandler { cursorShape: Qt.IBeamCursor }
}
