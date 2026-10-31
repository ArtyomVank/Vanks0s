//@ pragma AppId delta-exe-manager
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.exe

// «Программы Windows» — отдельный процесс Quickshell (запуск: delta-exe
// --manager). AppId задаёт класс окна для правила Hyprland «delta-exe-manager».
ShellRoot {
    ManagerWindow {}
}
