import QtQuick
import qs.common
import qs.common.ui

// Поле ввода в стиле Delta: иконка, подсказка, кнопка очистки.
// В common/ui такого пока нет — кандидат на перенос.
//     Field { placeholder: "Поиск"; onAccepted: … ; onKey: e => { if (e.key === Qt.Key_Down) { …; e.accepted = true } } }
Rectangle {
    id: root

    property alias text: input.text
    property alias input: input
    property string placeholder
    property string icon: "search"
    property bool password: false
    property int fontSize: 14
    property bool clearable: true
    signal accepted()
    // все нажатия до обработки самим полем: стрелки, Esc и т. п.
    signal key(var event)

    function focusInput() { input.forceActiveFocus(); }

    implicitWidth: 280
    implicitHeight: 42
    radius: 12
    color: Theme.soft2
    border.width: 1
    border.color: input.activeFocus ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55) : Theme.line
    Behavior on border.color { ColorAnimation { duration: Theme.anim.fast } }

    Sym {
        id: sym
        visible: root.icon.length > 0
        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
        name: root.icon
        size: Math.round(root.fontSize * 1.25)
        color: Theme.fg2
    }

    TextInput {
        id: input
        anchors {
            left: sym.visible ? sym.right : parent.left; leftMargin: sym.visible ? 10 : 14
            right: clear.visible ? clear.left : parent.right; rightMargin: 8
            verticalCenter: parent.verticalCenter
        }
        color: Theme.fg
        selectionColor: Theme.accent
        selectedTextColor: Theme.onAccent
        font.family: Theme.font
        font.pixelSize: root.fontSize
        echoMode: root.password ? TextInput.Password : TextInput.Normal
        passwordCharacter: "•"
        clip: true
        selectByMouse: true
        Keys.onPressed: e => root.key(e)
        onAccepted: root.accepted()

        Label {
            anchors.fill: parent
            visible: input.text.length === 0
            text: root.placeholder
            tone: 3
            font.pixelSize: root.fontSize
        }
    }

    Btn {
        id: clear
        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
        visible: root.clearable && input.text.length > 0
        icon: "close"
        kind: "ghost"
        iconSize: 14
        implicitHeight: root.height - 12
        border.width: 0
        onClicked: { input.text = ""; input.forceActiveFocus(); }
    }

    TapHandler { onTapped: input.forceActiveFocus() }
}
