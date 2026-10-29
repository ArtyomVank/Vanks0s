pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Звуки оболочки: уведомление, громкость, включение звука, снимок экрана,
// блокировка, зарядка. Файлы — тема звуков freedesktop и свои мягкие тона
// Delta (shell/sounds/*.ogg, их синтезирует tools/gen-sounds.sh), играет pw-play.
// Настройки: sounds.enabled (вкл/выкл), sounds.volume (0–1).
//     Sounds.play("message-new-instant")
Singleton {
    id: root

    readonly property bool enabled: Settings.get("sounds.enabled", true) !== false
    readonly property real volume: Math.max(0, Math.min(1, Number(Settings.get("sounds.volume", 0.6))))
    readonly property string dir: "/usr/share/sounds/freedesktop/stereo/"
    readonly property string ownDir: Quickshell.shellDir + "/sounds/"
    readonly property var own: ["oobe-hello", "oobe-step", "oobe-back", "oobe-select", "oobe-hold", "oobe-done",
        "pop", "workspace", "island", "swoosh", "drop", "unlock"]
    function file(name) { return own.indexOf(name) >= 0 ? ownDir + name + ".ogg" : dir + name + ".oga"; }

    // когда звук играл последний раз — частые события (громкость колесом) не трещат
    property var last: ({})
    function play(name, minGap) {
        if (!enabled || volume <= 0) return;
        const now = Date.now();
        if (now - (last[name] || 0) < (minGap ?? 120)) return;
        last[name] = now;
        Quickshell.execDetached(["pw-play", "--volume", volume.toFixed(2), file(name)]);
    }
    // звук, который можно оборвать (удержание кнопки «Начать»)
    function hold(name) {
        holdProc.running = false;
        if (!enabled || volume <= 0) return;
        holdProc.command = ["pw-play", "--volume", volume.toFixed(2), file(name)];
        holdProc.running = true;
    }
    function release() { holdProc.running = false; }
    Process { id: holdProc }
    // для команд оболочки (снимок экрана): кусок sh, играющий звук, или пусто
    function shell(name) {
        return enabled && volume > 0 ? " && pw-play --volume " + volume.toFixed(2) + " '" + dir + name + ".oga'" : "";
    }

    // зарядку подключили или отключили
    Connections {
        target: UPower
        function onOnBatteryChanged() { root.play(UPower.onBattery ? "power-unplug" : "power-plug"); }
    }
}
