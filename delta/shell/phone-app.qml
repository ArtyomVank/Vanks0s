//@ pragma AppId delta-phone
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.phone

// «Телефон» — отдельный процесс Quickshell (запуск: delta-phone). AppId задаёт
// класс окна для правила композитора «delta-phone».
ShellRoot {
    // файлы не отслеживаем — см. shell.qml (кроме вложенной сессии)
    settings.watchFiles: (Quickshell.env("DELTA_NESTED") || "") !== ""
    PhoneWindow {}
}
