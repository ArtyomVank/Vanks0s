pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.common

// На время редактора виджетов окна убираются с рабочего стола, а после
// «Готово» возвращаются на свои столы — виджеты видно целиком.
//
// Окна видимых столов всех мониторов уезжают на скрытый стол
// special:delta-desk (Hyprland сам играет их исчезновение). Если оболочку
// перезапустили посреди редактора, при старте окна оттуда возвращаются.
Scope {
    id: root

    readonly property string parkWs: "special:delta-desk"
    // адрес окна (без 0x) → id стола, откуда его убрали
    property var parked: ({})
    property string lastActive: ""

    function norm(a) { return String(a || "").replace(/^0x/, ""); }
    function moveTo(addr, ws) {
        Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + ws + '", follow = false, window = "address:0x' + addr + '" })');
    }

    function park() {
        const shown = Hyprland.monitors.values.map(m => m.activeWorkspace?.id).filter(id => id !== undefined && id !== null);
        lastActive = norm(Hyprland.activeToplevel?.address);
        const p = {};
        for (const h of Hyprland.toplevels.values) {
            const ws = h.workspace;
            if (!ws || ws.name.startsWith("special:") || shown.indexOf(ws.id) === -1) continue;
            const addr = norm(h.address);
            p[addr] = ws.id;
            moveTo(addr, parkWs);
        }
        parked = p;
    }

    function unpark() {
        for (const addr in parked) moveTo(addr, String(parked[addr]));
        if (lastActive && parked[lastActive] !== undefined)
            Hyprland.dispatch('hl.dsp.focus({ window = "address:0x' + lastActive + '" })');
        parked = {};
        lastActive = "";
    }

    Connections {
        target: ShellState
        function onWidgetEditingChanged() {
            if (ShellState.widgetEditing) root.park();
            else root.unpark();
        }
    }

    // перезапуск оболочки посреди редактора — окна не должны потеряться
    Component.onCompleted: Qt.callLater(() => {
        if (ShellState.widgetEditing) return;
        const ws = Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1;
        for (const h of Hyprland.toplevels.values)
            if ((h.workspace?.name ?? "") === root.parkWs) root.moveTo(root.norm(h.address), String(ws));
    })
}
