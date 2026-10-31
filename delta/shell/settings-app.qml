//@ pragma AppId delta-settings
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.settings

// Разделы грузятся по пути; модули qs.*, которые импортируют только они,
// без статического импорта Quickshell не находит («module is not installed»).
import qs.settings.parts
import qs.display
import qs.display.parts
import qs.lock
import qs.lock.parts
import qs.walls
import qs.services
import qs.widgets.parts
import qs.launcher.parts

// «Настройки» Delta — отдельный процесс Quickshell (запуск: delta-settings).
// AppId задаёт класс окна для правила Hyprland «delta-settings».
ShellRoot {
    // файлы не отслеживаем — см. shell.qml (кроме вложенной сессии)
    settings.watchFiles: (Quickshell.env("DELTA_NESTED") || "") !== ""
    SettingsWindow {}
}
