pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Запущенные программы Windows (Wine, Proton, delta-exe). Их значки трея —
// старого вида (XEmbed): ни одна современная панель их не показывает,
// поэтому «Фоновые приложения» берут программы отсюда — по процессам.
//
//   WinApps.apps    [{ key, name, icon, exe, pids }] — key: имя exe строчными
//   WinApps.focus(app)   поднять окно программы (класс окна Wine — имя exe)
//   WinApps.watch        пока true — список обновляется раз в 5 секунд
//
// Служебные процессы Wine и Proton (services.exe, explorer.exe, steam.exe…)
// не показываются.
Singleton {
    id: root

    property var apps: []
    property bool watch: false

    readonly property var skip: ["services.exe", "winedevice.exe", "plugplay.exe", "svchost.exe", "explorer.exe",
        "rpcss.exe", "tabtip.exe", "conhost.exe", "start.exe", "wineboot.exe", "winemenubuilder.exe", "steam.exe",
        "rundll32.exe", "regsvr32.exe", "msiexec.exe", "cmd.exe", "wineconsole.exe", "mscorsvw.exe", "ngen.exe",
        "crashpad_handler.exe", "unitycrashhandler64.exe", "unitycrashhandler32.exe", "crashreportclient.exe",
        "lestaerrormonitor.exe", "qtwebengineprocess.exe", "cefsharp.browsersubprocess.exe", "steamwebhelper.exe"]

    // ярлыки delta-exe: имя exe → название и значок
    function entryFor(key) {
        for (const e of DesktopEntries.applications.values) {
            const ex = (e.execString || "").toLowerCase();
            if (ex.indexOf("delta-exe") === -1 && ex.indexOf(".exe") === -1) continue;
            const m = ex.match(/([^\\/"]+\.exe)/g);
            if (m && m.some(x => x === key)) return e;
        }
        return null;
    }

    function parse(text) {
        const map = {};
        for (const line of text.split("\n")) {
            const m = line.match(/^\s*(\d+)\s+(.*)$/);
            if (!m) continue;
            const args = m[2];
            // путь к exe — с диском («C:\…») или обычный путь Linux
            const hit = args.match(/(?:^|[\s"'])((?:[A-Za-z]:\\|\/)[^"']*?([^\\\/"']+\.exe))(?=$|[\s"'])/i);
            if (!hit) continue;
            const key = hit[2].toLowerCase();
            if (skip.indexOf(key) !== -1) continue;
            // сами раннеры (wine64-preloader, proton) — не программы
            const head = args.split(/\s+/)[0];
            if (/\/(proton|umu-run|wineserver)$/.test(head)) continue;
            if (!map[key]) map[key] = { key: key, exe: hit[2], pids: [] };
            map[key].pids.push(Number(m[1]));
        }
        const out = Object.values(map).map(a => {
            const e = entryFor(a.key);
            return Object.assign(a, {
                name: e ? e.name : a.exe.replace(/\.exe$/i, ""),
                icon: e && e.icon ? (e.icon.startsWith("/") ? "file://" + e.icon : Quickshell.iconPath(e.icon, true)) : ""
            });
        });
        out.sort((a, b) => a.name.localeCompare(b.name));
        // без лишних перерисовок, если ничего не поменялось
        const sig = JSON.stringify(out.map(a => a.key + ":" + a.pids.join(",")));
        if (sig !== lastSig) { lastSig = sig; apps = out; }
    }
    property string lastSig: ""

    function focus(app) {
        if (!app) return;
        Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "class:" + app.key]);
    }

    Process {
        id: ps
        command: ["ps", "x", "-o", "pid=,args="]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }
    Timer {
        interval: 5000
        repeat: true
        running: root.watch
        triggeredOnStart: true
        onTriggered: if (!ps.running) ps.running = true
    }
}
