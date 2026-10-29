//@ pragma UseQApplication
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import qs.common.ui
import qs.wallpaper
import qs.docks
import qs.notify
import qs.osd
// меню модулей (C, D, B) берут части отсюда; Quickshell регистрирует модуль qs.* только
// если его импортирует статически загруженный файл — в shell.qml это делает Launcher
import qs.launcher.parts
import qs.lock
import qs.widgets.parts

// Отладка модуля A: обои, доки, уведомления и OSD.
//   DELTA_DEV_NAME=docks DELTA_DEV_HIDDEN=1 DELTA_DEV_PRIVATE_BUS=1 \
//   DELTA_SHELL_ENTRY=delta/shell/dev-docks.qml tools/delta-dev.sh nested 300
// Состояния без мыши: tools/delta-dev.sh ipc call dev <функция> …
ShellRoot {
    id: root

    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: perScreen
            required property ShellScreen modelData
            Wallpaper { screen: perScreen.modelData }
            Docks { screen: perScreen.modelData }
        }
    }

    // предпросмотр разделов «Настроек» (Docks, Notifications) — dev.section("Docks")
    property string section: ""
    LazyLoader {
        active: root.section !== ""
        FloatingWindow {
            title: "Delta: раздел " + root.section
            implicitWidth: 720
            implicitHeight: 780
            color: "transparent"
            Glass {
                anchors.fill: parent
                strong: true
                Flickable {
                    anchors { fill: parent; margins: 24 }
                    contentHeight: sec.item ? sec.item.implicitHeight : 0
                    clip: true
                    Loader { id: sec; width: parent.width; source: Qt.resolvedUrl("settings/sections/" + root.section + ".qml") }
                }
            }
        }
    }

    Notifications { id: notifications }
    Osd { id: osd }

    IpcHandler {
        target: "shell"
        function reload(): void { Quickshell.reload(true); }
        function get(key: string): string { return JSON.stringify(Settings.get(key, null)); }
        function set(key: string, json: string): void { Settings.set(key, JSON.parse(json)); }
    }

    IpcHandler {
        target: "dev"

        // меню модуля верхнего дока: wifi, sound, notifications, … ("" — закрыть)
        function menu(id: string): void {
            if (id === "") ShellState.closeMenu();
            else ShellState.openMenu(id, Quickshell.screens[0]);
        }
        function edit(on: bool): void { ShellState.dockEditing = on; }
        // «мышь у края» для автоскрытия
        function peek(on: bool): void { DockService.peek = on; }
        function forced(on: bool): void { ShellState.overlay = on ? "launcher" : ""; }
        // подставной плеер: media(true, "Трек", "Исполнитель")
        function media(on: bool, title: string, artist: string): void {
            DockService.fake = on ? { title: title, artist: artist, art: "", playing: true } : null;
        }
        function pause(): void { DockService.togglePlaying(); }
        function mediaView(): void { DockService.toggleMediaView(); }
        // меню дока приложений: "add" | "context" (для первого закреплённого)
        function appMenu(mode: string): void {
            const s = Quickshell.screens[0];
            if (mode === "") { DockService.closeAppMenu(); return; }
            const g = ShellState.dockGeometry[s.name]?.apps ?? { x: s.width / 2, y: s.height - 90, w: 60, h: 76 };
            const first = DockService.pinnedRaw[0];
            DockService.openAppMenu(s, mode, mode === "add" ? null : { key: DockService.pinKey(first), kind: typeof first === "string" ? "app" : first.type, id: first, name: String(first) },
                                    { x: g.x + 80, y: g.y, w: 48, h: 48 });
        }
        function moveModule(id: string, cell: int): bool { return DockService.moveModule(id, cell); }
        // OSD с подставным значением (громкость системы не трогаем): volume | mic | brightness
        function osd(kind: string, value: real, muted: bool): void { osd.show(kind, value, muted); }
        // OSD раскладки (как при переключении)
        function lang(): void { KbLayout.switched(); }
        function center(): void { notifications.toggleCenter(); }
        function dnd(on: bool): void { ShellState.dnd = on; }
        function notifs(): string { return JSON.stringify(ShellState.notifications); }
        function section(name: string): void { root.section = name; }
        function geometry(): string { return JSON.stringify({ docks: ShellState.dockGeometry, icons: ShellState.appIconGeometry }); }
    }
}
