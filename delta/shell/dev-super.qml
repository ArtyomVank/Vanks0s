//@ pragma AppId delta-dev-super
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.wallpaper

// Кадры супер обоев без виджетов и доков: готовые картинки для wallpaper.path
// (wallpaper/super/<id>.jpg) снимаются отсюда.
//     DEV_SUPER=moon DEV_NEAR=1 qs -p shell/dev-super.qml; потом grim
ShellRoot {
    PanelWindow {
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "delta-dev-super"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: "black"
        SuperWall {
            anchors.fill: parent
            near: Quickshell.env("DEV_NEAR") === "1"
            live: false
            spec: SuperWalls.builtin.concat(SuperWalls.flows).find(w => w.id === Quickshell.env("DEV_SUPER")) ?? null
        }
    }
}
