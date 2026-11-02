pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Супер обои: издалека на экране блокировки, при входе на стол камера летит к
// ним (SuperWall.qml). Настройка wallpaper.super — id из списка; wallpaper.path
// при этом указывает на готовый кадр: его берут темы, линза стекла и экран входа.
Singleton {
    id: root

    readonly property string dir: Qt.resolvedUrl("super/").toString().replace(/^file:\/\//, "")

    // kind: shader — считает видеокарта; photos, video — свои (delta-superwall)
    readonly property var builtin: [
        { id: "blackhole", kind: "shader", title: "Чёрная дыра", frag: "blackhole" },
        { id: "moon",      kind: "shader", title: "Луна",        frag: "moon" }
    ]
    // живые обои при запуске: один рисунок в четырёх цветах (A — глубина, B — полотна, C — блик)
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

    // --- время сцены: идёт на экране блокировки и в полёте, на столе кадр стоит ---
    property real time: 0
    property bool flying: false
    readonly property bool shaderOn: current !== null && current.kind === "shader"
    readonly property bool ticking: shaderOn && (!ShellState.desktopShown || flying)
    Connections {
        target: ShellState
        function onDesktopShownChanged() { root.flying = true; flightEnd.restart(); }
    }
    Timer { id: flightEnd; interval: 1900; onTriggered: root.flying = false }
    property real lastTick: 0
    Timer {
        interval: 16
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
    // до заставки кадр ждёт в самом начале; после запуска оболочки заново не играют
    property real intro: Quickshell.env("DELTA_SESSION_START") === "1" ? 0 : 1
    NumberAnimation {
        id: introAnim
        target: root
        property: "intro"
        from: 0
        to: 1
        duration: 6500
        easing.type: Easing.Linear
    }
    function playIntro() { introAnim.restart(); }

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
