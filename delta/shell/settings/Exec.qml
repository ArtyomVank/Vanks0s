pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Единственный путь, которым «Настройки» что-то меняют вне settings.json.
//
//   Exec.read(cmd, (code, out, err) => …)      чтение состояния — выполняется всегда
//   Exec.run(cmd, { label, home, selfDry, redact, input, env, toast, dryOut, done })  изменение
//
// Пробный режим (DELTA_DRY_RUN=1, во всех проверках): команды изменения не
// выполняются, а пишутся в журнал и в лог. Исключение — home: true, то есть
// команды, которые пишут только в домашнюю папку: во вложенной сессии
// (DELTA_NESTED=1) HOME — отдельная папка разработчика, там они выполняются.
Singleton {
    id: root

    // отладочная точка входа (DELTA_SHELL_ENTRY) — всегда пробный режим
    property bool forceDry: (Quickshell.env("DELTA_SHELL_ENTRY") || "").length > 0
    readonly property bool dryRun: forceDry || Quickshell.env("DELTA_DRY_RUN") === "1"
    readonly property bool homeWritable: !dryRun || Quickshell.env("DELTA_NESTED") === "1"
    readonly property string helpers: Quickshell.shellDir + "/settings/helpers"

    // [{ time, label, cmd, dry }] — последние команды (для IPC и проверки)
    property var journal: []

    function helper(name) { return helpers + "/" + name; }

    function shown(cmd, redact) {
        return cmd.map((a, i) => (redact || []).indexOf(i) !== -1 ? "‹скрыто›" : /[\s"'$]/.test(a) ? JSON.stringify(a) : a).join(" ");
    }

    function note(label, cmd, dry, redact) {
        const j = journal.slice(-49);
        j.push({ time: new Date().toISOString(), label: label || "", cmd: shown(cmd, redact), dry: dry });
        journal = j;
    }

    function read(cmd, done, env) {
        spawn(cmd, done, "", env);
    }

    // selfDry: true — помощник сам понимает DELTA_DRY_RUN (theme-apply), его
    // запускаем всегда и передаём режим через окружение
    function run(cmd, opts) {
        const o = opts || {};
        if (o.selfDry) {
            note(o.label, cmd, dryRun, o.redact);
            spawn(cmd, o.done, o.input || "", Object.assign({ DELTA_DRY_RUN: dryRun ? "1" : "0" }, o.env || {}));
            return;
        }
        const dry = dryRun && !(o.home && homeWritable);
        note(o.label, cmd, dry, o.redact);
        if (dry) {
            console.info("[delta-settings] пробный режим, не выполняю: " + shown(cmd, o.redact));
            if (o.toast !== false) Nav.toast("Пробный режим: " + (o.label || shown(cmd, o.redact)));
            // ответ как от успешной команды, чтобы интерфейс прошёл весь путь
            if (o.done) Qt.callLater(() => o.done(0, o.dryOut || "", ""));
            return;
        }
        spawn(cmd, o.done, o.input || "", o.env);
    }

    function spawn(cmd, done, input, env) {
        proc.createObject(root, { command: cmd, done: done || null, input: input || "", environment: env || ({}) });
    }

    Component {
        id: proc
        Process {
            id: p
            property var done: null
            property string input: ""
            property int code: -1
            property int left: 3
            property bool finished: false
            function finish() {
                if (finished) return;
                finished = true;
                const cb = done;
                if (cb) cb(code === -1 ? 127 : code, out.text, err.text);
                p.destroy();
            }
            function step() { if (--left <= 0) finish(); }
            running: true
            stdinEnabled: input.length > 0
            stdout: StdioCollector { id: out; onStreamFinished: p.step() }
            stderr: StdioCollector { id: err; onStreamFinished: p.step() }
            onStarted: if (input.length > 0) { write(input); stdinEnabled = false; }
            onExited: c => { code = c; step(); }
            // программа не запустилась (нет такой) — exited может не прийти
            onRunningChanged: if (!running) guard.start()
            property Timer guard: Timer { interval: 600; onTriggered: p.finish() }
        }
    }
}
