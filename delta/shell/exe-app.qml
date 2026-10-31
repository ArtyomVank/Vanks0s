//@ pragma AppId delta-exe
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.exe

// Как открыть программу Windows — отдельный процесс Quickshell (запуск:
// delta-exe <файл>). AppId задаёт класс окна для правила Hyprland «delta-exe».
ShellRoot {
    // файлы не отслеживаем — см. shell.qml (кроме вложенной сессии)
    settings.watchFiles: (Quickshell.env("DELTA_NESTED") || "") !== ""
    ExeWindow {}
}
