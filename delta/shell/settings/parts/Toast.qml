import QtQuick
import qs.common
import qs.common.ui
import qs.settings

// Короткая подсказка внизу окна: «Сохранено», «Пробный режим: …», ошибки.
// Показывается на Nav.toast(текст).
Rectangle {
    id: root

    property bool shown: false
    z: 1000

    anchors.horizontalCenter: parent.horizontalCenter
    y: parent.height - (shown ? height + 22 : -10)
    width: Math.min(parent.width - 80, lbl.implicitWidth + 40)
    height: 40
    radius: 20
    color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.96)
    border.color: Theme.line
    opacity: shown ? 1 : 0
    Behavior on y { NumberAnimation { duration: Theme.anim.normal; easing.type: Theme.anim.outCurve } }
    Behavior on opacity { NumberAnimation { duration: Theme.anim.fast } }

    Label {
        id: lbl
        anchors.centerIn: parent
        width: Math.min(implicitWidth, root.width - 40)
        text: Nav.toastText
    }

    Timer { id: hide; interval: 3200; onTriggered: root.shown = false }
    Connections {
        target: Nav
        function onToastSerialChanged() { root.shown = true; hide.restart(); }
    }
}
