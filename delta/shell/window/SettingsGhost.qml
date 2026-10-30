pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.common
import qs.docks.parts

// «Настройки» выходят из верхнего дока и уходят в него обратно.
//
// Настройки — отдельный процесс (delta-settings), его окно рисует Hyprland, и
// оболочка не может его анимировать. Поэтому анимацию играет «призрак»: слой
// поверх окон, в котором капля из дока растекается в стеклянную карточку
// ровно там, где откроется окно (правило Hyprland: 1100×720 по центру, без
// своих анимаций — no_anim). Пока капля растекается, процесс успевает
// запуститься; когда окно появилось и карточка встала — призрак гаснет и
// открывает настоящее окно. При закрытии окна — обратный путь в док.
//
//   ShellState.openSettings(раздел, откуда)   откуда — прямоугольник на экране или null (верхний док)
Scope {
    id: root

    readonly property bool animate: Settings.get("windows.animations", true) !== false
    readonly property var wins: ToplevelManager.toplevels.values.filter(t => t.appId === "delta-settings")
    readonly property bool running: wins.length > 0

    // "" — ничего, "open" — капля растекается и ждёт окно, "reveal" — гаснет над окном, "close" — обратно в док
    property string phase: ""
    property bool blobOpen: false
    property bool windowSeen: false
    property ShellScreen screen: null
    property point source: Qt.point(0, 0)
    property rect card: Qt.rect(0, 0, 0, 0)
    // откуда открыли (модуль V) — туда же окно и вернётся
    property var lastFrom: null

    Connections {
        target: ShellState
        function onSettingsRequested(section, from) { root.request(section, from); }
    }

    function focusedScreen() {
        const name = Hyprland.focusedMonitor?.name ?? "";
        return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0] ?? null;
    }
    // точка на поверхности верхнего дока, обращённой к экрану
    // (напротив модуля V: край острова там вздувается каплей)
    function dockSource(scr, from) {
        const dock = (ShellState.dockGeometry[scr.name] || {}).top || null;
        const cx = from ? from.x + from.w / 2 : dock ? dock.x + dock.w / 2 : scr.width / 2;
        const cy = from ? from.y + from.h / 2 : dock ? dock.y + dock.h / 2 : 0;
        if (!dock) return Qt.point(cx, 0);
        switch (dock.edge) {
        case "bottom": return Qt.point(cx, dock.y);
        case "left": return Qt.point(dock.x + dock.w, cy);
        case "right": return Qt.point(dock.x, cy);
        default: return Qt.point(cx, dock.y + dock.h);
        }
    }
    // где откроется окно (правило delta-settings в hyprland.lua)
    function centerCard(scr) {
        const w = Math.min(1100, scr.width - 40), h = Math.min(720, scr.height - 40);
        return Qt.rect(Math.round((scr.width - w) / 2), Math.round((scr.height - h) / 2), w, h);
    }

    function request(section, from) {
        const args = ["delta-settings"].concat(section ? [section] : []);
        const scr = focusedScreen();
        // уже открыто (только сменить раздел и поднять) или анимации выключены
        if (running || !animate || !scr || phase !== "") { Quickshell.execDetached(args); return; }
        screen = scr;
        lastFrom = from;
        source = dockSource(scr, from);
        card = centerCard(scr);
        windowSeen = false;
        blobOpen = true;
        phase = "open";
        Quickshell.execDetached(args);
        giveUp.restart();
    }

    // окно так и не появилось — капля возвращается в док
    Timer {
        id: giveUp
        interval: 6000
        onTriggered: if (root.phase === "open") { root.blobOpen = false; }
    }

    // --- окно появилось / закрылось ---
    onRunningChanged: {
        if (running) {
            if (phase === "open") { windowSeen = true; tryReveal(); }
            return;
        }
        // окно закрыли — капля уходит из его места обратно в док
        if (!animate || phase !== "") return;
        const r = lastRect;
        const scr = r ? Quickshell.screens.find(s => s.name === r.screen) : focusedScreen();
        if (!scr) return;
        screen = scr;
        card = r ? Qt.rect(r.x, r.y, r.w, r.h) : centerCard(scr);
        source = dockSource(scr, lastFrom);
        blobOpen = true;
        phase = "close";
    }
    function tryReveal() {
        if (phase === "open" && windowSeen && ghost.item && ghost.item.settled) phase = "reveal";
    }

    // --- где сейчас окно: для обратной анимации -------------------------------
    // Геометрию знает только Hyprland; пока окно открыто, изредка обновляем.
    property var lastRect: null
    Timer {
        interval: 700
        repeat: true
        running: root.running
        triggeredOnStart: true
        onTriggered: {
            Hyprland.refreshToplevels();
            const h = Hyprland.toplevels.values.find(t => t.wayland && t.wayland.appId === "delta-settings");
            const o = h?.lastIpcObject;
            // at/size — списки Qt, не массивы JS: Array.isArray для них false
            if (!o || !(o.at?.length >= 2) || !(o.size?.length >= 2)) return;
            if ((o.workspace?.name ?? "").startsWith("special:")) return;
            const mon = Hyprland.monitors.values.find(m => m.id === o.monitor);
            const scr = mon ? Quickshell.screens.find(s => s.name === mon.name) : null;
            if (!scr) return;
            root.lastRect = { screen: scr.name, x: o.at[0] - scr.x, y: o.at[1] - scr.y, w: o.size[0], h: o.size[1] };
        }
    }

    // --- слой призрака ---------------------------------------------------------
    LazyLoader {
        id: ghost
        active: root.phase !== "" && root.screen !== null

        PanelWindow {
            id: win
            screen: root.screen
            readonly property bool settled: blob.settled
            onSettledChanged: root.tryReveal()

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "delta-ghost"
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            // клики проходят насквозь — к настоящему окну
            mask: Region {}

            Component.onCompleted: {
                if (root.phase !== "close") return;
                // закрытие начинается с карточки на месте окна
                blob.snapOpen();
                Qt.callLater(() => { root.blobOpen = false; });
            }

            Item {
                id: fade
                anchors.fill: parent
                opacity: root.phase === "reveal" ? 0 : 1
                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.OutCubic
                        onRunningChanged: if (!running && fade.opacity === 0) root.phase = ""
                    }
                }

                Blob {
                    id: blob
                    x: root.card.x
                    y: root.card.y
                    width: root.card.width
                    height: root.card.height
                    radiusOpen: Settings.get("windows.rounding", 16)
                    strong: true
                    // капля тянет за собой модуль V верхнего дока
                    // (открыли не из V — край верхнего дока вздувается посередине)
                    pullKey: root.screen ? root.screen.name + "/top:" + (root.lastFrom ? "launcher" : "@") : ""
                    open: root.blobOpen
                    srcX: root.source.x - x
                    srcY: root.source.y - y
                    onClosed: root.phase = ""

                    // набросок окна «Настроек»: боковая панель слева
                    Rectangle {
                        width: Math.min(260, parent.width * 0.3)
                        height: parent.height
                        color: Theme.soft
                    }
                }
            }
        }
    }
}
