//@ pragma AppId delta-android
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.android

// «Android» — отдельный процесс Quickshell (запуск: delta-android). AppId задаёт
// класс окна для правила композитора «delta-android».
ShellRoot {
    // файлы не отслеживаем — см. shell.qml (кроме вложенной сессии)
    settings.watchFiles: (Quickshell.env("DELTA_NESTED") || "") !== ""
    AndroidWindow {}
}
