pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower

// Звуки оболочки: уведомление, громкость, включение звука, снимок экрана,
// блокировка, зарядка. Файлы — тема звуков freedesktop, играет pw-play.
// Настройки: sounds.enabled (вкл/выкл), sounds.volume (0–1).
//     Sounds.play("message-new-instant")
Singleton {
    id: root

    readonly property bool enabled: Settings.get("sounds.enabled", true) !== false
    readonly property real volume: Math.max(0, Math.min(1, Number(Settings.get("sounds.volume", 0.6))))
    readonly property string dir: "/usr/share/sounds/freedesktop/stereo/"

    // когда звук играл последний раз — частые события (громкость колесом) не трещат
    property var last: ({})
    function play(name, minGap) {
        if (!enabled || volume <= 0) return;
        const now = Date.now();
        if (now - (last[name] || 0) < (minGap ?? 120)) return;
        last[name] = now;
        Quickshell.execDetached(["pw-play", "--volume", volume.toFixed(2), dir + name + ".oga"]);
    }
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
