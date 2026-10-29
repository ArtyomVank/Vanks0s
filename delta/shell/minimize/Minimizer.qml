pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.common
import qs.display.parts

// Сворачивание окон в значок дока.
//
// В Hyprland нет свёрнутых окон, поэтому свёрнутое окно живёт на скрытом
// рабочем столе special:minimized. Анимацию «джинн» рисует Genie (по окну на
// монитор): снимок окна берётся, пока окно ещё видно, и хранится до
// разворачивания — со скрытого стола снимок уже не получить.
//
//   Minimizer.minimizeActive()      Super+M
//   Minimizer.minimize(окно)        окно — Toplevel (Quickshell.Wayland) или HyprlandToplevel
//   Minimizer.restore(окно)         на текущий рабочий стол, с фокусом
//   Minimizer.isMinimized(окно)
//
// Кнопка «свернуть» в заголовке программы и активация свёрнутого окна извне
// (уведомление, Alt+Tab) тоже приходят сюда — через события Hyprland.
Singleton {
    id: root

    readonly property string workspace: "special:minimized"
    readonly property bool animate: Settings.get("windows.genie", true) !== false
                                    && Settings.get("windows.animations", true) !== false

    // адрес окна (без 0x) → { url, grab, rect, screen }; grab держит снимок в памяти
    property var shots: ({})
    // имя монитора → Genie
    property var genies: ({})
    // адреса, которые сейчас в анимации, — чтобы двойное нажатие не запускало её дважды
    property var busy: ({})
    // док показывается, пока окно летит в значок или из него
    readonly property bool animating: Object.keys(busy).length > 0

    // окно долетело до значка — док подбрасывает значок (appId окна)
    signal landed(string appId)

    function norm(a) { return String(a || "").replace(/^0x/, ""); }

    function hyprFor(t) {
        if (!t) return null;
        if (t.address !== undefined) return t;
        return Hyprland.toplevels.values.find(h => h.wayland === t) ?? null;
    }
    function byAddress(a) {
        a = norm(a);
        return Hyprland.toplevels.values.find(h => norm(h.address) === a) ?? null;
    }
    function isMinimized(t) {
        const h = hyprFor(t);
        return (h?.workspace?.name ?? "") === workspace;
    }

    function minimizeActive() {
        const h = Hyprland.activeToplevel;
        if (h && !isMinimized(h)) minimize(h);
    }
    function toggle(t) {
        if (isMinimized(t)) restore(t); else minimize(t);
    }

    function moveTo(addr, ws) {
        Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + ws + '", follow = false, window = "address:0x' + addr + '" })');
    }

    // --- свернуть ---------------------------------------------------------

    function minimize(t) {
        const h = hyprFor(t);
        if (!h || isMinimized(h)) return;
        const addr = norm(h.address);
        if (busy[addr]) return;
        Sounds.play("swoosh", 150);
        if (!animate || !h.wayland) { moveTo(addr, workspace); return; }

        mark(addr, true);
        // геометрию окна знает только hyprctl: at/size в глобальных координатах
        run(["hyprctl", "-j", "clients"], (code, out) => {
            let c = null;
            try { c = JSON.parse(out).find(x => norm(x.address) === addr); } catch (e) {}
            const mon = c ? Hyprland.monitors.values.find(m => m.id === c.monitor) : null;
            const screen = mon ? Quickshell.screens.find(s => s.name === mon.name) : null;
            const genie = screen ? genies[screen.name] : null;
            if (!c || !genie || c.fullscreen >= 2) {
                if (!genie) console.warn("[delta] сворачивание: нет слоя анимации для монитора " + (mon?.name ?? "?"));
                // на весь экран (2; 1 — развёрнуто) «джинн» выглядит странно — просто убираем
                root.moveTo(addr, root.workspace);
                root.mark(addr, false);
                return;
            }
            const rect = { x: c.at[0] - screen.x, y: c.at[1] - screen.y, w: c.size[0], h: c.size[1] };
            genie.capture(h.wayland, rect, grab => {
                if (grab) root.keepShot(addr, { url: grab.url, grab: grab, rect: rect, screen: screen.name });
                const target = root.iconRect(h, screen);
                if (!grab) {
                    console.warn("[delta] сворачивание: не удалось снять окно " + addr + " — без анимации");
                    root.moveTo(addr, root.workspace);
                    root.mark(addr, false);
                    return;
                }
                genie.play(grab.url, rect, target.rect, target.edge, false,
                    // снимок уже поверх окна — окно можно убирать
                    () => root.moveTo(addr, root.workspace),
                    () => { root.mark(addr, false); root.landed(h.wayland?.appId ?? ""); });
            });
        });
    }

    // --- развернуть -------------------------------------------------------

    function restore(t) {
        const h = hyprFor(t);
        if (!h || !isMinimized(h)) return;
        const addr = norm(h.address);
        if (busy[addr]) return;
        const ws = Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1;
        const back = () => {
            root.moveTo(addr, String(ws));
            Hyprland.dispatch('hl.dsp.focus({ window = "address:0x' + addr + '" })');
        };

        const shot = shots[addr];
        const screenName = Hyprland.focusedMonitor?.name ?? "";
        const screen = Quickshell.screens.find(s => s.name === screenName) ?? null;
        const genie = screen ? genies[screen.name] : null;
        if (!animate || !shot || !genie) { back(); dropShot(addr); return; }

        mark(addr, true);
        const target = iconRect(h, screen);
        genie.play(shot.url, shot.rect, target.rect, target.edge, true,
            back,
            () => { root.mark(addr, false); root.dropShot(addr); });
    }

    // --- значок в доке ------------------------------------------------------

    // Куда лететь: значок приложения в доке этого монитора, иначе середина дока.
    function iconRect(h, screen) {
        const dock = (ShellState.dockGeometry[screen.name] || {}).apps || null;
        const edge = dock ? ["bottom", "top", "left", "right"].indexOf(dock.edge) : 0;
        const app = h.wayland?.appId ?? "";
        const icons = ShellState.appIconGeometry;
        let g = null;
        for (const k of [app, app.toLowerCase(), app.replace(/\.desktop$/, "")]) {
            const v = icons[k];
            if (v && v.screen === screen.name) { g = v; break; }
        }
        if (g) return { rect: { x: g.x, y: g.y, w: g.size, h: g.size }, edge: Math.max(0, edge) };
        if (dock) return { rect: { x: dock.x + dock.w / 2 - 24, y: dock.y + dock.h / 2 - 24, w: 48, h: 48 }, edge: Math.max(0, edge) };
        return { rect: { x: screen.width / 2 - 24, y: screen.height - 64, w: 48, h: 48 }, edge: 0 };
    }

    // --- служебное ----------------------------------------------------------

    function mark(addr, on) {
        const b = Object.assign({}, busy);
        if (on) b[addr] = Date.now(); else delete b[addr];
        busy = b;
    }

    // Сторож: анимация не длится дольше пары секунд. Если колбэк потерялся
    // (окно закрылось посреди анимации, hyprctl не ответил), отметку снимаем
    // сами — иначе нижний док так и висел бы открытым.
    Timer {
        interval: 1000
        repeat: true
        running: root.animating
        onTriggered: {
            const now = Date.now();
            for (const a in root.busy)
                if (now - root.busy[a] > 3000) root.mark(a, false);
        }
    }
    function keepShot(addr, s) {
        dropShot(addr);
        const n = Object.assign({}, shots);
        n[addr] = s;
        shots = n;
    }
    function dropShot(addr) {
        if (!shots[addr]) return;
        const n = Object.assign({}, shots);
        delete n[addr];
        shots = n;
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            switch (event.name) {
            case "minimized": {
                // кнопка «свернуть» программы: minimized>>адрес,1 (0 — развернуть)
                const [a, on] = event.data.split(",");
                const h = root.byAddress(a);
                if (!h) return;
                if (on === "1") root.minimize(h); else root.restore(h);
                break;
            }
            case "activespecial": {
                // Свёрнутое окно активировали извне — Hyprland раскрыл бы скрытый
                // стол поверх. Закрываем его и разворачиваем окно по-нашему.
                if (!event.data.startsWith(root.workspace + ",")) return;
                Hyprland.dispatch('hl.dsp.workspace.toggle_special("minimized")');
                const h = Hyprland.activeToplevel;
                if (h && root.isMinimized(h)) Qt.callLater(() => root.restore(h));
                break;
            }
            case "closewindow":
                root.dropShot(root.norm(event.data));
                break;
            }
        }
    }

    Component { id: runComp; Run {} }
    function run(argv, done) { runComp.createObject(root, { argv: argv, done: done }); }
}
