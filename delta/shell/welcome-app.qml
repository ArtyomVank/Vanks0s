//@ pragma AppId delta-welcome
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.welcome

// Помощник «Добро пожаловать» — отдельный процесс Quickshell (запуск:
// delta-welcome). AppId задаёт класс окна для правила Hyprland «delta-welcome».
ShellRoot {
    // файлы не отслеживаем — см. shell.qml (кроме вложенной сессии)
    settings.watchFiles: (Quickshell.env("DELTA_NESTED") || "") !== ""
    WelcomeWindow {}
}
