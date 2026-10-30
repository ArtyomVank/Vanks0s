pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// Разворачивание окна на весь экран (Mod+F, кнопка окна). Раньше здесь на
// время разворачивания снималась пружина «желе»; теперь «желе» рисует
// оболочка только при перетаскивании (Jelly.qml), а перемещение окон в
// Hyprland — плавная кривая без пружины (delta-apply).
Singleton {
    id: root

    function fullscreen() {
        Hyprland.dispatch(Hyprland.usingLua ? 'hl.dsp.window.fullscreen()' : "fullscreen 0");
    }
}
