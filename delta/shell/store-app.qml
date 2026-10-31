//@ pragma AppId delta-store
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.store

// Магазин Delta — отдельный процесс Quickshell (запуск: delta-store). AppId
// задаёт класс окна для правила Hyprland «delta-store».
ShellRoot {
    // файлы не отслеживаем — см. shell.qml (кроме вложенной сессии)
    settings.watchFiles: (Quickshell.env("DELTA_NESTED") || "") !== ""
    StoreWindow {}
}
