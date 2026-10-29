pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.common
import qs.docks.parts
import qs.minimize

// Док приложений одного монитора: закреплённые приложения, ярлыки и файлы,
// запущенные окна (точка-индикатор), кнопка «Добавить».
//
// Край, длина и автоскрытие — из docks.apps. Окно — полоса вдоль края без
// резервирования места (его держит Reserve), координаты = координаты экрана.
PanelWindow {
    id: win

    // верхний док на том же крае — встаём над ним
    property string topEdge: "top"
    property real topReach: 0

    readonly property var cfg: Settings.get("docks.apps", ({}))
    readonly property string edge: ["top", "bottom", "left", "right"].indexOf(cfg.edge) !== -1 ? cfg.edge : "bottom"
    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property string length: ["full", "tiles", "compact"].indexOf(cfg.length) !== -1 ? cfg.length : "compact"
    // автоскрытие: true — всегда, "smart" — только когда окно на видимом столе
    // этого монитора заходит на место дока (не задевает — док остаётся)
    readonly property bool smart: cfg.autohide === "smart"
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property bool hasWindows: smart && DockService.covered(screen?.name ?? "", openRect)
    readonly property bool autohide: cfg.autohide === true || (smart && hasWindows)
    readonly property bool magnify: cfg.magnify !== false
    readonly property bool showRunning: cfg.showRunning !== false

    readonly property int iconSize: 48
    readonly property real thick: 76
    readonly property real margin: 14 + (topEdge === edge ? topReach + 8 : 0)
    // длина края — по самому окну: ShellScreen не всегда успевает за сменой масштаба
    readonly property real screenAlong: vertical ? height : width
    readonly property real contentAlong: (vertical ? row.height : row.width) + 32
    readonly property real along: length === "full" ? screenAlong - 2 * 14 : contentAlong
    readonly property real reach: margin + thick
    readonly property int zone: cfg.autohide !== true && !smart && length !== "compact" ? Math.round(margin + thick) : 0

    readonly property bool popupHere: DockService.appMenu !== null && DockService.appMenu.screen === screen?.name
    readonly property bool hovered: island.hovered || hot.containsMouse || hint.containsMouse
    readonly property bool want: Settings.ready && !ShellState.widgetEditing && (!autohide || hovered || hold.running || popupHere
                                 || ShellState.docksForced || DockService.peek
                                 || Minimizer.animating)
    onHoveredChanged: if (!hovered) { hold.restart(); hoverIndex = -1; }
    Timer { id: hold; interval: 700 }
    readonly property bool hintVisible: autohide && island.stage === 0 && !ShellState.dockEditing

    WlrLayershell.namespace: "delta-dock"
    WlrLayershell.layer: WlrLayer.Top
    exclusionMode: ExclusionMode.Ignore
    anchors { top: edge !== "bottom"; bottom: edge !== "top"; left: edge !== "right"; right: edge !== "left" }
    // запас на увеличение значков, подскок и подсказку
    implicitHeight: vertical ? 0 : margin + thick + 84
    implicitWidth: vertical ? margin + thick + 84 : 0
    color: "transparent"
    mask: Region {
        item: island.body
        Region { item: hot }
        Region { item: hint }
    }

    readonly property point origin: Qt.point(edge === "right" ? (screen?.width ?? 0) - width : 0,
                                             edge === "bottom" ? (screen?.height ?? 0) - height : 0)
    function screenRect(item) {
        const p = item.mapToItem(null, 0, 0);
        return { x: origin.x + p.x, y: origin.y + p.y, w: item.width, h: item.height };
    }

    // --- что показывать ---
    function norm(p) {
        const key = DockService.pinKey(p);
        if (!key) return null;
        if (typeof p === "string") return { key: key, kind: "app", id: p, pinned: true };
        if (p.type === "cmd") return { key: key, kind: "cmd", name: p.name || p.command, command: p.command, pinned: true };
        return { key: key, kind: "path", name: p.name || p.path.replace(/\/+$/, "").split("/").pop(), path: p.path, pinned: true };
    }
    readonly property var pinned: DockService.pinnedRaw.map(norm).filter(x => x !== null)

    // ключи, по которым окно узнаёт закреплённое приложение
    function appKeys(id) {
        const out = [id.toLowerCase().replace(/\.desktop$/, "")];
        const e = DesktopEntries.byId(id) ?? DesktopEntries.heuristicLookup(id);
        if (e) {
            out.push(e.id.toLowerCase());
            if (e.startupClass) out.push(e.startupClass.toLowerCase());
        }
        return out;
    }
    // окна по ключу элемента + запущенные незакреплённые приложения
    readonly property var running: {
        DesktopEntries.applications.values;
        const byKey = {}, extra = [], extraIdx = {};
        const keys = pinned.filter(p => p.kind === "app").map(p => ({ key: p.key, ids: appKeys(p.id) }));
        for (const t of ToplevelManager.toplevels.values) {
            const app = (t.appId || "").toLowerCase();
            if (!app) continue;
            const look = DesktopEntries.heuristicLookup(t.appId);
            const lookId = look ? look.id.toLowerCase() : "";
            const hit = keys.find(k => k.ids.indexOf(app) !== -1 || (lookId && k.ids.indexOf(lookId) !== -1));
            const key = hit ? hit.key : "run:" + (lookId || app);
            if (!hit && extraIdx[key] === undefined) {
                extraIdx[key] = extra.length;
                extra.push({ key: key, kind: "run", appId: t.appId, pinned: false });
            }
            (byKey[key] = byKey[key] || []).push(t);
        }
        return { byKey: byKey, extra: extra };
    }
    readonly property var items: [{ key: "launcher", kind: "launcher" }, { key: "sep1", kind: "sep" }]
        .concat(pinned)
        .concat(showRunning ? running.extra : [])
        .concat([{ key: "sep2", kind: "sep" }, { key: "add", kind: "add" }])
    function windowsFor(key) { return running.byKey[key] || []; }

    property int hoverIndex: -1

    // --- действия ---
    function activate(item) {
        const d = item.modelData;
        if (d.kind === "launcher") { ShellState.toggleOverlay("launcher"); return; }
        if (d.kind === "add") { DockService.openAppMenu(screen, "add", null, screenRect(item)); return; }
        const wins = windowsFor(d.key);
        if (wins.length > 0) {
            // все окна свёрнуты — развернуть последнее
            const shown = wins.filter(t => !Minimizer.isMinimized(t));
            if (shown.length === 0) { Minimizer.restore(wins[wins.length - 1]); return; }
            // уже открыто — показать; повторное нажатие листает окна приложения,
            // а нажатие на единственное активное окно сворачивает его
            const i = shown.findIndex(t => t.activated);
            if (i !== -1 && shown.length === 1) { Minimizer.minimize(shown[0]); return; }
            shown[(i + 1) % shown.length].activate();
            return;
        }
        launch(item);
    }
    function launch(item) {
        const d = item.modelData;
        item.bounce();
        // «Настройки» Delta выходят каплей (window/SettingsGhost.qml) — из своего значка
        if (/^delta-settings(\.desktop)?$/.test(item.entry ? item.entry.id : (d.id || ""))) { ShellState.openSettings("", screenRect(item)); return; }
        if (item.entry) item.entry.execute();
        else if (d.kind === "cmd") Quickshell.execDetached(["sh", "-c", d.command]);
        else if (d.kind === "path") Quickshell.execDetached(["xdg-open", DockService.expandPath(d.path)]);
    }
    function requestMenu(item) {
        const d = item.modelData;
        if (d.kind === "launcher" || d.kind === "add" || d.kind === "sep") return;
        DockService.openAppMenu(screen, "context", Object.assign({}, d, { name: item.name, hasEntry: item.entry !== null }), screenRect(item));
    }
    // для меню: запустить ещё одно окно элемента key
    function launchKey(key) {
        for (let i = 0; i < rep.count; i++) {
            const it = rep.itemAt(i);
            if (it && it.modelData.key === key) { launch(it); return; }
        }
    }

    // --- геометрия для ShellState ---
    readonly property var openRect: {
        const sw = screen?.width ?? 0, sh = screen?.height ?? 0;
        if (vertical) return { x: edge === "left" ? margin : sw - margin - thick, y: (screenAlong - along) / 2, w: thick, h: along };
        return { x: (screenAlong - along) / 2, y: edge === "top" ? margin : sh - margin - thick, w: along, h: thick };
    }
    function publish() {
        if (!screen) return;
        const r = openRect;
        DockService.publishDock(screen.name, "apps", { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.w), h: Math.round(r.h), edge: edge, shown: want });
        iconTimer.restart();
    }
    onOpenRectChanged: publish()
    onWantChanged: publish()
    onItemsChanged: iconTimer.restart()
    Component.onCompleted: publish()

    // окно свернулось в значок — значок подпрыгивает, «поймав» его
    Connections {
        target: Minimizer
        function onLanded(appId) {
            if (!appId) return;
            for (let i = 0; i < rep.count; i++) {
                const it = rep.itemAt(i);
                if (it && it.windows.some(t => t.appId === appId)) { it.bounce(); return; }
            }
        }
    }

    // Положение значков в открытом доке (даже если он сейчас спрятан):
    // содержимое стоит по центру открытого прямоугольника.
    Timer {
        id: iconTimer
        interval: 400
        onTriggered: {
            if (!win.screen) return;
            const r = win.openRect, map = {};
            const ox = r.x + (r.w - row.width) / 2, oy = r.y + (r.h - row.height) / 2;
            for (let i = 0; i < rep.count; i++) {
                const it = rep.itemAt(i);
                if (!it || !it.visible || it.sep) continue;
                const geo = { screen: win.screen.name, x: Math.round(ox + it.x + (it.width - win.iconSize) / 2), y: Math.round(oy + it.y + (it.height - win.iconSize) / 2), size: win.iconSize };
                const keys = [];
                // кнопка «Приложения» — из неё вырастает окно приложений
                if (it.modelData.kind === "launcher") keys.push("@launcher");
                if (it.entry) { keys.push(it.entry.id); if (it.entry.startupClass) keys.push(it.entry.startupClass); }
                if (it.modelData.appId) keys.push(it.modelData.appId);
                for (const t of it.windows) if (t.appId) keys.push(t.appId);
                for (const k of keys) map[k] = geo;
            }
            DockService.publishIcons(win.screen.name, map);
        }
    }

    MouseArea {
        id: hot
        hoverEnabled: true
        readonly property int t: win.autohide ? 12 : 0
        x: win.edge === "right" ? win.width - t : 0
        y: win.edge === "bottom" ? win.height - t : 0
        width: win.vertical ? t : win.width
        height: win.vertical ? win.height : t
    }

    // видимая ручка свёрнутого дока
    Rectangle {
        id: hint
        visible: win.hintVisible
        opacity: visible ? 0.6 : 0
        width: win.vertical ? 4 : 52
        height: win.vertical ? 52 : 4
        radius: 2
        color: Theme.accent
        x: win.vertical ? (win.edge === "left" ? 2 : win.width - width - 2) : (win.width - width) / 2
        y: win.vertical ? (win.height - height) / 2 : (win.edge === "top" ? 2 : win.height - height - 2)
        Behavior on opacity { NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.OutCubic } }
        SequentialAnimation on scale {
            running: hint.visible
            loops: Animation.Infinite
            NumberAnimation { to: 0.72; duration: 1200; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 1200; easing.type: Easing.InOutSine }
        }
        MouseArea { id: hintArea; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true }
        readonly property alias containsMouse: hintArea.containsMouse
    }

    Island {
        id: island
        anchors.fill: parent
        edge: win.edge
        along: win.along
        thick: win.thick
        radiusOpen: 24
        margin: win.margin
        want: win.want
        tiles: win.length === "tiles"
        screenName: win.screen?.name ?? ""
        dockId: "apps"
        origin: win.origin

        Grid {
            id: row
            anchors.centerIn: parent
            columns: win.vertical ? 1 : Math.max(1, rep.count)
            rowSpacing: 10
            columnSpacing: 10

            Repeater {
                id: rep
                model: ScriptModel { values: win.items; objectProp: "key" }
                delegate: AppItem {
                    edge: win.edge
                    iconSize: win.iconSize
                    across: win.thick
                    tiles: win.length === "tiles"
                    magnify: win.magnify
                    hoverIndex: win.hoverIndex
                    windows: win.running.byKey[modelData.key] || []
                    screenName: win.screen?.name ?? ""
                    onHoverChanged2: (i, on) => { if (on) win.hoverIndex = i; else if (win.hoverIndex === i) win.hoverIndex = -1; }
                    onActivated: it => win.activate(it)
                    onMenuRequested: it => win.requestMenu(it)
                    onMiddleClicked: it => { if (modelData.kind !== "launcher" && modelData.kind !== "add") win.launch(it); }
                }
            }
        }
    }
}
