pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common

// Подсветка края при перетаскивании окна: курсор у левого или правого края —
// половина экрана, у угла — четверть, у верхнего — весь экран. Отпустили —
// окно занимает подсвеченное место (это делает hyprland.lua, раздел
// «ПЕРЕТАСКИВАНИЕ»). Выключается в «Настройки → Экран» (windows.snap).
Scope {
    id: root

    readonly property bool enabled: Settings.get("windows.snap", true) !== false

    Connections {
        target: DragState
        function onMoved() {
            if (!root.enabled) return;
            if (DragState.zone !== root.lastZone) {
                if (DragState.zone !== "") Sounds.play("snap-in", 60);
                root.lastZone = DragState.zone;
            }
        }
        function onEnded(snapped) {
            if (root.enabled && snapped) Sounds.play("snap", 60);
            root.lastZone = "";
        }
    }
    property string lastZone: ""

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData

            readonly property bool here: root.enabled && DragState.dragging && DragState.zone !== ""
                                         && DragState.monitor === modelData.name
            // зону помним и после конца перетаскивания — пока гаснет
            property rect zone
            onHereChanged: if (here) zone = DragState.zoneRect
            Connections {
                target: DragState
                function onMoved() { if (win.here) win.zone = DragState.zoneRect; }
            }

            visible: here || plate.opacity > 0.01
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "delta-snap"
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            mask: Region {}

            Rectangle {
                id: plate
                readonly property real zx: win.zone.x - win.modelData.x
                readonly property real zy: win.zone.y - win.modelData.y
                x: zx; y: zy
                width: win.zone.width; height: win.zone.height
                radius: Math.max(12, Number(Settings.get("windows.rounding", 16)) || 0)
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                border.width: 2
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.85)
                opacity: win.here ? 1 : 0
                scale: win.here ? 1 : 0.94

                Behavior on x { NumberAnimation { duration: 220 * Theme.anim.k; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 220 * Theme.anim.k; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: 220 * Theme.anim.k; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 220 * Theme.anim.k; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180 * Theme.anim.k } }
                Behavior on scale { NumberAnimation { duration: 260 * Theme.anim.k; easing.type: Easing.OutBack } }

                // стеклянный блик сверху и мягкое свечение по краю
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.14) }
                        GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0.03) }
                        GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -6
                    radius: parent.radius + 6
                    color: "transparent"
                    border.width: 6
                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                    SequentialAnimation on opacity {
                        running: win.here
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.4; to: 1; duration: 700 * Theme.anim.k; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 1; to: 0.4; duration: 700 * Theme.anim.k; easing.type: Easing.InOutSine }
                    }
                }
            }
        }
    }
}
