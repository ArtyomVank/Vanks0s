//@ pragma AppId delta-share
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.share

// Что показать в Discord, OBS и браузере — отдельный процесс Quickshell (запуск:
// delta-share-picker, его зовёт портал). AppId задаёт класс окна для правила «delta-share».
ShellRoot {
    // файлы не отслеживаем — см. shell.qml (кроме вложенной сессии)
    settings.watchFiles: (Quickshell.env("DELTA_NESTED") || "") !== ""
    ShareWindow {}
}
