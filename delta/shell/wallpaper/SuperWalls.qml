pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower
import qs.common

// Супер обои: издалека на экране блокировки, при входе на стол камера летит к
// ним (SuperWall.qml). Настройка wallpaper.super — id из списка; wallpaper.path
// при этом указывает на готовый кадр: его берут темы, линза стекла и экран входа.
Singleton {
    id: root

    readonly property string dir: Qt.resolvedUrl("super/").toString().replace(/^file:\/\//, "")

    // kind: shader — считает видеокарта; photos, video, live — свои (delta-superwall)
    readonly property var builtin: [
        { id: "blackhole", kind: "shader", title: "Чёрная дыра", frag: "blackhole" },
        { id: "moon",      kind: "shader", title: "Луна",        frag: "moon" }
    ]
    // живые обои при запуске: один рисунок в четырёх цветах (A — глубина, B — круги, C — блик)
    readonly property var flows: [
        { id: "flow-blue",   kind: "flow", title: "Синие",      a: "#0a1c4a", b: "#1f6dff", c: "#9fdcff" },
        { id: "flow-violet", kind: "flow", title: "Фиолетовые", a: "#1d0d47", b: "#7a3cff", c: "#e2b8ff" },
        { id: "flow-coral",  kind: "flow", title: "Коралловые", a: "#3d0d1c", b: "#f0523f", c: "#ffd2a8" },
        { id: "flow-green",  kind: "flow", title: "Зелёные",    a: "#04302b", b: "#14b48a", c: "#c4ffd9" }
    ]
    // свои: [{ id: "user:…", kind, title, far, near, clip }]
    property var user: []

    readonly property string currentId: Settings.get("wallpaper.super", "") || ""
    readonly property var current: {
        const id = currentId;
        if (!id) return null;
        return builtin.concat(flows, user).find(w => w.id === id) ?? null;
    }
    function still(w) { return w.near || dir + w.id + ".jpg"; }

    function apply(w) {
        Settings.set("wallpaper.video", false);
        Settings.set("wallpaper.super", w.id);
        Settings.set("wallpaper.path", still(w));
        if (w.kind === "flow") playIntro();
    }
    // обои сменили на обычные (WallStore.apply и «Убрать»)
    function clear() { if (currentId) Settings.set("wallpaper.super", ""); }

    // --- анимация на столе: включается в настройках, тратит видеокарту постоянно ---
    readonly property bool animated: Settings.get("wallpaper.superAnimated", false) === true
    // окно на весь экран закрывает обои, а на батарее (по настройке) их незачем крутить
    readonly property bool covered: Hyprland.focusedMonitor?.activeWorkspace?.hasFullscreen ?? false
    readonly property bool mayAnimate: animated && !covered
        && !(UPower.onBattery && Settings.get("wallpaper.pauseOnBattery", true) !== false)

    // --- время сцены: идёт на экране блокировки и в полёте, на столе — по настройке ---
    property real time: 0
    property bool flying: false
    readonly property string currentKind: current ? current.kind : ""
    readonly property bool ticking: (currentKind === "shader" && (!ShellState.desktopShown || flying))
        || ((currentKind === "shader" || currentKind === "flow") && mayAnimate)
    Connections {
        target: ShellState
        function onDesktopShownChanged() { root.flying = true; flightEnd.restart(); }
    }
    Timer { id: flightEnd; interval: 1900; onTriggered: root.flying = false }
    property real lastTick: 0
    Timer {
        // на столе хватает 30 кадров: движение медленное, видеокарте легче
        interval: ShellState.desktopShown && !root.flying ? 33 : 16
        repeat: true
        running: root.ticking
        onRunningChanged: root.lastTick = Date.now()
        onTriggered: {
            const now = Date.now();
            root.time = (root.time + Math.min(0.1, (now - root.lastTick) / 1000)) % 3600;
            root.lastTick = now;
        }
    }

    // --- живые обои: играют один раз при запуске системы ---
    // До заставки кадр ждёт в самом начале, после запуска оболочки заново не играют.
    // Время считается по кадрам: при запуске система занята, и по часам анимация
    // успела бы пройти, пока кадры не выходят
    readonly property real introSeconds: 7
    property real intro: Quickshell.env("DELTA_SESSION_START") === "1" ? 0 : 1
    property real introLast: 0
    Timer {
        id: introTimer
        interval: 16
        repeat: true
        onRunningChanged: root.introLast = Date.now()
        onTriggered: {
            const now = Date.now();
            const dt = Math.min(1 / 30, (now - root.introLast) / 1000);
            root.introLast = now;
            root.intro = Math.min(1, root.intro + dt / root.introSeconds);
            if (root.intro >= 1) running = false;
        }
    }
    function playIntro() { intro = 0; introTimer.restart(); }

    // --- свои супер обои ---
    function reload() { listProc.running = true; }
    Process {
        id: listProc
        running: true
        command: ["delta-superwall", "list"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.user = JSON.parse(text); } catch (e) {} }
        }
    }
    function removeUser(w) {
        if (currentId === w.id) { clear(); Settings.set("wallpaper.path", ""); }
        removeProc.command = ["delta-superwall", "remove", w.id.replace(/^user:/, "")];
        removeProc.running = true;
    }
    Process { id: removeProc; onExited: root.reload() }
}
