//@ pragma UseQApplication
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import qs.wallpaper
import qs.docks
import qs.notify
import qs.osd
import qs.lock
import qs.launcher
import qs.walls
import qs.widgets
import qs.display
import qs.minimize
import qs.window
import qs.appearance
import qs.polkit
import qs.oobe
import qs.fx

// Меню доков и разделы грузятся через Loader по пути. Модули qs.*, которые
// импортируют только они, Quickshell без статического импорта не находит
// («module is not installed»), поэтому они перечислены здесь.
import qs.launcher.parts
import qs.lock.parts
import qs.widgets.parts
import qs.services
import qs.display.parts

// Delta — точка входа оболочки.
ShellRoot {
    id: root

    // Файлы не отслеживаем: обновление пакета меняет их по одному, и
    // перезагрузка на полпути показала бы ошибку сверху экрана (или уронила
    // окно). Новая версия начинает работать после перезагрузки. Во вложенной
    // сессии разработчика (DELTA_NESTED) правки подхватываются сразу.
    settings.watchFiles: (Quickshell.env("DELTA_NESTED") || "") !== ""

    // Обои, доки и виджеты на каждом мониторе.
    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: perScreen
            required property ShellScreen modelData

            Wallpaper { screen: perScreen.modelData }
            Widgets { screen: perScreen.modelData }
            Docks { screen: perScreen.modelData }
        }
    }

    // По одному на всю оболочку: сервер уведомлений должен быть один.
    Notifications { id: notifications }
    Osd { id: osd }
    Lock { id: lock }          // показывает и окно питания (overlay "power")
    Launcher {}
    Wallpapers {}
    DesktopMenu {}         // правый щелчок по рабочему столу: виджеты, обои, настройки
    Minimize {}            // слой «джинна» на каждом мониторе
    DeskClear {}           // окна уходят с рабочего стола на время правки виджетов
    WindowControls {}      // кнопки свернуть / развернуть / закрыть на активном окне
    Jelly {}               // «желе»: низ перетаскиваемого окна отстаёт (window/DragState)
    Snap {}                // подсветка края: окно прилипает к половине, четверти, всему экрану
    SettingsGhost {}       // «Настройки» выходят каплей из верхнего дока
    ThemeSync {}           // оформление для программ GTK/Qt
    Polkit {}              // окно «Нужно подтверждение» (агент polkit)
    UpdateCheck {}         // фоновая проверка обновлений и уведомление о них
    VolumeMemory {}        // громкость и «без звука» между входами (если WirePlumber не вернул)
    ShellFx {}             // звуки рабочих столов, меню, острова; вспышка снимка (ipc fx flash)
    Oobe {}                // первая настройка при первом входе (delta-shell ipc call oobe start)

    // Раскладка мониторов по набору подключённых экранов; ночной свет
    // запускается при первом обращении к синглтону.
    Component.onCompleted: {
        Displays.manageProfiles = true;
        NightLight.checked;
    }

    Shortcuts {
        onLauncher: ShellState.toggleOverlay("launcher")
        onWallpapers: ShellState.toggleOverlay("wallpapers")
        onNotifications: notifications.toggleCenter()
        onWidgets: ShellState.widgetEditing = !ShellState.widgetEditing
        onSettings: ShellState.openSettings("", null)
        onLock: lock.lock()
        onPower: ShellState.toggleOverlay("power")
        onVolume: action => osd.volume(action)
        onBrightness: action => osd.brightness(action)
        onScreenshot: Quickshell.execDetached(["sh", "-c", 'g=$(slurp) && grim -g "$g" - | wl-copy -t image/png && delta-shell ipc call fx flash' + Sounds.shell("camera-shutter")])
        onMinimize: Minimizer.minimizeActive()
        onFullscreen: Motion.fullscreen()
    }

    // delta-shell ipc call shell <функция>
    IpcHandler {
        target: "shell"

        function reload(): void { Quickshell.reload(true); }
        function get(key: string): string { return JSON.stringify(Settings.get(key, null)); }
        function set(key: string, json: string): void { Settings.set(key, JSON.parse(json)); }
        // окно приложений, обоев, питания: delta-shell ipc call shell overlay launcher
        function overlay(name: string): void { ShellState.toggleOverlay(name); }
        function center(): void { notifications.toggleCenter(); }
        function widgets(): void { ShellState.widgetEditing = !ShellState.widgetEditing; }
    }
}
