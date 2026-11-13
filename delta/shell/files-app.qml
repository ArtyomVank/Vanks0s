//@ pragma AppId delta-files
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.files

// Файлы Delta — отдельный процесс Quickshell (запуск: delta-files [папка]).
// AppId задаёт класс окна для правила Hyprland «delta-files».
ShellRoot {
    // файлы не отслеживаем — см. shell.qml (кроме вложенной сессии)
    settings.watchFiles: (Quickshell.env("DELTA_NESTED") || "") !== ""
    FilesWindow {}
}
