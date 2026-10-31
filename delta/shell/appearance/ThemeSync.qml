pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Переносит оформление Delta на программы GTK и Qt (settings/helpers/theme-apply):
// при первом входе и после каждого изменения темы, акцента, значков, курсора
// или шрифта — откуда бы оно ни пришло («Настройки», IPC, правка файла).
//
// Что уже применено, помнит отметка в state-папке оболочки: при обычном входе
// помощник не запускается. Выключается настройкой appearance.applyApps.
//
// Во вложенной сессии системные команды (gsettings, hyprctl setcursor) только
// печатаются: dconf общий с основной сессией. Файлы пишутся в её HOME.
Scope {
    id: root

    readonly property var a: Settings.s.appearance || {}
    readonly property bool enabled: Settings.ready && a.applyApps !== false
    readonly property bool nested: (Quickshell.env("DELTA_NESTED") || "") !== ""
    readonly property bool dryRun: nested || Quickshell.env("DELTA_DRY_RUN") === "1"

    readonly property var args: [
        "--scheme", Theme.light ? "light" : "dark",
        "--icons", a.iconTheme || "Papirus-Dark",
        "--cursor", a.cursorTheme || "Adwaita",
        "--cursor-size", String(a.cursorSize ?? 24),
        "--accent", String(Theme.accent),
        "--base", Theme.baseRgb,
        "--radius", String(Settings.get("windows.rounding", 16)),
        "--font", Theme.font
    ]
    readonly property string key: args.join(" ")

    FileView {
        id: stamp
        path: Quickshell.statePath("theme-applied")
        blockLoading: true
        printErrors: false
    }

    // темы перебирают щелчками — ждём, пока выбор устоится
    Timer { id: debounce; interval: 1200; onTriggered: root.apply() }
    onKeyChanged: if (enabled) debounce.restart()
    onEnabledChanged: if (enabled) debounce.restart()

    function apply() {
        if (!enabled) return;
        if (stamp.text().trim() === key) return;
        if (proc.running) { debounce.restart(); return; }
        proc.forKey = key;
        proc.command = ["bash", Quickshell.shellDir + "/settings/helpers/theme-apply"].concat(args);
        proc.running = true;
    }

    Process {
        id: proc
        property string forKey
        environment: ({ DELTA_DRY_RUN: root.dryRun ? "1" : "0" })
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            if (out.text.trim()) console.info("[delta] оформление GTK/Qt:\n" + out.text.trim());
            if (code !== 0) {
                console.warn("[delta] оформление GTK/Qt не применилось (код " + code + "): " + err.text.trim());
                return;
            }
            // в пробном режиме отметку не ставим: настоящий вход должен применить
            if (!root.dryRun) stamp.setText(forKey + "\n");
        }
    }
}
