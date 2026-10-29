pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.display.parts

// Яркость экранов.
//
//   Brightness.available     есть ли что регулировать
//   Brightness.value         0..1 — основной экран (встроенный, иначе основной внешний)
//   Brightness.set(v)        установить: встроенную подсветку, а если её нет — все внешние
//   Brightness.step(d)       прибавить d (может быть отрицательным), вернуть новое значение
//
//   Brightness.has(порт) / valueFor(порт) / setFor(порт, v)   — отдельный монитор
//   Brightness.devices       { порт: { kind: "backlight" | "ddc", id, value, max } }
//
// Встроенный экран — logind Session.SetBrightness (без root), запасной путь —
// brightnessctl. Внешние — DDC/CI через ddcutil: он медленный (сотни мс на
// команду), поэтому поиск идёт в фоне с кешем, а запись — с задержкой, по
// одной команде на монитор, последним значением.
//
// Во вложенной сессии, с моком мониторов и в пробном режиме яркость не
// меняется по-настоящему — только значение в интерфейсе (и строка в журнале).
Singleton {
    id: root

    readonly property bool dryRun: Displays.mock || (Quickshell.env("DELTA_NESTED") || "") !== ""
                                   || Quickshell.env("DELTA_DRY_RUN") === "1"

    property var devices: ({})
    readonly property bool available: Object.keys(devices).length > 0
    readonly property string mainOutput: {
        const keys = Object.keys(devices);
        const bl = keys.find(k => devices[k].kind === "backlight");
        if (bl !== undefined) return bl;
        if (devices[Displays.primaryName]) return Displays.primaryName;
        return keys.length ? keys[0] : "";
    }
    readonly property real value: devices[mainOutput] ? devices[mainOutput].value : 0

    function has(output) { return devices[output] !== undefined; }
    function valueFor(output) { return devices[output] ? devices[output].value : 0; }

    function set(v) {
        const keys = Object.keys(devices);
        const bl = keys.filter(k => devices[k].kind === "backlight");
        for (const k of (bl.length ? bl : keys)) setFor(k, v);
    }

    function step(d) {
        set(value + d);
        return value;
    }

    function setFor(output, v) {
        const dev = devices[output];
        if (!dev) return;
        // подсветку не гасим совсем — иначе экран выглядит выключенным
        v = Math.max(dev.kind === "backlight" ? 0.01 : 0, Math.min(1, v));
        update(output, { value: v, dirty: true });
        if (dev.kind === "backlight") blTimer.restart();
        else ddcTimer.restart();
    }

    function update(output, patch) {
        const next = Object.assign({}, devices);
        next[output] = Object.assign({}, next[output], patch);
        devices = next;
    }

    // --- запись ------------------------------------------------------------

    property bool logindWorks: true
    property var busy: ({})

    function flush(kind) {
        for (const k in devices) {
            const d = devices[k];
            if (d.kind !== kind || !d.dirty || busy[k]) continue;
            const raw = Math.round(d.value * d.max);
            update(k, { dirty: false });
            if (dryRun) {
                console.info("[delta] яркость (проверка): " + k + " → " + raw + "/" + d.max);
                continue;
            }
            busy[k] = true;
            const argv = kind === "ddc"
                ? ["ddcutil", "--bus", String(d.id), "setvcp", "10", String(raw), "--noverify"]
                : logindWorks
                    ? ["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1/session/auto",
                       "org.freedesktop.login1.Session", "SetBrightness", "ssu", "backlight", d.id, String(raw)]
                    : ["brightnessctl", "-q", "-d", d.id, "set", String(raw)];
            const name = k;
            run(argv, (code, out) => {
                root.busy[name] = false;
                if (code !== 0) {
                    console.warn("[delta] яркость " + name + ": " + out.trim());
                    if (kind === "backlight" && root.logindWorks) {
                        // нет logind-сессии (например, запуск не из greetd) — brightnessctl
                        root.logindWorks = false;
                        root.update(name, { dirty: true });
                    }
                }
                // пока команда шла, ползунок мог уехать дальше
                if (root.devices[name] && root.devices[name].dirty) root.flush(kind);
            });
        }
    }

    Timer { id: blTimer; interval: 30; onTriggered: root.flush("backlight") }
    Timer { id: ddcTimer; interval: 300; onTriggered: root.flush("ddc") }

    // --- поиск устройств ---------------------------------------------------

    function internalOutput() {
        const m = Displays.monitors.find(x => x.internal);
        return m ? m.name : "";
    }

    function scanBacklight() {
        run(["sh", "-c", 'for d in /sys/class/backlight/*; do [ -r "$d/max_brightness" ] && echo "${d##*/} $(cat "$d/brightness") $(cat "$d/max_brightness")"; done; true'], (code, out) => {
            const line = out.split("\n").find(l => l.split(" ").length === 3);
            if (!line) return;
            const [id, cur, max] = line.split(" ");
            const out1 = root.internalOutput() || "internal";
            const next = Object.assign({}, root.devices);
            for (const k in next) if (next[k].kind === "backlight") delete next[k];
            next[out1] = { kind: "backlight", id: id, max: parseInt(max), value: parseInt(cur) / Math.max(1, parseInt(max)), dirty: false };
            root.devices = next;
        });
    }

    // ddcutil detect --terse:
    //   Display 1
    //      I2C bus:          /dev/i2c-4
    //      DRM connector:    card1-HDMI-A-1
    function scanDdc() {
        if (ddcScanning) return;
        ddcScanning = true;
        run(["ddcutil", "detect", "--terse"], (code, out) => {
            const found = [];
            let cur = null;
            for (const raw of out.split("\n")) {
                const l = raw.trim();
                if (/^Display \d+/.test(l)) { cur = {}; found.push(cur); }
                else if (/^Invalid display/.test(l)) cur = null;
                else if (cur && /^I2C bus:/.test(l)) cur.bus = parseInt((/i2c-(\d+)/.exec(l) || [])[1]);
                else if (cur && /^DRM[_ ]connector:/.test(l)) cur.output = l.replace(/^DRM[_ ]connector:\s*/, "").replace(/^card\d+-/, "");
            }
            root.readDdc(found.filter(d => d.output && !isNaN(d.bus)), {});
        });
    }
    property bool ddcScanning: false

    // по одному монитору за раз: ddcutil не любит параллельной работы с шиной
    function readDdc(list, acc) {
        if (list.length === 0) {
            ddcScanning = false;
            const next = Object.assign({}, devices);
            for (const k in next) if (next[k].kind === "ddc" && !acc[k]) delete next[k];
            for (const k in acc) if (!(next[k] && next[k].dirty)) next[k] = acc[k];
            devices = next;
            cacheFile.setText(JSON.stringify(acc) + "\n");
            return;
        }
        const d = list[0];
        run(["ddcutil", "--bus", String(d.bus), "getvcp", "10", "--terse"], (code, out) => {
            // "VCP 10 C 70 100"
            const m = /VCP 10 C (\d+) (\d+)/.exec(out);
            if (code === 0 && m && parseInt(m[2]) > 0)
                acc[d.output] = { kind: "ddc", id: d.bus, max: parseInt(m[2]), value: parseInt(m[1]) / parseInt(m[2]), dirty: false };
            root.readDdc(list.slice(1), acc);
        });
    }

    // Кеш прошлого поиска: ползунки внешних мониторов есть сразу после входа,
    // а ddcutil detect (секунды) уточняет их в фоне.
    FileView {
        id: cacheFile
        path: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/delta/ddc.json"
        blockLoading: true
        atomicWrites: true
        onLoaded: {
            if (Displays.mock) return;
            try {
                const c = JSON.parse(text());
                const next = Object.assign({}, root.devices);
                for (const k in c) if (!next[k] && c[k].kind === "ddc") next[k] = c[k];
                root.devices = next;
            } catch (e) {}
        }
    }

    function loadMock() {
        const next = {};
        for (const m of Displays.monitors) {
            if (m.brightnessKind === "backlight" || m.brightnessKind === "ddc")
                next[m.name] = { kind: m.brightnessKind, id: m.name, max: 100, value: devices[m.name] ? devices[m.name].value : 0.7, dirty: false };
        }
        devices = next;
    }

    Connections {
        target: Displays
        function onSetKeyChanged() {
            if (Displays.mock) root.loadMock();
            else { root.scanBacklight(); rescanTimer.restart(); }
        }
    }
    // после подключения монитора DDC отвечает не сразу
    Timer { id: rescanTimer; interval: 3000; onTriggered: root.scanDdc() }

    Component { id: runComp; Run {} }
    function run(argv, done) { runComp.createObject(root, { argv: argv, done: done }); }

    Component.onCompleted: {
        if (Displays.mock) { loadMock(); return; }
        scanBacklight();
        rescanTimer.interval = 1500;
        rescanTimer.restart();
    }
}
