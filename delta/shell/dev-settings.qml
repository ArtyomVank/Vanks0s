//@ pragma AppId delta-settings
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.wallpaper
import qs.settings

// Отладка «Настроек» во вложенной сессии: обои и окно настроек.
// Всегда пробный режим — системные команды только пишутся в журнал.
//   DELTA_DEV_NAME=settings DELTA_DEV_HIDDEN=1 DELTA_SHELL_ENTRY=delta/shell/dev-settings.qml tools/delta-dev.sh nested 300
//   DELTA_DEV_NAME=settings tools/delta-dev.sh ipc call settings open keyboard
ShellRoot {
    Component.onCompleted: Exec.forceDry = true

    Variants {
        model: Quickshell.screens
        delegate: Wallpaper { required property ShellScreen modelData; screen: modelData }
    }

    SettingsWindow { quitOnClose: false }
}
