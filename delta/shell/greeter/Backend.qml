pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import qs.common

// Логика экрана входа: пользователи, сессии, вход через greetd.
//
// Режим проверки (DELTA_GREETER_MOCK=1) работает без greetd — во вложенной
// сессии: пароль «delta» подходит, любой другой — нет, запуск сессии только
// пишется в журнал.
//
// Откуда берётся вид экрана входа (см. session/greetd/README.md):
//   /var/lib/delta-greeter/users/<логин>/   — копирует delta-greeter-sync от имени
//       settings.json, wallpaper.*, avatar   пользователя; принимаем, только если
//                                            владелец каталога — сам этот пользователь
//   /var/cache/delta-greeter/state.json      — последний пользователь и сессия (пишет greeter)
Scope {
    id: root

    readonly property bool mock: Quickshell.env("DELTA_GREETER_MOCK") === "1"
    readonly property string dataDir: Quickshell.env("DELTA_GREETER_DIR") || "/var/lib/delta-greeter"
    readonly property string stateDir: Quickshell.env("DELTA_GREETER_STATE")
        || (mock ? (Quickshell.env("HOME") + "/.cache/delta-greeter") : "/var/cache/delta-greeter")
    readonly property string sessionsDir: Quickshell.env("DELTA_GREETER_SESSIONS") || "/usr/share/wayland-sessions"

    // [{ name, realName, avatar, look }] — look: каталог с вашими обоями/темой или ""
    property var users: []
    property int index: 0
    readonly property var user: users[index] || ({ name: "", realName: "", avatar: "", look: "" })
    readonly property string displayName: user.realName || user.name

    // [{ id, name, exec, desktopNames }]
    property var sessions: []
    property string sessionId: "delta"
    readonly property var session: sessions.find(s => s.id === sessionId) || sessions[0] || null

    property var last: ({})
    signal ready()          // пароль принят — пора играть анимацию и запускать сессию

    function nextUser(d) {
        if (users.length < 2) return;
        if (!mock && Greetd.state !== GreetdState.Inactive) Greetd.cancelSession();
        auth.reset();
        index = (index + d + users.length) % users.length;
        applyLook();
    }
    function nextSession() {
        if (sessions.length < 2) return;
        const i = sessions.findIndex(s => s.id === sessionId);
        sessionId = sessions[(i + 1) % sessions.length].id;
    }

    // ---------- проверка пароля (тот же интерфейс, что у lock/Lock.qml) ----------
    QtObject {
        id: auth
        property bool busy: false
        property string message: root.greetdOk ? "" : "Служба входа greetd недоступна"
        property bool isError: !root.greetdOk
        property string prompt: ""
        property bool echo: false
        property string pending: ""
        signal failed()

        function reset() { busy = false; message = ""; isError = false; prompt = ""; echo = false; pending = ""; }

        function fail(text) {
            busy = false; pending = ""; prompt = ""; echo = false;
            message = text; isError = true;
            failed();
        }

        function submit(text) {
            if (busy || !root.user.name) return;
            busy = true; message = ""; isError = false;
            if (root.mock) { pending = text; mockTimer.restart(); return; }
            if (Greetd.state === GreetdState.Authenticating && pending === "" && prompt !== "") {
                Greetd.respond(text);
                return;
            }
            if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession();
            pending = text;
            Greetd.createSession(root.user.name);
        }
    }
    readonly property alias auth: auth
    readonly property bool greetdOk: mock || Greetd.available

    Timer {
        id: mockTimer
        interval: 700
        onTriggered: {
            if (auth.pending === "delta") { auth.pending = ""; auth.busy = false; root.ready(); }
            else auth.fail("Неверный пароль");
        }
    }

    Connections {
        target: root.mock ? null : Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                if (auth.pending.length) { Greetd.respond(auth.pending); auth.pending = ""; }
                else {
                    auth.busy = false;
                    auth.prompt = message.replace(/:\s*$/, "");
                    auth.echo = echoResponse;
                }
            } else if (message.length) {
                auth.message = message;
                auth.isError = error;
            }
        }
        function onAuthFailure(message) { auth.fail(message && message.length && message !== "pam_authenticate" ? message : "Неверный пароль"); }
        function onError(error) { console.warn("[greeter] greetd: " + error); auth.fail("Ошибка входа: " + error); }
        function onReadyToLaunch() { auth.busy = false; root.ready(); }
    }

    // Запуск — после анимации: greetd ждёт, что greeter сразу завершится.
    function launch() {
        const s = session;
        if (!s) { auth.fail("Нет ни одной сессии в " + sessionsDir); return; }
        const cmd = s.exec.replace(/%[a-zA-Z]/g, "").trim().split(/\s+/);
        const env = ["XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=" + s.id,
            "XDG_CURRENT_DESKTOP=" + (s.desktopNames || s.id).replace(/;$/, "").replace(/;/g, ":")];
        saveState();
        if (mock) { console.info("[greeter] (проверка) запуск: " + cmd.join(" ") + " | " + env.join(" ")); return; }
        Greetd.launch(cmd, env, true);
    }

    // ---------- состояние: последний пользователь и сессия ----------
    FileView {
        id: stateFile
        path: root.stateDir + "/state.json"
        printErrors: false
        onLoaded: {
            try { root.last = JSON.parse(text()) || {}; } catch (e) { root.last = {}; }
            root.pickDefaults();
        }
        onLoadFailed: root.pickDefaults()
    }
    function saveState() {
        stateDirProc.running = true;
        stateFile.setText(JSON.stringify({ user: user.name, session: sessionId }) + "\n");
    }
    Process { id: stateDirProc; command: ["mkdir", "-p", root.stateDir] }

    function pickDefaults() {
        const i = users.findIndex(u => u.name === last.user);
        if (i >= 0) index = i;
        if (last.session && sessions.some(s => s.id === last.session)) sessionId = last.session;
        else if (!sessions.some(s => s.id === "delta") && sessions.length) sessionId = sessions[0].id;
        applyLook();
    }

    // ---------- пользователи ----------
    Process {
        running: true
        // логин:имя:аватар:каталог-вида. Каталог вида берём, только если им владеет сам
        // пользователь (иначе кто-то другой мог создать его заранее под чужим именем).
        command: ["sh", "-c",
            "d=$1; getent passwd | while IFS=: read -r n _ uid _ gecos home sh; do " +
            "[ \"$uid\" -ge 1000 ] && [ \"$uid\" -lt 60000 ] || continue; " +
            "case $sh in */nologin|*/false|'') continue;; esac; " +
            "look=; [ -d \"$d/users/$n\" ] && [ \"$(stat -c %u \"$d/users/$n\")\" = \"$uid\" ] && look=$d/users/$n; " +
            "av=; for f in \"/var/lib/AccountsService/icons/$n\" \"$look/avatar\"; do [ -n \"$f\" ] && [ -r \"$f\" ] && [ -s \"$f\" ] && { av=$f; break; }; done; " +
            "printf '%s\\t%s\\t%s\\t%s\\n' \"$n\" \"${gecos%%,*}\" \"$av\" \"$look\"; done",
            "sh", root.dataDir]
        stdout: StdioCollector {
            onStreamFinished: {
                root.users = text.split("\n").filter(l => l.length).map(l => {
                    const p = l.split("\t");
                    return { name: p[0], realName: p[1] || "", avatar: p[2] || "", look: p[3] || "" };
                });
                stateFile.reload();
            }
        }
    }

    // ---------- сессии из /usr/share/wayland-sessions ----------
    Process {
        running: true
        command: ["sh", "-c",
            "for f in \"$1\"/*.desktop; do [ -r \"$f\" ] || continue; " +
            "grep -qi '^NoDisplay=true' \"$f\" && continue; grep -qi '^Hidden=true' \"$f\" && continue; " +
            "id=$(basename \"$f\" .desktop); " +
            "name=$(sed -n 's/^Name\\[ru\\]=//p' \"$f\" | head -1); [ -n \"$name\" ] || name=$(sed -n 's/^Name=//p' \"$f\" | head -1); " +
            "ex=$(sed -n 's/^Exec=//p' \"$f\" | head -1); dn=$(sed -n 's/^DesktopNames=//p' \"$f\" | head -1); " +
            "printf '%s\\t%s\\t%s\\t%s\\n' \"$id\" \"$name\" \"$ex\" \"$dn\"; done",
            "sh", root.sessionsDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.split("\n").filter(l => l.length).map(l => {
                    const p = l.split("\t");
                    return { id: p[0], name: p[1] || p[0], exec: p[2] || "", desktopNames: p[3] || "" };
                }).filter(s => s.exec.length);
                // Delta — первой
                list.sort((a, b) => (b.id === "delta") - (a.id === "delta") || a.name.localeCompare(b.name));
                root.sessions = list;
                if (root.users.length) root.pickDefaults();
            }
        }
    }

    // ---------- вид выбранного пользователя ----------
    // Копируем его settings.json туда, где его читает Settings (XDG_CONFIG_HOME/delta) —
    // тема, акцент, обои и часы применяются сами, как в оболочке.
    readonly property string configFile: Settings.path
    FileView { id: lookSrc; printErrors: false; blockLoading: true }
    FileView { id: lookDst; path: root.configFile; printErrors: false; atomicWrites: true }

    function applyLook() {
        let cfg = {};
        if (user.look) {
            lookSrc.path = user.look + "/settings.json";
            lookSrc.reload();
            lookSrc.waitForJob();
            try { cfg = JSON.parse(lookSrc.text()) || {}; } catch (e) { cfg = {}; }
        }
        // обои — только из каталога вида, чужие пути (домашний каталог) greeter'у не видны
        if (!cfg.wallpaper || typeof cfg.wallpaper !== "object") cfg.wallpaper = {};
        const wp = String(cfg.wallpaper.path || "");
        if (!user.look || wp.indexOf(user.look + "/") !== 0) cfg.wallpaper.path = "";
        const text = JSON.stringify(cfg, null, 2) + "\n";
        if (text !== lastLook) {
            lastLook = text;
            cfgDirProc.running = true;
            lookDst.setText(text);
        }
    }
    property string lastLook: ""
    Process { id: cfgDirProc; command: ["mkdir", "-p", Settings.configDir] }
}
