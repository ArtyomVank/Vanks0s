import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.common.ui

// Меню питания по центру экрана (Super+Escape, ShellState.overlay === "power").
// Затемнение вокруг, карточка «выпрыгивает» с пружиной; клик мимо или Esc — закрыть.
PanelWindow {
    id: root

    signal dismissed()

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "delta-power"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    property bool shown: false
    property alias confirm: panel.confirm
    function dismiss() {
        if (!shown) return;
        shown = false;
        closeTimer.restart();
    }
    Timer { id: closeTimer; interval: Theme.anim.normal; onTriggered: root.dismissed() }
    Component.onCompleted: shown = true

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.35)
        opacity: root.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.anim.normal; easing.type: Theme.anim.outCurve } }
        MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    Glass {
        id: card
        strong: true
        anchors.centerIn: parent
        width: 380
        height: panel.implicitHeight + 40
        radius: Theme.radius + 6
        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 0.92
        Behavior on opacity { NumberAnimation { duration: Theme.anim.normal; easing.type: Theme.anim.outCurve } }
        Behavior on scale { NumberAnimation { duration: Theme.anim.slow; easing.type: Theme.anim.springCurve; easing.overshoot: 1.3 } }

        // клики по карточке не закрывают окно
        MouseArea { anchors.fill: parent }

        PowerPanel {
            id: panel
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            onClose: root.dismiss()
        }
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: {
            if (panel.confirm !== "") panel.confirm = "";
            else root.dismiss();
        }
    }
}
