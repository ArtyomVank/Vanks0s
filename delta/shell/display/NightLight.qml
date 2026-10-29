pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import qs.display.parts
import "sun.js" as Sun

// Ночной свет через hyprsunset (необязательная зависимость: её может не быть).
//
// Расписание считаем сами: «закат — рассвет» по координатам (настройки
// display.nightLight.lat/lon, иначе — координаты часового пояса из
// zone1970.tab, без сети) или фиксированные часы. Пока свет нужен, держим
// процесс hyprsunset; температуру меняем на лету через `hyprctl hyprsunset`.
//
// Синглтон работает, только пока на него кто-то ссылается: в оболочке его
// нужно «разбудить» (см. отчёт для shell.qml).
Singleton {
    id: root

    readonly property bool dryRun: (Quickshell.env("DELTA_NESTED") || "") !== "" || Quickshell.env("DELTA_DRY_RUN") === "1"
                                   || (Quickshell.env("DELTA_DISPLAYS_MOCK") || "") !== ""
    readonly property string instance: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""

    property bool installed: false
    property bool checked: false
    // для проверки интерфейса без hyprsunset (dev-display)
    property bool pretendInstalled: false
    readonly property bool usable: installed || pretendInstalled

    readonly property bool enabled: Settings.get("display.nightLight.enabled", false) === true
    readonly property int temperature: Math.max(1000, Math.min(6500, Settings.get("display.nightLight.temperature", 4500)))
    // "sun" — от заката до рассвета, "time" — по часам, "always" — всегда
    readonly property string schedule: Settings.get("display.nightLight.schedule", "sun")
    readonly property string from: Settings.get("display.nightLight.from", "22:00")
    readonly property string to: Settings.get("display.nightLight.to", "07:00")

    property string zone: ""
    property var zoneLocation: null
    readonly property var location: {
        const lat = Settings.get("display.nightLight.lat", null), lon = Settings.get("display.nightLight.lon", null);
        if (typeof lat === "number" && typeof lon === "number") return { lat: lat, lon: lon, source: "settings" };
        return zoneLocation ? { lat: zoneLocation.lat, lon: zoneLocation.lon, source: "zone" } : null;
    }

    // минуты от полуночи; пересчитываются раз в минуту (tick)
    property int tick: 0
    readonly property var sunToday: {
        tick;
        if (!location) return null;
        const t = Sun.times(new Date(), location.lat, location.lon);
        return t ? { sunrise: Sun.minutesOf(t.sunrise), sunset: Sun.minutesOf(t.sunset) } : null;
    }
    readonly property var span: {
        if (schedule === "time") {
            const f = Sun.parseTime(from), t = Sun.parseTime(to);
            return f !== null && t !== null ? { from: f, to: t } : null;
        }
        // без координат — как будто 20:00–07:00
        return sunToday ? { from: sunToday.sunset, to: sunToday.sunrise } : { from: 20 * 60, to: 7 * 60 };
    }
    readonly property bool active: {
        tick;
        if (!enabled) return false;
        if (schedule === "always") return true;
        if (!span) return false;
        const now = new Date();
        return Sun.inWindow(now.getHours() * 60 + now.getMinutes(), span.from, span.to);
    }

    function fmt(minutes) { return Sun.fmt(minutes); }

    // включить/выключить, не дожидаясь расписания (кнопка в меню)
    function toggle() { Settings.set("display.nightLight.enabled", !enabled); }

    Timer { interval: 30000; running: true; repeat: true; onTriggered: root.tick++ }

    // hyprsunset живёт, пока свет нужен; без него гамма возвращается сама
    Process {
        id: sunset
        running: root.installed && root.active && !root.dryRun
        command: ["hyprsunset", "--temperature", String(root.temperature)]
        stderr: StdioCollector { onStreamFinished: if (text.trim().length) console.info("[delta] hyprsunset: " + text.trim()) }
    }
    onTemperatureChanged: if (sunset.running) tempTimer.restart()
    Timer {
        id: tempTimer
        interval: 250
        onTriggered: Quickshell.execDetached(["hyprctl", "-i", root.instance, "hyprsunset", "temperature", String(root.temperature)])
    }
    onActiveChanged: if (dryRun) console.info("[delta] ночной свет (проверка): " + (active ? "вкл, " + temperature + " K" : "выкл"))

    Component { id: runComp; Run {} }
    function run(argv, done) { runComp.createObject(root, { argv: argv, done: done }); }

    Component.onCompleted: {
        run(["sh", "-c", "command -v hyprsunset"], (code, out) => { root.installed = code === 0; root.checked = true; });
        // часовой пояс: $TZ или ссылка /etc/localtime
        run(["sh", "-c", 'z=${TZ#:}; [ -n "$z" ] || z=$(readlink -f /etc/localtime | sed "s|.*/zoneinfo/||"); echo "$z"; cat /usr/share/zoneinfo/zone1970.tab 2>/dev/null'], (code, out) => {
            const nl = out.indexOf("\n");
            root.zone = out.slice(0, nl).trim();
            root.zoneLocation = Sun.zoneCoords(out.slice(nl + 1), root.zone);
        });
    }
}
