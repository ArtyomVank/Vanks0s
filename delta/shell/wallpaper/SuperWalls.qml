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
        { id: "moon",      kind: "shader", title: "Луна",        frag: "moon" },
        { id: "earth",     kind: "shader", title: "Земля",       frag: "earth" },
        { id: "prism",     kind: "shader", title: "Стеклянные грани", frag: "prism" }
    ]
    // Живые обои (kind flow): оживают при входе — после запуска системы и после
    // каждой разблокировки — и замирают. Это не супер обои: камера к ним не
    // летит, а на экране блокировки видна только часть рисунка (lockPose).
    // frag — шейдер, group — семейство в списке; a…d — цвета, material — у волн.
    readonly property var groups: [
        { id: "circles", title: "Круги" },
        { id: "you",     title: "Material You" },
        { id: "glass",   title: "Жидкое стекло" },
        { id: "waves",   title: "Волны" },
        { id: "mountains", title: "Горы" },
        { id: "nothing", title: "Nothing" }
    ]
    readonly property var flows: [
        { id: "flow-blue",    kind: "flow", group: "circles", frag: "circles", title: "Синие",      a: "#0a1c4a", b: "#1f6dff", c: "#9fdcff", d: "#36c6ff" },
        { id: "flow-violet",  kind: "flow", group: "circles", frag: "circles", title: "Фиолетовые", a: "#1d0d47", b: "#7a3cff", c: "#e2b8ff", d: "#ff5fd2" },
        { id: "flow-coral",   kind: "flow", group: "circles", frag: "circles", title: "Коралловые", a: "#3d0d1c", b: "#f0523f", c: "#ffd2a8", d: "#ffb03a" },
        { id: "flow-green",   kind: "flow", group: "circles", frag: "circles", title: "Зелёные",    a: "#04302b", b: "#14b48a", c: "#c4ffd9", d: "#a6e84a" },
        { id: "flow-sunset",  kind: "flow", group: "circles", frag: "circles", title: "Закат",      a: "#24062e", b: "#ff4f7b", c: "#ffe0b5", d: "#ffa63d" },
        { id: "flow-aurora",  kind: "flow", group: "circles", frag: "circles", title: "Сияние",     a: "#031a2a", b: "#19c3a7", c: "#d8fff4", d: "#7a5cff" },
        { id: "you-lavender", kind: "flow", group: "you", frag: "you", title: "Лаванда", a: "#ece1ff", b: "#6f43c0", c: "#c9b3ff", d: "#ff8fb1" },
        { id: "you-mint",     kind: "flow", group: "you", frag: "you", title: "Мята",    a: "#d8f5e7", b: "#006c4f", c: "#8be0b8", d: "#ff9f7f" },
        { id: "you-peach",    kind: "flow", group: "you", frag: "you", title: "Персик",  a: "#ffe6d8", b: "#9c4323", c: "#ffb68f", d: "#56703f" },
        { id: "you-night",    kind: "flow", group: "you", frag: "you", title: "Ночь",    a: "#1c1b25", b: "#4b5bd6", c: "#bcc3ff", d: "#ffb4a9" },
        { id: "glass-lagoon", kind: "flow", group: "glass", frag: "glass", title: "Лагуна",  a: "#04161f", b: "#00a6c8", c: "#3b5bff", d: "#8cf2d0" },
        { id: "glass-dawn",   kind: "flow", group: "glass", frag: "glass", title: "Рассвет", a: "#1a0a1c", b: "#ff6a88", c: "#ffb35c", d: "#a77bff" },
        { id: "glass-night",  kind: "flow", group: "glass", frag: "glass", title: "Полночь", a: "#05060d", b: "#3a46a8", c: "#8a2fa0", d: "#1f8fa3" },
        { id: "waves-matte",  kind: "flow", group: "waves", frag: "waves", material: 0, title: "Матовые",    a: "#0b1630", b: "#2f6bd8", c: "#a8d4ff", d: "#7f5cf0" },
        { id: "waves-glass",  kind: "flow", group: "waves", frag: "waves", material: 1, title: "Стеклянные", a: "#071a24", b: "#19b3c9", c: "#e0fbff", d: "#6a7dff" },
        { id: "waves-metal",  kind: "flow", group: "waves", frag: "waves", material: 2, title: "Металл",     a: "#0d0d10", b: "#8a6b3d", c: "#fff1d0", d: "#4e5566" },
        { id: "waves-silk",   kind: "flow", group: "waves", frag: "waves", material: 2, title: "Шёлк",       a: "#26071a", b: "#c2275b", c: "#ffd1e0", d: "#ff8a3d" },
        { id: "mountains-dawn", kind: "flow", group: "mountains", frag: "mountains", title: "Рассвет", a: "#33427a", b: "#f4b28c", c: "#2c3150", d: "#ffe6d6" },
        { id: "mountains-day",  kind: "flow", group: "mountains", frag: "mountains", title: "День",    a: "#3f7fcf", b: "#cfe5f4", c: "#2e4a5f", d: "#ffffff" },
        { id: "mountains-dusk", kind: "flow", group: "mountains", frag: "mountains", title: "Закат",   a: "#26163f", b: "#ff8d5e", c: "#2a1b34", d: "#ffc6aa" },
        { id: "dots-black",   kind: "flow", group: "nothing", frag: "dots", title: "Чёрные", a: "#000000", b: "#f2f2f2", c: "#d71921", d: "#262626" },
        { id: "dots-white",   kind: "flow", group: "nothing", frag: "dots", title: "Белые",  a: "#f0f0f0", b: "#111111", c: "#d71921", d: "#d4d4d4" }
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
        || (currentKind === "flow" && onLock && !ShellState.desktopShown && animated)
    Connections {
        target: ShellState
        function onDesktopShownChanged() { root.flying = true; flightEnd.restart(); }
    }
    function groupTitle(id) { return groups.find(g => g.id === id)?.title ?? ""; }
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

    // --- живые обои: оживают при каждом входе на стол ---
    // На экране блокировки рисунок стоит в позе lockPose (видна только часть),
    // при входе — после запуска системы и после разблокировки — доигрывает до
    // конца; при блокировке быстро сворачивается обратно. До заставки запуска
    // кадр ждёт в самом начале (StartCover.qml). Время считается по кадрам: при
    // запуске система занята, и по часам анимация прошла бы, пока кадры не выходят.
    readonly property real introSeconds: 6
    readonly property real lockPose: 0.3
    // «Сразу на экране блокировки»: анимация входа играет целиком уже на
    // блокировке (при каждой блокировке — заново), разблокировка её не ждёт
    readonly property bool onLock: Settings.get("wallpaper.introOnLock", false) === true
    readonly property real lockTarget: onLock ? 1 : lockPose
    property real intro: Quickshell.env("DELTA_SESSION_START") === "1" ? 0 : 1
    property real introTarget: 1
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
            // назад — в восемь раз быстрее: блокировка не ждёт
            const step = dt / root.introSeconds * (root.introTarget < root.intro ? 8 : 1);
            root.intro = root.introTarget > root.intro ? Math.min(root.introTarget, root.intro + step)
                                                       : Math.max(root.introTarget, root.intro - step);
            if (root.intro === root.introTarget) running = false;
        }
    }
    function introTo(target) {
        introTarget = target;
        if (intro !== target) introTimer.restart();
    }
    // с начала: при выборе обоев и после заставки запуска
    function playIntro() {
        intro = 0;
        introTo(ShellState.desktopShown ? 1 : lockTarget);
    }
    Connections {
        target: ShellState
        function onDesktopShownChanged() {
            if (root.currentKind !== "flow") return;
            // на блокировке — с начала, чтобы её было видно целиком
            if (!ShellState.desktopShown && root.onLock) root.playIntro();
            else root.introTo(ShellState.desktopShown ? 1 : root.lockTarget);
        }
    }

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
