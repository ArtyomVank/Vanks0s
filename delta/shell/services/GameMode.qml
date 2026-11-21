pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.common

// Delta Play — игровой режим. Пока открыто окно игры, система подстраивается
// под неё, а когда игр больше нет — возвращается как была:
//   • «Не беспокоить» (play.dnd): уведомления не всплывают поверх игры;
//   • производительность (play.performance): профиль «Максимум» у
//     power-profiles-daemon — powerprofilesctl launch держит его, пока жив
//     процесс-держатель, и сам вернёт прежний (пароль не нужен).
// Включение — само (play.auto) или вручную: GameMode.setManual(true).
//
// Игра — окно Steam (steam_app_*), Windows-программа (*.exe, Proton, Wine),
// gamescope, окно с типом содержимого «game» или класс из play.games.
//
//   GameMode.active      режим сейчас включён
//   GameMode.game        { class, title, address } — окно игры (первое)
//   GameMode.since       когда включился (мс), для «в игре 1:24»
//   GameMode.setManual(on)
//
// Во вложенной сессии и в пробном режиме профиль не трогается.
Singleton {
    id: root

    readonly property bool dryRun: (Quickshell.env("DELTA_NESTED") || "") !== "" || Quickshell.env("DELTA_DRY_RUN") === "1"
    readonly property bool auto: Settings.get("play.auto", true) !== false
    readonly property bool wantDnd: Settings.get("play.dnd", true) !== false
    readonly property bool wantPerf: Settings.get("play.performance", true) !== false

    property var game: null
    property bool manual: false
    readonly property bool active: manual || (auto && game !== null)
    property real since: 0

    readonly property var builtin: /^(steam_app_\d+|.*\.exe|gamescope|steam_proton|wine.*|lutris.*|heroic.*|minecraft.*|org\.prismlauncher\..*)$/i
    readonly property var extra: {
        const out = [];
        const list = Settings.get("play.games", []);
        for (const p of (Array.isArray(list) ? list : [])) {
            if (typeof p !== "string" || !p.length) continue;
            try { out.push(new RegExp(p, "i")); } catch (e) { console.warn("[delta] play.games: " + p + ": " + e); }
        }
        return out;
    }
    function isGame(c) {
        const cls = String(c.class || c.initialClass || "");
        return c.contentType === "game" || builtin.test(cls) || builtin.test(String(c.initialClass || ""))
            || extra.some(r => r.test(cls));
    }
    function setManual(on) { manual = on; }

    // --- какие окна открыты: hyprctl clients (и у своего композитора тоже) ---
    Process {
        id: clients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try { list = JSON.parse(text); } catch (e) { return; }
                const g = (Array.isArray(list) ? list : []).find(c => c && root.isGame(c));
                root.game = g ? { class: g.class || g.initialClass || "", title: g.title || "", address: g.address || "" } : null;
            }
        }
    }
    function rescan() { if (!clients.running) clients.running = true; }
    // открытие и закрытие окон приходят пачкой — опрос раз в полсекунды
    Timer { id: settle; interval: 500; onTriggered: root.rescan() }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["openwindow", "closewindow", "windowtitlev2", "fullscreen", "movewindowv2"].indexOf(event.name) !== -1) settle.restart();
        }
    }
    Component.onCompleted: rescan()

    // --- что режим делает ---
    property bool dndWas: false
    property bool dndOurs: false
    onActiveChanged: {
        if (active) {
            since = Date.now();
            if (wantDnd && Settings.get("notifications.dnd", false) !== true) {
                dndWas = false;
                dndOurs = true;
                Settings.set("notifications.dnd", true);
                ShellState.dnd = true;
            }
            ShellState.island({ kind: "play", icon: "gamepad", title: I18n.tr("Игровой режим"),
                                         text: game ? game.title || game.class : I18n.tr("включён"), ms: 2600 });
        } else {
            // вернуть «Не беспокоить», только если включали его мы
            if (dndOurs) {
                Settings.set("notifications.dnd", dndWas);
                ShellState.dnd = dndWas;
                dndOurs = false;
            }
            since = 0;
        }
    }

    // профиль «Максимум», пока жив держатель (powerprofilesctl сам вернёт
    // прежний). Держатель следит за своим родителем: оболочку закрыли или
    // режим выключили — powerprofilesctl завершён, и он уходит следом
    Process {
        id: hold
        running: root.active && root.wantPerf && !root.dryRun
        command: ["powerprofilesctl", "launch", "--profile", "performance", "--reason", "Delta Play", "--",
                  "sh", "-c", "while kill -0 \"$PPID\" 2>/dev/null; do sleep 5; done"]
    }
}
