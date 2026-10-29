import QtQuick
import qs.common

// Кнопка. kind: "soft" (по умолчанию) · "accent" · "ghost" · "danger".
// Можно только иконку (круглая), только текст или иконку с текстом.
//     Btn { icon: "power"; text: "Выключить"; kind: "danger"; onClicked: … }
Rectangle {
    id: root

    property string text
    property string icon
    property string kind: "soft"
    property bool active: false
    property bool enabled: true
    property int iconSize: 18
    signal clicked()

    readonly property bool round: text.length === 0
    readonly property color fgColor: kind === "accent" || active ? Theme.onAccent : kind === "danger" ? "#ff6b6b" : Theme.fg

    implicitHeight: 36
    implicitWidth: round ? implicitHeight : row.implicitWidth + 28
    radius: height / 2
    opacity: enabled ? 1 : 0.45
    color: kind === "accent" || active ? Theme.accent
         : kind === "ghost" ? "transparent"
         : kind === "danger" ? Qt.rgba(1, 0.42, 0.42, 0.14)
         : Theme.soft2
    border.width: kind === "ghost" ? 1 : 0
    border.color: Theme.line

    scale: tap.pressed ? 0.95 : 1
    Behavior on scale { NumberAnimation { duration: Theme.anim.fast; easing.type: Theme.anim.outCurve } }
    Behavior on color { ColorAnimation { duration: Theme.anim.fast } }

    // подсветка при наведении
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Theme.fg
        opacity: hover.hovered && root.enabled ? 0.07 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.anim.fast } }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8
        Sym {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon.length > 0
            name: root.icon
            size: root.iconSize
            color: root.fgColor
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.round
            text: root.text
            color: root.fgColor
            font.weight: Font.Medium
        }
    }

    HoverHandler { id: hover; cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler { id: tap; enabled: root.enabled; onTapped: root.clicked() }
}
