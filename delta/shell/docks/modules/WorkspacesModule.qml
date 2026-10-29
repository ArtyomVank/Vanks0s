pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.common

// Рабочие столы: тёмная капсула, в ней точки, активный стол — вытянутая
// светлая пилюля. Нажатие на точку переходит на этот стол (пустой стол
// создаётся), колесо — соседний. Меню модуль не открывает: щелчок
// получает сам (click), ModuleGrid отдаёт его сюда.
// Число точек — docks.top.workspaces (настройки → Доки).
Item {
    id: root

    property bool vertical: false
    property bool full: true
    property ShellScreen screen
    property bool hidden: false

    readonly property HyprlandMonitor monitor: screen ? Hyprland.monitorFor(screen) : null
    readonly property int count: Math.max(2, Math.min(10, Number(Settings.get("docks.top.workspaces", 5)) || 5))
    readonly property int activeId: monitor?.activeWorkspace?.id ?? -1
    // столы 1…count; активный за пределами — добавляется в конец
    readonly property var ids: {
        const n = Math.max(count, activeId > 0 ? activeId : 0);
        const out = [];
        for (let i = 1; i <= n; i++) out.push(i);
        return out;
    }
    // сколько окон на каждом столе — занятые точки ярче
    readonly property var busy: {
        const c = {};
        for (const w of Hyprland.workspaces.values)
            if (w.id > 0) c[w.id] = (w.toplevels?.values?.length ?? 0) > 0;
        return c;
    }
    readonly property var urgent: {
        const c = {};
        for (const w of Hyprland.workspaces.values)
            if (w.id > 0 && w.urgent) c[w.id] = true;
        return c;
    }

    readonly property real dot: 8
    readonly property real pill: 22
    readonly property real gap: 7
    readonly property real thick: 20

    implicitWidth: vertical ? thick : track.width
    implicitHeight: vertical ? track.height : thick

    function go(id) {
        if (id === activeId) return;
        Hyprland.dispatch(Hyprland.usingLua ? "hl.dsp.focus({ workspace = " + id + " })" : "workspace " + id);
    }
    // колесо: следующий / предыдущий стол из показанных
    function wheel(dy) {
        const i = ids.indexOf(activeId);
        const next = ids[Math.max(0, Math.min(ids.length - 1, (i < 0 ? 0 : i) + (dy < 0 ? 1 : -1)))];
        if (next !== undefined) go(next);
    }
    // точка под курсором (координаты модуля) или -1
    function idAt(x, y) {
        const p = row.mapFromItem(root, x, y);
        for (let i = 0; i < rep.count; i++) {
            const it = rep.itemAt(i);
            const along = vertical ? p.y : p.x;
            const s = vertical ? it.y : it.x, e = s + (vertical ? it.height : it.width);
            if (along >= s - gap / 2 && along < e + gap / 2) return it.wid;
        }
        return -1;
    }
    function click(x, y) {
        const id = idAt(x, y);
        if (id > 0) go(id);
    }
    property int hoverId: -1
    function hoverAt(x, y) { hoverId = x < 0 ? -1 : idAt(x, y); }

    Rectangle {
        id: track
        anchors.centerIn: parent
        width: root.vertical ? root.thick : row.width + (root.thick - root.dot)
        height: root.vertical ? row.height + (root.thick - root.dot) : root.thick
        radius: root.thick / 2
        color: Theme.light ? Qt.rgba(0, 0, 0, 0.10) : Qt.rgba(0, 0, 0, 0.34)
        Behavior on width { NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.OutCubic } }

        Grid {
            id: row
            anchors.centerIn: parent
            columns: root.vertical ? 1 : Math.max(1, root.ids.length)
            spacing: root.gap

            Repeater {
                id: rep
                model: root.ids
                delegate: Rectangle {
                    id: d
                    required property int modelData
                    readonly property int wid: modelData
                    readonly property bool active: wid === root.activeId
                    readonly property bool full: root.busy[wid] === true
                    readonly property real len: active ? root.pill : root.dot
                    width: root.vertical ? root.dot : len
                    height: root.vertical ? len : root.dot
                    radius: root.dot / 2
                    color: root.urgent[wid] ? Theme.accent
                         : active ? (Theme.light ? Theme.fg : "#FFFFFF")
                         : Theme.light ? Qt.rgba(0, 0, 0, full ? 0.42 : 0.22)
                         : Qt.rgba(1, 1, 1, full ? 0.42 : 0.18)
                    scale: root.hoverId === wid && !active ? 1.3 : 1
                    Behavior on width { NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                    Behavior on height { NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                    Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
                    Behavior on scale { NumberAnimation { duration: Theme.anim.fast; easing.type: Easing.OutBack } }
                }
            }
        }
    }
}
