//@ pragma AppId delta-welcome
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.welcome

// Помощник «Добро пожаловать» — отдельный процесс Quickshell (запуск:
// delta-welcome). AppId задаёт класс окна для правила Hyprland «delta-welcome».
ShellRoot {
    WelcomeWindow {}
}
