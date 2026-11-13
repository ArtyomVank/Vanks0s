//@ pragma AppId delta-video
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.video

// Видео Delta — отдельный процесс Quickshell (запуск: delta-video [файл]).
// AppId задаёт класс окна для правила Hyprland «delta-video».
ShellRoot {
    // файлы не отслеживаем — см. shell.qml (кроме вложенной сессии)
    settings.watchFiles: (Quickshell.env("DELTA_NESTED") || "") !== ""
    VideoWindow {}
}
