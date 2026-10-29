pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.common
import qs.common.ui
import qs.wallpaper
import qs.launcher
import qs.walls

// Отладка модуля C: лаунчер, выбор обоев, обои, быстрые меню, разделы настроек.
//   DELTA_DEV_NAME=launcher DELTA_DEV_HIDDEN=1 DELTA_SHELL_ENTRY=delta/shell/dev-launcher.qml tools/delta-dev.sh nested 300
//   … ipc call dev launcher "fire"            окно приложений с запросом
//   … ipc call dev walls video violet ""      выбор обоев с фильтрами
//   … ipc call dev menu Sound                 меню в стеклянной подложке (как в доке)
//   … ipc call dev viz 0.8                    подставной уровень визуализатора (-1 — настоящий)
//   … ipc call dev section Wallpapers         раздел «Настроек»
//   … ipc call dev close                      закрыть всё
ShellRoot {
    id: dev

    Variants {
        model: Quickshell.screens
        delegate: Wallpaper { required property ShellScreen modelData; screen: modelData }
    }

    Launcher { id: launcher }
    Wallpapers { id: walls }

    Shortcuts {
        onLauncher: ShellState.toggleOverlay("launcher")
        onWallpapers: ShellState.toggleOverlay("wallpapers")
    }

    property string menu: ""
    property string section: ""
    property real vizDemo: -1
    property alias menuHost: menuLoader

    IpcHandler {
        target: "dev"

        function launcher(query: string): void { launcher.show(query); }
        function walls(type: string, color: string, query: string): void { walls.show(type, color, query); }
        function colors(): string { return JSON.stringify(WallStore.colors); }
        function menu(id: string): void { dev.menu = id; }
        function section(name: string): void { dev.section = name; }
        // вызвать функцию открытого меню: ipc call dev act pick 1
        function act(fn: string, arg: string): string {
            const it = dev.menuHost.item;
            if (!it || typeof it[fn] !== "function") return "нет функции";
            it[fn](isNaN(Number(arg)) ? arg : Number(arg));
            return "ok";
        }
        function viz(level: real): void { dev.vizDemo = level; }
        function lock(on: bool): void { ShellState.locked = on; }
        function close(): void { ShellState.closeOverlay(); dev.menu = ""; dev.section = ""; }
        function set(key: string, json: string): void { Settings.set(key, JSON.parse(json)); }
        function get(key: string): string { return JSON.stringify(Settings.get(key, null)); }
    }

    // Меню модулей обычно показывает верхний док (модуль A). Здесь — та же
    // стеклянная подложка у правого верхнего угла.
    PanelWindow {
        visible: dev.menu.length > 0
        anchors { top: true; right: true }
        margins { top: 14; right: 14 }
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "delta-menu-dev"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        implicitWidth: (menuLoader.item?.implicitWidth ?? 320) + 32
        implicitHeight: Math.min(760, (menuLoader.item?.implicitHeight ?? 100) + 32)

        Glass {
            anchors.fill: parent
            strong: true
            radius: 22

            Loader {
                id: menuLoader
                anchors { fill: parent; margins: 16 }
                source: dev.menu.length ? Quickshell.shellDir + "/menus/" + dev.menu + "Menu.qml" : ""
                onLoaded: if (item.vizDemo !== undefined) item.vizDemo = Qt.binding(() => dev.vizDemo)
                Connections {
                    target: menuLoader.item
                    ignoreUnknownSignals: true
                    function onClose() { dev.menu = ""; }
                }
            }
        }
    }

    // Разделы «Настроек» (обычно их показывает приложение модуля F)
    PanelWindow {
        visible: dev.section.length > 0
        anchors { top: true; bottom: true }
        margins { top: 30; bottom: 30 }
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "delta-section-dev"
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        implicitWidth: 680

        Glass {
            anchors.fill: parent
            strong: true
            radius: 22

            Flickable {
                anchors { fill: parent; margins: 24 }
                contentHeight: sectionLoader.item?.implicitHeight ?? 0
                clip: true
                Loader {
                    id: sectionLoader
                    width: parent.width
                    source: dev.section.length ? Quickshell.shellDir + "/settings/sections/" + dev.section + ".qml" : ""
                }
            }
        }
    }
}
