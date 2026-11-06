import QtQuick
import QtQuick.Effects
import qs.common

// Переключатель. Щёлкает мягким звуком вверх или вниз (Sounds: toggle-on/off).
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

    // «Акрил»: включённый переключатель светится акцентом
    RectangularShadow {
        z: -1
        anchors.fill: parent
        visible: Theme.acrylic
        opacity: root.checked ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.anim.normal } }
        radius: root.radius
        blur: 16
        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.light ? 0.35 : 0.55)
    }

    Rectangle {
        // Material 3: ручка выключенного меньше, нажатая — больше
        width: Theme.material ? (press.pressed ? parent.height - 2 : root.checked ? parent.height - 6 : parent.height - 12) : parent.height - 6
        height: width
        radius: width / 2
        y: (parent.height - height) / 2
        x: root.checked ? root.width - width - (parent.height - width) / 2 : (parent.height - width) / 2
        Behavior on width { enabled: Theme.material; SpringAnimation { spring: 8; damping: 0.45; epsilon: 0.1 } }
        // на светлом акценте белая ручка пропала бы
        color: root.checked ? Theme.onAccent : "#ffffff"
        Behavior on x { NumberAnimation { duration: Theme.anim.normal; easing.type: Theme.anim.springCurve } }
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
    TapHandler {
        id: press
        enabled: root.enabled
        onTapped: {
            Sounds.play(root.checked ? "toggle-off" : "toggle-on", 40);
            root.toggled(!root.checked);
        }
    }
}
