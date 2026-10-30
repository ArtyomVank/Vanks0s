pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.common

// Общее для доков всех мониторов: каталог модулей верхнего дока,
// состояние музыки (режим «плеер-пилюля»), всплывающие окна дока
// приложений, публикация геометрии в ShellState и IPC `docks`.
Singleton {
    id: root

    // --- каталог модулей верхнего дока ---
    readonly property var catalog: ({
        launcher:      { name: "Приложения",     span: 1, icon: "apps" },
        workspaces:    { name: "Рабочие столы",  span: 3, icon: "windows" },
        lang:          { name: "Язык",           span: 1, icon: "keyboard" },
        wifi:          { name: "Сеть",           span: 1, icon: "wifi" },
        bluetooth:     { name: "Bluetooth",      span: 1, icon: "bluetooth" },
        sound:         { name: "Звук",           span: 1, icon: "volume" },
        battery:       { name: "Батарея",        span: 1, icon: "battery" },
        power:         { name: "Питание",        span: 1, icon: "power" },
        weather:       { name: "Погода",         span: 2, icon: "cloud-sun" },
        pc:            { name: "Показатели ПК",  span: 3, icon: "cpu" },
        notifications: { name: "Уведомления",    span: 1, icon: "bell" },
        calendar:      { name: "Календарь",      span: 2, icon: "calendar" }
    })
    // Музыки среди модулей нет: когда она играет, весь верхний док становится
    // пилюлей плеера (mediaPill), а её меню — menus/MediaMenu.qml.
    readonly property var order: ["launcher", "workspaces", "calendar", "weather", "pc", "lang",
                                  "bluetooth", "wifi", "sound", "battery", "notifications", "power"]
    readonly property int cells: 16

    function cap(id) { return id.charAt(0).toUpperCase() + id.slice(1); }

    // Модули из настроек: только известные, в пределах сетки, без наложений.
    function sanitize(list) {
        const out = [], used = {};
        for (const m of (Array.isArray(list) ? list : [])) {
            if (!m || !catalog[m.id] || out.some(o => o.id === m.id)) continue;
            const span = Math.max(1, Math.min(cells, Math.round(m.span || catalog[m.id].span)));
            const cell = Math.max(0, Math.min(cells - span, Math.round(m.cell || 0)));
            let free = true;
            for (let c = cell; c < cell + span; c++) if (used[c]) free = false;
            if (!free) continue;
            for (let c = cell; c < cell + span; c++) used[c] = true;
            out.push({ id: m.id, cell: cell, span: span });
        }
        return out;
    }

    readonly property var modules: sanitize(Settings.get("docks.top.modules", []))

    function moduleAt(list, cell, except) {
        return list.find(m => m.id !== except && cell >= m.cell && cell < m.cell + m.span);
    }
    function valid(list) {
        const used = {};
        for (const m of list) {
            if (m.cell < 0 || m.cell + m.span > cells) return false;
            for (let c = m.cell; c < m.cell + m.span; c++) { if (used[c]) return false; used[c] = true; }
        }
        return true;
    }
    // Куда встанут модули, если перенести id в ячейку target: null — нельзя.
    // Занятое место меняется местами с переносимым модулем.
    function planMove(id, target) {
        const list = modules.map(m => Object.assign({}, m));
        const me = list.find(m => m.id === id);
        if (!me) return null;
        const from = me.cell;
        me.cell = Math.max(0, Math.min(cells - me.span, target));
        if (valid(list)) return list;
        const other = moduleAt(list, me.cell, id);
        if (other) {
            other.cell = from;
            if (other.cell + other.span > cells) other.cell = cells - other.span;
            if (valid(list)) return list;
        }
        return null;
    }
    function moveModule(id, target) {
        const plan = planMove(id, target);
        if (plan) Settings.set("docks.top.modules", plan);
        return plan !== null;
    }
    // Ширина модуля в ячейках: тянем за правый (нижний) край в режиме правки.
    function planSpan(id, span) {
        const list = modules.map(m => Object.assign({}, m));
        const me = list.find(m => m.id === id);
        if (!me) return null;
        me.span = Math.max(1, Math.min(cells - me.cell, Math.round(span)));
        if (!valid(list)) return null;
        return list;
    }
    function setSpan(id, span) {
        const plan = planSpan(id, span);
        if (plan) Settings.set("docks.top.modules", plan);
        return plan !== null;
    }
    function spanOf(id) { return modules.find(m => m.id === id)?.span ?? 1; }
    function removeModule(id) {
        Settings.set("docks.top.modules", modules.filter(m => m.id !== id));
        if (ShellState.menu === id) ShellState.closeMenu();
    }
    // Новый модуль — в первую свободную подходящую ячейку справа.
    function addModule(id) {
        if (!catalog[id] || modules.some(m => m.id === id)) return false;
        const span = catalog[id].span;
        for (let c = cells - span; c >= 0; c--) {
            let free = true;
            for (let k = c; k < c + span; k++) if (moduleAt(modules, k)) free = false;
            if (free) {
                Settings.set("docks.top.modules", modules.concat({ id: id, cell: c, span: span }));
                return true;
            }
        }
        // целиком не влезает — пробуем ширину в одну ячейку
        for (let c = cells - 1; c >= 0; c--)
            if (!moduleAt(modules, c)) {
                Settings.set("docks.top.modules", modules.concat({ id: id, cell: c, span: 1 }));
                return true;
            }
        return false;
    }
    function resetModules() {
        Settings.set("docks.top.modules", [
            { id: "launcher", cell: 0, span: 1 }, { id: "workspaces", cell: 1, span: 3 },
            { id: "calendar", cell: 4, span: 2 }, { id: "weather", cell: 6, span: 2 },
            { id: "notifications", cell: 10, span: 1 }, { id: "lang", cell: 11, span: 1 },
            { id: "wifi", cell: 12, span: 1 }, { id: "sound", cell: 13, span: 1 },
            { id: "battery", cell: 14, span: 1 }, { id: "power", cell: 15, span: 1 }
        ]);
    }

    // --- музыка: верхний док становится пилюлей с обложкой ---
    // fake — подстановка для проверки без плеера: { title, artist, art, playing }
    property var fake: null
    readonly property var players: Mpris.players.values
    property MprisPlayer stickyPlayer: null
    readonly property MprisPlayer player: {
        const list = players;
        const playing = list.find(p => p.isPlaying);
        if (playing) return playing;
        if (stickyPlayer && list.indexOf(stickyPlayer) !== -1) return stickyPlayer;
        return list[0] ?? null;
    }
    onPlayerChanged: if (player) stickyPlayer = player

    // Звук без MPRIS: игры, видеоплееры без плагина, часть браузеров. Их видно
    // как потоки воспроизведения PipeWire — по ним остров тоже появляется.
    // Свои звуки оболочки (pw-play) и записи (микрофон) не считаем.
    readonly property var playback: Pipewire.nodes.values.filter(n => n.isStream && !n.isSink && n.audio)
    // свойства узла (имя приложения, название) приходят, только пока узел отслеживается
    PwObjectTracker { objects: root.playback }
    // только воспроизведение (Stream/Output/Audio): захват — cava, запись, звонки
    // с микрофона — тоже «поток не-приёмник», но острову не нужен
    readonly property var streams: playback.filter(n => n.properties
        && n.properties["media.class"] === "Stream/Output/Audio"
        && ["pw-play", "paplay", "cava"].indexOf(n.properties["application.process.binary"] || "") === -1
        && ["pw-play", "paplay", "cava"].indexOf(n.properties["application.name"] || "") === -1)
    readonly property var stream: streams.length ? streams[streams.length - 1] : null
    readonly property bool mprisPlaying: player?.isPlaying ?? false
    // поток показываем, только если плеер MPRIS сейчас не играет (иначе он главный)
    readonly property bool streamOnly: fake === null && !mprisPlaying && stream !== null

    readonly property bool hasPlayer: fake !== null || player !== null || stream !== null
    readonly property bool playing: fake ? fake.playing === true : (mprisPlaying || stream !== null)
    readonly property string title: fake ? (fake.title || "")
        : streamOnly ? (stream.properties["media.name"] || stream.properties["application.name"] || "Звук")
        : (player?.trackTitle || player?.identity || "")
    readonly property string artist: fake ? (fake.artist || "")
        : streamOnly ? (stream.properties["application.name"] || "") : (player?.trackArtist || "")
    readonly property string art: fake ? (fake.art || "") : streamOnly ? "" : (player?.trackArtUrl || "")

    // Пилюля держится и пару секунд после паузы, чтобы не мигать между треками.
    property bool recent: false
    onPlayingChanged: {
        if (playing) {
            // музыка заиграла — верхний док выглядывает, даже если он спрятан
            if (!recent) peekMusic();
            recent = true;
            graceTimer.stop();
        } else graceTimer.restart();
    }
    onTitleChanged: if (playing && title.length) peekMusic()
    Timer { id: graceTimer; interval: 4000; onTriggered: root.recent = false }
    readonly property bool mediaActive: hasPlayer && (playing || recent)
    // двойной щелчок по пилюле — обычный док, пока музыка не закончится
    property bool barPreferred: false
    onMediaActiveChanged: if (!mediaActive) barPreferred = false
    readonly property bool mediaPill: Settings.get("docks.top.media", true) === true && mediaActive && !barPreferred

    // верхний док показывается на несколько секунд при начале музыки и смене трека
    property bool musicPeek: false
    function peekMusic() { musicPeek = true; musicPeekTimer.restart(); }
    Timer { id: musicPeekTimer; interval: 4000; onTriggered: root.musicPeek = false }
    function toggleMediaView() { if (mediaActive) barPreferred = !barPreferred; }

    // --- умное автоскрытие: прятать док, только если окно заходит на его место ---
    // Геометрию окон знает только Hyprland: пока умный режим включён у какого-то
    // дока, изредка спрашиваем (и сразу — когда окна двигаются или меняются).
    readonly property bool smartUsed: Settings.get("docks.top", ({})).autohide === "smart"
                                      || Settings.get("docks.apps", ({})).autohide === "smart"
    Timer {
        interval: 400
        repeat: true
        running: root.smartUsed
        triggeredOnStart: true
        onTriggered: Hyprland.refreshToplevels()
    }
    Connections {
        target: Hyprland
        enabled: root.smartUsed
        function onRawEvent(event) {
            switch (event.name) {
            case "openwindow": case "closewindow": case "movewindow": case "movewindowv2":
            case "changefloatingmode": case "fullscreen": case "workspace": case "workspacev2":
            case "activewindow": case "resizewindow":
                Hyprland.refreshToplevels();
                break;
            }
        }
    }
    // «желе»: доки вздрагивают от событий — верхний от смены стола и раскладки,
    // док приложений — когда открылось окно (и звук «приложение открылось»;
    // здесь, а не в Sounds: Sounds есть и у процесса «Настроек», звучало бы дважды)
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() { ShellState.pokeDock("top", 0.55); }
        function onRawEvent(event) {
            if (event.name !== "openwindow") return;
            ShellState.pokeDock("apps", 0.5);
            Sounds.play("app-open", 500);
        }
    }
    Connections {
        target: KbLayout
        function onSwitched() { ShellState.pokeDock("top", 0.45); }
    }

    // есть ли на видимом столе монитора окно, задевающее прямоугольник r
    // (координаты экрана монитора) — с запасом в несколько пикселей
    function covered(screenName, r) {
        if (!r) return false;
        const mon = Hyprland.monitors.values.find(m => m.name === screenName);
        const ws = mon?.activeWorkspace;
        if (!mon || !ws) return false;
        const pad = 4;
        for (const t of Hyprland.toplevels.values) {
            if (t.workspace !== ws) continue;
            const o = t.lastIpcObject;
            if (!o || !Array.isArray(o.at) || !Array.isArray(o.size) || o.hidden === true || o.mapped === false) continue;
            const x = o.at[0] - mon.x, y = o.at[1] - mon.y;
            if (x < r.x + r.w + pad && x + o.size[0] > r.x - pad && y < r.y + r.h + pad && y + o.size[1] > r.y - pad) return true;
        }
        return false;
    }

    // --- «остров»: короткое сообщение в верхнем доке ---
    // { kind: "mute", muted } — режим без звука (колокольчик, как в iOS).
    // Док выглядывает, даже если спрятан, и через пару секунд всё как было.
    property var notice: null
    function showNotice(kind, muted) {
        notice = { kind: kind, muted: muted === true, at: Date.now() };
        noticeTimer.restart();
        // звук включили — короткий сигнал (выключение тихое: звука уже нет)
        if (kind === "mute" && muted !== true) Sounds.play("audio-volume-change");
    }
    Timer { id: noticeTimer; interval: 2000; onTriggered: root.notice = null }
    // во вложенной сессии звук по-настоящему не выключается: здесь — каким он стал бы
    property var previewMuted: null

    // выключили или включили звук откуда угодно (клавиша, меню, микшер)
    readonly property PwNode sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }
    readonly property var sinkMuted: sink?.audio ? sink.audio.muted : null
    property var lastSink: null
    property var lastMuted: null
    onSinkMutedChanged: {
        // смена устройства по умолчанию — не переключение режима
        if (sink !== lastSink || sinkMuted === null || lastMuted === null) {
            lastSink = sink;
            lastMuted = sinkMuted;
            return;
        }
        if (sinkMuted !== lastMuted) showNotice("mute", sinkMuted);
        lastMuted = sinkMuted;
    }

    function togglePlaying() {
        if (fake) { fake = Object.assign({}, fake, { playing: !fake.playing }); return; }
        if (player?.canTogglePlaying) player.togglePlaying();
    }

    // --- закреплённые в доке приложений ---
    // элемент docks.apps.pinned: "id.desktop-файла" | { type: "cmd", name, command }
    //                            | { type: "path", name, path }
    readonly property var pinnedRaw: {
        const v = Settings.get("docks.apps.pinned", []);
        return Array.isArray(v) ? v : [];
    }
    function pinKey(p) {
        if (typeof p === "string") return "app:" + p;
        if (p && p.type === "cmd" && p.command) return "cmd:" + p.command;
        if (p && p.type === "path" && p.path) return "path:" + p.path;
        return "";
    }
    function isPinned(key) { return pinnedRaw.some(p => pinKey(p) === key); }
    function pin(p) {
        const key = pinKey(p);
        if (!key || isPinned(key)) return;
        Settings.set("docks.apps.pinned", pinnedRaw.concat([p]));
    }
    function unpin(key) { Settings.set("docks.apps.pinned", pinnedRaw.filter(p => pinKey(p) !== key)); }
    function movePinned(key, delta) {
        const list = pinnedRaw.slice();
        const i = list.findIndex(p => pinKey(p) === key), j = i + delta;
        if (i < 0 || j < 0 || j >= list.length) return;
        const t = list[i]; list[i] = list[j]; list[j] = t;
        Settings.set("docks.apps.pinned", list);
    }
    // ~/… в пути — домашний каталог
    function expandPath(p) {
        const home = Quickshell.env("HOME") || "";
        return p.startsWith("~") ? home + p.slice(1) : p;
    }

    // --- всплывающие окна дока приложений ---
    // { screen: "<имя>", mode: "context" | "add", app: {…}, anchor: { x, y, w, h } }
    property var appMenu: null
    function appMenuKey(m) { return m ? "app:" + m.mode + ":" + (m.app?.key ?? "") : ""; }
    function openAppMenu(screen, mode, app, anchor) {
        const next = { screen: screen.name, mode: mode, app: app, anchor: anchor };
        // то же меню только что закрыли нажатием по этому значку — не открываем снова
        if (ShellState.recentlyDismissed(appMenuKey(next))) return;
        ShellState.closeMenu();
        appMenu = next;
    }
    function closeAppMenu() { appMenu = null; }

    // --- режим правки верхнего дока ---
    property string editScreen: ""
    Connections {
        target: ShellState
        function onDockEditingChanged() {
            if (ShellState.dockEditing) {
                root.editScreen = root.focusedScreen()?.name ?? "";
                ShellState.closeMenu();
                root.closeAppMenu();
            }
        }
        function onMenuChanged() { if (ShellState.menu !== "") root.closeAppMenu(); }
    }

    function focusedScreen() {
        const name = Hyprland.focusedMonitor?.name ?? "";
        return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0] ?? null;
    }

    // для проверки: «мышь у края» без настоящей мыши
    property bool peek: false

    // --- публикация в ShellState (с задержкой, чтобы не дёргать на каждом кадре) ---
    property var pendingDock: ({})
    property var pendingIcons: ({})
    function publishDock(screenName, which, geo) {
        const s = Object.assign({}, pendingDock[screenName] || ShellState.dockGeometry[screenName] || {});
        s[which] = geo;
        const all = Object.assign({}, pendingDock);
        all[screenName] = s;
        pendingDock = all;
        publishTimer.restart();
    }
    function publishIcons(screenName, map) {
        const all = Object.assign({}, pendingIcons);
        all[screenName] = map;
        pendingIcons = all;
        publishTimer.restart();
    }
    Timer {
        id: publishTimer
        interval: 120
        onTriggered: {
            ShellState.dockGeometry = Object.assign({}, ShellState.dockGeometry, root.pendingDock);
            root.pendingDock = {};
            const icons = {};
            for (const scr in root.pendingIcons) root.iconsByScreen[scr] = root.pendingIcons[scr];
            for (const scr in root.iconsByScreen) Object.assign(icons, root.iconsByScreen[scr]);
            root.pendingIcons = {};
            ShellState.appIconGeometry = icons;
        }
    }
    property var iconsByScreen: ({})

    // delta-shell ipc call docks <функция>
    IpcHandler {
        target: "docks"
        // «Изменить модули» из приложения «Настройки»: повторное нажатие закрывает,
        // как Esc, — не нужно искать кнопку «Готово».
        function edit(): void { ShellState.dockEditing = !ShellState.dockEditing; }
        function done(): void { ShellState.dockEditing = false; }
        function toggleMedia(): void { root.toggleMediaView(); }
        // меню модуля верхнего дока, как щелчок по плитке (демо, проверки):
        //     delta-shell ipc call docks menu sound      ещё раз — закрыть
        // «желе» для проверок: толчок и «курсор» над доком (u — px вдоль края, -1 — убрать)
        function poke(dock: string, strength: real): void { ShellState.pokeDock(dock, strength); }
        function hover(dock: string, u: real): void {
            const h = Object.assign({}, ShellState.devHover);
            const key = (root.focusedScreen()?.name ?? "") + "/" + dock;
            if (u < 0) delete h[key]; else h[key] = u;
            ShellState.devHover = h;
        }
        function menu(id: string): void {
            if (ShellState.menu === id) ShellState.closeMenu();
            else ShellState.openMenu(id, root.focusedScreen());
        }
    }
}
