pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.common

// «Желе» при перетаскивании окна: точка, за которую держат, идёт за курсором,
// а остальное отстаёт и догоняет с покачиванием — низ окна тянется следом,
// как у Wobbly Windows в GNOME. Hyprland окна гнуть не умеет, поэтому на время
// перетаскивания само окно прячется (прозрачность 0), а поверх рисуется его
// живая копия (ScreencopyView) на сетке из шейдера shaders/jelly.vert.
//
// Отстают пять «колец» по расстоянию от точки захвата: у каждого своя пружина,
// дальние мягче. Сила — «Настройки → Окна → Желе» (windows.jelly: 0…1.7).
// Отпустили у края (Snap) — копия сразу уступает место окну, иначе ждёт,
// пока покачивание уляжется.
Scope {
    id: root

    readonly property real strength: Math.max(0, Math.min(1.7, Number(Settings.get("windows.jelly", 0.5)) || 0))
    readonly property bool enabled: strength > 0 && Settings.get("windows.animations", true) !== false
    readonly property int rounding: Math.max(0, Math.min(40, Number(Settings.get("windows.rounding", 16)) || 0))
    readonly property int border: Math.max(0, Math.min(10, Number(Settings.get("windows.border", 2)) || 0))

    property bool active: false        // копия на экране (окно, может быть, ещё видно)
    property bool hidden: false        // окно спрятано под копией
    property bool releasing: false     // отпустили — ждём, пока уляжется
    property bool capturing: false     // живой захват окна включён
    property string addr: ""
    property var toplevel: null
    property string monitorName: ""
    property rect target               // где окно на самом деле
    property point grab
    property var rings: []             // кольца 1…5: { x, y, vx, vy } в глобальных координатах

    property vector4d o12: Qt.vector4d(0, 0, 0, 0)
    property vector4d o34: Qt.vector4d(0, 0, 0, 0)
    property vector4d o5: Qt.vector4d(0, 0, 0, 0)

    function norm(a) { return String(a || "").replace(/^0x/, ""); }
    // прозрачное окно Hyprland всё равно размывает под собой фон и рисует
    // тень — они вылезали бы из-под изогнутой копии, поэтому их тоже снимаем
    function setOpacity(on) {
        if (!addr) return;
        const sel = 'window = "address:0x' + addr + '"';
        const prop = (name, value) => Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "' + name + '", value = "' + value + '", ' + sel + ' })');
        prop("opacity", on ? 1 : 0);
        prop("opacity_override", on ? 0 : 1);
        prop("no_blur", on ? 0 : 1);
        prop("no_shadow", on ? 0 : 1);
    }

    Connections {
        target: DragState
        function onBegan() {
            if (!root.enabled) return;
            // прежняя копия ещё не ушла — окно возвращаем сразу
            handBack.stop();
            if (root.hidden) { root.setOpacity(true); root.hidden = false; }
            root.active = false;
            const h = Hyprland.toplevels.values.find(t => root.norm(t.address) === DragState.address);
            if (!h || !h.wayland) return;
            root.addr = DragState.address;
            root.toplevel = h;
            root.monitorName = DragState.monitor;
            root.target = DragState.win;
            root.grab = DragState.grab;
            const r = [];
            for (let i = 0; i < 5; i++) r.push({ x: DragState.win.x, y: DragState.win.y, vx: 0, vy: 0 });
            root.rings = r;
            root.releasing = false;
            root.active = true;
            root.capturing = true;
        }
        function onMoved() {
            if (!root.active || DragState.address !== root.addr) return;
            // окно поменяло размер (прилипшее вернуло прежний) — захват
            // Quickshell на этом обрывается: показываем окно и снимаем заново
            if (DragState.win.width !== root.target.width || DragState.win.height !== root.target.height) {
                if (root.hidden) { root.setOpacity(true); root.hidden = false; }
                root.capturing = false;
                Qt.callLater(() => root.capturing = root.active);
            }
            root.target = DragState.win;
            if (DragState.monitor && DragState.monitor !== root.monitorName) root.monitorName = DragState.monitor;
        }
        function onEnded(snapped) {
            if (!root.active) return;
            // у края окно само переедет в свою зону — копия там не нужна
            if (snapped || !root.hidden) root.stopNow(snapped);
            else { root.releasing = true; settleLimit.restart(); }
        }
    }

    // пружины колец: дальние мягче и сильнее раскачиваются
    FrameAnimation {
        running: root.active
        onTriggered: {
            const dt = Math.min(1 / 30, frameTime || 1 / 60);
            const s = root.strength;
            const kf = 1.35 - 0.4 * s;
            const zeta = 0.72 - 0.17 * s;
            const t = root.target;
            const lim = 0.32 * Math.hypot(t.width, t.height);
            let calm = true;
            const out = [];
            for (let i = 0; i < 5; i++) {
                const p = root.rings[i];
                const r = (i + 1) / 5;
                const k = (560 - 430 * r) * kf;
                const c = 2 * Math.sqrt(k) * zeta;
                // два полушага — устойчиво и при просевшей частоте кадров
                for (let n = 0; n < 2; n++) {
                    const h = dt / 2;
                    p.vx += (k * (t.x - p.x) - c * p.vx) * h;
                    p.vy += (k * (t.y - p.y) - c * p.vy) * h;
                    p.x += p.vx * h;
                    p.y += p.vy * h;
                }
                let ox = p.x - t.x, oy = p.y - t.y;
                const len = Math.hypot(ox, oy);
                if (len > lim) { ox *= lim / len; oy *= lim / len; p.x = t.x + ox; p.y = t.y + oy; }
                if (len > 0.4 || Math.abs(p.vx) + Math.abs(p.vy) > 8) calm = false;
                out.push(ox, oy);
            }
            root.o12 = Qt.vector4d(out[0], out[1], out[2], out[3]);
            root.o34 = Qt.vector4d(out[4], out[5], out[6], out[7]);
            root.o5 = Qt.vector4d(out[8], out[9], 0, 0);
            if (root.releasing && calm) root.stopNow();
        }
    }
    // покачивание не улеглось за секунду (очень сильное «желе») — всё равно отдаём окно
    Timer { id: settleLimit; interval: 1100; onTriggered: if (root.releasing) root.stopNow() }

    // окно возвращается, и только через пару кадров пропадает копия — без мигания
    // Hyprland возвращает прозрачность плавно — на месте копия держится, пока
    // окно не проявится; у края окно уезжает в зону, там хватит пары кадров
    property int handFrames: 3
    function stopNow(snapped) {
        settleLimit.stop();
        releasing = false;
        handFrames = snapped ? 3 : 14;
        if (hidden) { setOpacity(true); hidden = false; }
        handBack.restart();
    }
    FrameAnimation {
        id: handBack
        onTriggered: {
            if (currentFrame < root.handFrames) return;
            stop();
            root.active = false;
            root.capturing = false;
            root.toplevel = null;
            root.addr = "";
        }
    }

    readonly property var targetScreen: Quickshell.screens.find(s => s.name === root.monitorName) ?? null

    PanelWindow {
        id: win
        screen: root.targetScreen
        visible: root.active && root.targetScreen !== null
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "delta-jelly"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        mask: Region {}

        ScreencopyView {
            id: cap
            width: root.target.width
            height: root.target.height
            captureSource: root.active && root.capturing ? (root.toplevel?.wayland ?? null) : null
            live: true
            // первый кадр копии на месте — теперь можно прятать окно
            onHasContentChanged: if (hasContent && root.active && !root.hidden && DragState.dragging) {
                root.setOpacity(false);
                root.hidden = true;
            }
        }
        ShaderEffectSource {
            id: tex
            sourceItem: cap
            hideSource: true
            live: true
            visible: false
        }

        ShaderEffect {
            anchors.fill: parent
            visible: cap.hasContent && root.capturing
            readonly property real sx: win.screen?.x ?? 0
            readonly property real sy: win.screen?.y ?? 0
            property vector4d rect: Qt.vector4d(root.target.x - sx, root.target.y - sy, root.target.width, root.target.height)
            property point grab: root.grab
            property real reach: {
                const g = root.grab, w = root.target.width, h = root.target.height;
                return Math.max(Math.hypot(g.x, g.y), Math.hypot(w - g.x, g.y), Math.hypot(g.x, h - g.y), Math.hypot(w - g.x, h - g.y));
            }
            property real radius: root.rounding
            property real border: root.border
            property color borderColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.93)
            property vector4d o12: root.o12
            property vector4d o34: root.o34
            property vector4d o5: root.o5
            property variant source: tex
            mesh: GridMesh { resolution: Qt.size(24, 24) }
            vertexShader: Qt.resolvedUrl("shaders/jelly.vert.qsb")
            fragmentShader: Qt.resolvedUrl("shaders/jelly.frag.qsb")
        }
    }
}
