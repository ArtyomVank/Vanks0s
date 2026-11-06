pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.common
import qs.common.ui
import qs.docks
import qs.services

// Фоновые приложения (значки трея, StatusNotifierItem): Steam, Discord,
// Telegram и другие, что работают без окна. Щелчок — открыть программу,
// правый — её меню, средний — второе действие. Значков не больше
// docks.top.opts.trayMax (остальные — в «+N», щелчок по нему — меню
// последнего скрытого). Нет фоновых программ — модуль скрыт.
//
// Перед значками — то, что трей сам не покажет:
//   • щит, пока включён VPN (services/Vpn.qml), — если у VPN-программы нет
//     своего значка; щелчок — меню питания с переключателем VPN;
//   • запущенные программы Windows (services/WinApps.qml): их значки трея
//     старого вида (XEmbed), панели Wayland их не видят. Щелчок — окно
//     программы, правый — «Программы Windows».
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
    // VPN: щит не нужен, если значок своей программы уже в трее
    readonly property bool vpnHasIcon: {
        const words = Vpn.activeName.toLowerCase().split(/[^a-zа-я0-9]+/).filter(w => w.length >= 3 && ["tun", "vpn"].indexOf(w) === -1);
        return items.some(i => {
            const t = ((i.id || "") + " " + (i.title || "")).toLowerCase();
            return t.indexOf("vpn") !== -1 || words.some(w => t.indexOf(w) !== -1);
        });
    }
    readonly property var virtItems: (Vpn.active && !vpnHasIcon ? [{ key: "vpn", kind: "vpn", name: Vpn.activeName }] : [])
        .concat(WinApps.apps.map(a => ({ key: "win:" + a.key, kind: "win", app: a, name: a.name })))
    Component.onCompleted: { Vpn.watch = true; WinApps.watch = true; }
    readonly property bool hidden: items.length === 0 && virtItems.length === 0

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
        if (c.virt) {
            if (c.virt.kind === "vpn") ShellState.openMenu("power", root.screen);
            else WinApps.focus(c.virt.app);
            return;
        }
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
        columns: root.vertical ? 1 : Math.max(1, virtRep.count + rep.count + (root.extra > 0 ? 1 : 0))
        spacing: root.gap

        // щит VPN и программы Windows
        Repeater {
            id: virtRep
            model: ScriptModel { values: root.virtItems; objectProp: "key" }
            delegate: Item {
                id: vcell
                required property var modelData
                readonly property var trayItem: null
                readonly property var virt: modelData
                width: root.icon
                height: root.icon
                Sym {
                    anchors.centerIn: parent
                    visible: vcell.virt.kind === "vpn"
                    name: "vpn"
                    size: root.icon
                    color: Theme.accent
                }
                IconImage {
                    id: winIcon
                    anchors.fill: parent
                    visible: vcell.virt.kind === "win" && status === Image.Ready
                    source: vcell.virt.kind === "win" ? vcell.virt.app.icon : ""
                    asynchronous: true
                }
                Sym {
                    anchors.centerIn: parent
                    visible: vcell.virt.kind === "win" && !winIcon.visible
                    name: "windows"
                    size: root.icon - 2
                    color: Theme.fg2
                }
            }
        }

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
            if (c.virt) {
                if (c.virt.kind === "win") Quickshell.execDetached(["delta-exe", "--manager"]);
                else ShellState.openMenu("power", root.screen);
                return;
            }
            if (m.button === Qt.MiddleButton && c.trayItem) c.trayItem.secondaryActivate();
            else root.showMenu(c);
        }
    }
}
