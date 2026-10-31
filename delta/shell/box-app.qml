//@ pragma AppId delta-box
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.box

// Delta Box — отдельный процесс Quickshell (запуск: delta-box). AppId задаёт
// класс окна для правила Hyprland «delta-box».
ShellRoot {
    // файлы не отслеживаем — см. shell.qml (кроме вложенной сессии)
    settings.watchFiles: (Quickshell.env("DELTA_NESTED") || "") !== ""
    BoxWindow {}
}
