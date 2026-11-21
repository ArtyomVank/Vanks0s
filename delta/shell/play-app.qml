//@ pragma AppId delta-play
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.play

// Delta Play — библиотека игр, отдельный процесс Quickshell (запуск:
// delta-play). AppId задаёт класс окна для правила Hyprland «delta-play».
// Игровой режим и панель Super+G живут в самой оболочке (play/PlayOverlay,
// services/GameMode), здесь — только окно библиотеки.
ShellRoot {
    // файлы не отслеживаем — см. shell.qml (кроме вложенной сессии)
    settings.watchFiles: (Quickshell.env("DELTA_NESTED") || "") !== ""
    LibraryWindow {}
}
