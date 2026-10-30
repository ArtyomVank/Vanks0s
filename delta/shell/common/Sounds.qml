pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Звуки оболочки: уведомление, громкость, включение звука, снимок экрана,
// блокировка, зарядка. Файлы — тема звуков freedesktop и свои мягкие тона
// Delta (shell/sounds/*.ogg, их синтезирует tools/gen-sounds.sh), играет pw-play.
// Настройки: sounds.enabled (вкл/выкл), sounds.volume (0–1), sounds.off —
// выключенные группы (groups: уведомления, громкость, приложения…).
//     Sounds.play("message-new-instant")
Singleton {
    id: root

    readonly property bool enabled: Settings.get("sounds.enabled", true) !== false
    readonly property real volume: Math.max(0, Math.min(1, Number(Settings.get("sounds.volume", 0.6))))
    readonly property string dir: "/usr/share/sounds/freedesktop/stereo/"
    readonly property string ownDir: Quickshell.shellDir + "/sounds/"
    readonly property var own: ["oobe-hello", "oobe-step", "oobe-back", "oobe-select", "oobe-hold", "oobe-done",
        "pop", "workspace", "island", "swoosh", "drop", "unlock",
        "snap-in", "snap", "launcher", "tick", "sparkle", "app-open"]
    // группы для «Настройки → Звук»; звук без группы — «Интерфейс»
    readonly property var groups: [
        { id: "notify", label: "Уведомления", note: "Пришло сообщение", icon: "bell",
          sounds: ["message-new-instant", "dialog-warning"] },
        { id: "apps", label: "Открытие приложений", note: "Окно приложения появилось, меню приложений, сворачивание", icon: "apps",
          sounds: ["app-open", "launcher", "swoosh"] },
        { id: "windows", label: "Окна и рабочие столы", note: "Прилипание к краям, смена стола", icon: "windows",
          sounds: ["snap-in", "snap", "workspace"] },
        { id: "volume", label: "Громкость", note: "Щелчок при смене громкости", icon: "volume",
          sounds: ["audio-volume-change"] },
        { id: "lock", label: "Блокировка и питание", note: "Разблокировка, выход, зарядка", icon: "lock",
          sounds: ["unlock", "service-logout", "power-plug", "power-unplug"] },
        { id: "timer", label: "Таймер", note: "Время вышло", icon: "clock",
          sounds: ["alarm-clock-elapsed"] },
        { id: "shot", label: "Снимок экрана", note: "Щелчок затвора", icon: "screenshot",
          sounds: ["camera-shutter"] },
        { id: "ui", label: "Интерфейс", note: "Меню, виджеты, остров, первая настройка", icon: "sliders",
          sounds: [] }
    ]
    readonly property var off: Settings.get("sounds.off", []) || []
    function groupOf(name) {
        const g = groups.find(x => x.sounds.indexOf(name) >= 0);
        return g ? g.id : "ui";
    }
    function allowed(name) { return enabled && volume > 0 && off.indexOf(groupOf(name)) < 0; }
    function file(name) { return own.indexOf(name) >= 0 ? ownDir + name + ".ogg" : dir + name + ".oga"; }

    // когда звук играл последний раз — частые события (громкость колесом) не трещат
    property var last: ({})
    function play(name, minGap) {
        if (!allowed(name)) return;
        const now = Date.now();
        if (now - (last[name] || 0) < (minGap ?? 120)) return;
        last[name] = now;
        Quickshell.execDetached(["pw-play", "--volume", volume.toFixed(2), file(name)]);
    }
    // звук, который можно оборвать (удержание кнопки «Начать»)
    function hold(name) {
        holdProc.running = false;
        if (!allowed(name)) return;
        holdProc.command = ["pw-play", "--volume", volume.toFixed(2), file(name)];
        holdProc.running = true;
    }
    function release() { holdProc.running = false; }
    Process { id: holdProc }
    // для команд оболочки (снимок экрана): кусок sh, играющий звук, или пусто
    function shell(name) {
        return allowed(name) ? " && pw-play --volume " + volume.toFixed(2) + " '" + dir + name + ".oga'" : "";
    }

    // зарядку подключили или отключили
    Connections {
        target: UPower
        function onOnBatteryChanged() { root.play(UPower.onBattery ? "power-unplug" : "power-plug"); }
    }
}
