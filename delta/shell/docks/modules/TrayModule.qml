pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.common
import qs.common.ui
import qs.docks

// Фоновые приложения (значки трея, StatusNotifierItem): Steam, Discord,
// Telegram и другие, что работают без окна. Щелчок — открыть программу,
// правый — её меню, средний — второе действие. Значков не больше
// docks.top.opts.trayMax (остальные — в «+N», щелчок по нему — меню
// последнего скрытого). Нет фоновых программ — модуль скрыт.
//
// Левый щелчок дока приходит через click(x, y) (ModuleGrid), правый и
// средний его MouseArea пропускает — их ловит MouseArea модуля.
Item {
    id: root
    property bool vertical: false
    property bool full: true
    property ShellScreen screen

    readonly property var items: SystemTray.items.values.filter(i => i && i.status !== Status.Passive)
    readonly property int max: Math.max(1, Number(DockService.opt("trayMax", 5)) || 5)
    readonly property var shownItems: items.slice(0, max)
    readonly property int extra: Math.max(0, items.length - max)
    readonly property bool hidden: items.length === 0

    readonly property int icon: 18
    readonly property int gap: 8

    implicitWidth: vertical ? icon : list.implicitWidth
    implicitHeight: vertical ? list.implicitHeight : icon

    function itemAt(x, y) {
        const c = list.childAt(x - list.x, y - list.y);
        return c && c.trayItem !== undefined ? c : null;
    }
    // меню программы под значком cell («+N» — последней скрытой)
    function showMenu(cell) {
        if (!cell) return;
        const it = cell.trayItem ?? items[items.length - 1];
        const win = root.QsWindow.window;
        if (!it || !it.hasMenu || !win) return;
        const p = cell.mapToItem(null, 0, cell.height + 10);
        it.display(win, Math.round(p.x), Math.round(p.y));
    }
    function click(x, y) {
        const c = itemAt(x, y);
        if (!c) return;
        // «+N» и программы «только меню» (onlyMenu) — меню, остальные — открыть
        if (c.trayItem === null || c.trayItem.onlyMenu) showMenu(c);
        else c.trayItem.activate();
    }
    // наведение приходит от ModuleGrid (его MouseArea над модулем)
    property var hoveredItem: null
    function hoverAt(x, y) {
        const c = x < 0 ? null : itemAt(x, y);
        hoveredItem = c ? c.trayItem : null;
    }
    function wheel(dir) { if (hoveredItem) hoveredItem.scroll(dir * 120, false); }

    Grid {
        id: list
        anchors.centerIn: parent
        columns: root.vertical ? 1 : Math.max(1, rep.count + (root.extra > 0 ? 1 : 0))
        spacing: root.gap

        Repeater {
            id: rep
            model: ScriptModel { values: root.shownItems; objectProp: "id" }
            delegate: Item {
                id: cell
                required property var modelData
                readonly property var trayItem: modelData
                readonly property bool hovered: root.hoveredItem === modelData
                width: root.icon
                height: root.icon
                IconImage {
                    anchors.fill: parent
                    source: cell.modelData.icon
                    asynchronous: true
                    opacity: cell.modelData.status === Status.NeedsAttention || cell.hovered ? 1 : 0.85
                }
            }
        }

        // «+N»: сколько не поместилось
        Item {
            visible: root.extra > 0
            readonly property var trayItem: null
            width: plus.implicitWidth
            height: root.icon
            Label {
                id: plus
                anchors.centerIn: parent
                text: "+" + root.extra
                size: "caption"
                tone: 2
                font.weight: Font.Bold
            }
        }
    }

    // правый щелчок — меню программы, средний — её второе действие
    MouseArea {
        anchors.fill: list
        acceptedButtons: Qt.RightButton | Qt.MiddleButton
        onClicked: m => {
            const c = root.itemAt(m.x + list.x, m.y + list.y);
            if (!c) return;
            if (m.button === Qt.MiddleButton && c.trayItem) c.trayItem.secondaryActivate();
            else root.showMenu(c);
        }
    }
}
