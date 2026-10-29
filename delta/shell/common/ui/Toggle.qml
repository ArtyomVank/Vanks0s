import QtQuick
import qs.common

// Переключатель.
//     Toggle { checked: Settings.get("notifications.dnd", false); onToggled: v => Settings.set("notifications.dnd", v) }
Rectangle {
    id: root

    property bool checked: false
    property bool enabled: true
    signal toggled(bool value)

    implicitWidth: 44
    implicitHeight: 26
    radius: height / 2
    opacity: enabled ? 1 : 0.45
    color: checked ? Theme.accent : Theme.soft2
    border.width: checked ? 0 : 1
    border.color: Theme.line
    Behavior on color { ColorAnimation { duration: Theme.anim.fast } }

    Rectangle {
        width: parent.height - 6
        height: width
        radius: width / 2
        y: 3
        x: root.checked ? root.width - width - 3 : 3
        // на светлом акценте белая ручка пропала бы
        color: root.checked ? Theme.onAccent : "#ffffff"
        Behavior on x { NumberAnimation { duration: Theme.anim.normal; easing.type: Theme.anim.springCurve } }
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
    TapHandler {
        enabled: root.enabled
        onTapped: root.toggled(!root.checked)
    }
}
