pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.common
import qs.common.ui
import qs.wallpaper
import qs.widgets

// Отладка модуля D: обои, виджеты рабочего стола, сетка экрана блокировки,
// меню «Погода» и «ПК». Мышь во вложенную сессию не подать, поэтому всё
// управляется через IPC:
//   DELTA_DEV_NAME=widgets DELTA_DEV_HIDDEN=1 DELTA_SHELL_ENTRY=delta/shell/dev-widgets.qml tools/delta-dev.sh nested 300
//   DELTA_DEV_NAME=widgets tools/delta-dev.sh ipc call dev edit true
//   DELTA_DEV_NAME=widgets tools/delta-dev.sh ipc call dev drag weather 240 80
ShellRoot {
    id: root

    Variants {
        id: screens
        model: Quickshell.screens
        delegate: Scope {
            id: per
            required property ShellScreen modelData
            property alias widgets: w
            Wallpaper { screen: per.modelData }
            Widgets { id: w; screen: per.modelData }
        }
    }

    Shortcuts { onWidgets: ShellState.widgetEditing = !ShellState.widgetEditing }

    // экран блокировки «как у модуля B»: WidgetGrid через Loader
    property bool lockShown: false
    LazyLoader {
        active: root.lockShown
        PanelWindow {
            WlrLayershell.namespace: "delta-dev-lock"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: ShellState.lockEditing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: Qt.rgba(0.03, 0.02, 0.07, 0.55)
            Loader {
                id: lockLoader
                anchors.fill: parent
                source: Quickshell.shellDir + "/widgets/WidgetGrid.qml"
                onLoaded: {
                    item.place = "lock";
                    item.editing = Qt.binding(() => ShellState.lockEditing);
                    root.lockGrid = item;
                }
            }
        }
    }
    property var lockGrid: null

    // меню модулей дока в стеклянной подложке, как её рисует док
    property string menu: ""
    LazyLoader {
        active: root.menu.length > 0
        PanelWindow {
            WlrLayershell.namespace: "delta-dev-menu"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; right: true }
            margins { top: 16; right: 16 }
            implicitWidth: 400
            implicitHeight: menuLoader.implicitHeight + 40
            color: "transparent"
            Glass {
                anchors.fill: parent
                strong: true
                Loader {
                    id: menuLoader
                    x: 20; y: 20
                    width: 360
                    source: Quickshell.shellDir + "/menus/" + (root.menu === "pc" ? "PcMenu" : "WeatherMenu") + ".qml"
                }
            }
        }
    }

    // команды идут в сетку рабочего стола или экрана блокировки
    property string target: "desktop"
    function grid() {
        if (target === "lock") return lockGrid;
        const s = screens.instances[0];
        return s ? s.widgets.grid : null;
    }

    IpcHandler {
        target: "dev"

        function use(place: string): void { root.target = place; }
        function edit(on: bool): void { root.target = "desktop"; ShellState.widgetEditing = on; }
        function lock(on: bool): void { root.lockShown = on; if (!on) ShellState.lockEditing = false; }
        function lockEdit(on: bool): void { root.lockShown = true; root.target = "lock"; ShellState.lockEditing = on; }
        function menu(name: string): void { root.menu = name; }

        function select(id: string): void { root.grid().select(id); }
        function add(id: string): void { root.grid().add(id); }
        function remove(id: string): void { root.grid().remove(id); }
        function move(id: string, c: int, r: int): void { root.grid().moveTo(id, c, r); }
        function resize(id: string, w: int, h: int): void { root.grid().resizeTo(id, w, h); }
        function mode(id: string, m: string): void { root.grid().setMode(id, m); }
        function bg(id: string, on: bool): void { root.grid().setBg(id, on); }
        function style(s: string): void { root.grid().setStyle("clock", s); }
        function color(c: string): void { root.grid().setColor("clock", c); }
        function done(): void { root.grid().finish(); }

        // перетаскивание без мыши: показать «тень» и положение, потом drop()
        function drag(id: string, dx: int, dy: int): void { const g = root.grid(); g.select(id); g.beginDrag("move", id); g.updateDrag(dx, dy); }
        function drag2(id: string, dx: int, dy: int): void { const g = root.grid(); g.select(id); g.beginDrag("resize", id); g.updateDrag(dx, dy); }
        function drop(): void { root.grid().endDrag(); }

        function set(key: string, json: string): void { Settings.set(key, JSON.parse(json)); }
        // qs ipc ломает аргументы со сложным JSON («},{»), поэтому раскладку передаём в base64
        function set64(key: string, b64: string): void { Settings.set(key, JSON.parse(Qt.atob(b64))); }
        function get(key: string): string { return JSON.stringify(Settings.get(key, null)); }
        function info(): string {
            const g = root.grid();
            return g ? JSON.stringify({ w: g.width, h: g.height, screens: Quickshell.screens.map(s => s.name + " " + s.width + "x" + s.height), cell: g.cell, cols: g.cols, rows: g.rows, gx: g.gx, gy: g.gy, sel: g.sel, caption: g.caption, items: g.items }) : "нет сетки";
        }
        function notifs(n: int): void {
            const sample = [
                { id: 1, app: "Telegram", summary: "Аня", body: "Встречаемся в семь у входа?", time: Date.now() },
                { id: 2, app: "Почта", summary: "Отчёт за октябрь", body: "Файл во вложении, посмотри до пятницы", time: Date.now() },
                { id: 3, app: "Обновления", summary: "Доступно 12 обновлений", body: "Установить можно в Настройках", time: Date.now() }
            ];
            ShellState.notifications = sample.slice(0, n);
        }
    }
}
