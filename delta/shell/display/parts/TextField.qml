import QtQuick
import qs.common
import qs.common.ui

// Однострочное поле ввода в стиле Delta (кандидат в common/ui).
//     TextField { text: cfg.icc; placeholder: "/usr/share/color/icc/…"; onEdited: v => … }
// `edited` приходит по Enter или при потере фокуса, если текст изменился.
Rectangle {
    id: root

    property alias text: input.text
    property string placeholder
    property bool mono: false
    property bool invalid: false
    signal edited(string value)

    property string last: ""

    implicitWidth: 260
    implicitHeight: 36
    radius: 12
    color: Theme.soft2
    border.width: 1
    border.color: invalid ? "#ff6b6b" : input.activeFocus ? Theme.accent : Theme.line
    opacity: enabled ? 1 : 0.45

    TextInput {
        id: input
        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
        verticalAlignment: TextInput.AlignVCenter
        enabled: root.enabled
        clip: true
        color: Theme.fg
        selectionColor: Theme.accent
        selectedTextColor: Theme.onAccent
        font.family: root.mono ? Theme.fontMono : Theme.font
        font.pixelSize: 13
        onActiveFocusChanged: if (activeFocus) root.last = text; else if (text !== root.last) root.edited(text)
        onAccepted: { root.last = text; root.edited(text); }
    }
    Label {
        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
        visible: input.text.length === 0 && !input.activeFocus
        text: root.placeholder
        size: "small"
        tone: 3
    }
}
