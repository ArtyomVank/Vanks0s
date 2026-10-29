pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.common

// «Желе» окон — только при перетаскивании. В Hyprland одна анимация
// windowsMove и для перетаскивания, и для разворачивания на весь экран, а
// пружина с покачиванием хороша лишь в первом случае. Поэтому перед
// разворачиванием (Mod+F, кнопка окна) ставим плавную кривую без пружины, а
// через полсекунды возвращаем пружину (кривая deltaJelly — из delta-apply).
Singleton {
    id: root

    readonly property real jelly: Number(Settings.get("windows.jelly", 0.5)) || 0
    readonly property bool animations: Settings.get("windows.animations", true) !== false

    function calm() {
        if (jelly <= 0 || !animations || !Hyprland.usingLua) return;
        Hyprland.dispatch('hl.animation({ leaf = "windowsMove", enabled = true, speed = 4.5, bezier = "deltaInOut" })');
        restore.restart();
    }

    function fullscreen() {
        calm();
        Hyprland.dispatch(Hyprland.usingLua ? 'hl.dsp.window.fullscreen()' : "fullscreen 0");
    }

    Timer {
        id: restore
        interval: 650
        onTriggered: if (root.jelly > 0)
            Hyprland.dispatch('hl.animation({ leaf = "windowsMove", enabled = true, speed = 6, spring = "deltaJelly" })')
    }
}
