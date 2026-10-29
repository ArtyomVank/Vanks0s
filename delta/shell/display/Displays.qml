pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.common
import qs.display.parts
import "edid.js" as Edid
import "layout.js" as L

// Мониторы: состояние из Hyprland, сохранённые профили и безопасное применение.
//
//   Displays.monitors          [{ name, description, key, modes, hdr, … }] — см. normalize()
//   Displays.configs()         { порт: cfg } — текущие параметры в виде, удобном для UI
//   Displays.apply(next, base) применить на лету и спросить «Оставить?»
//   Displays.keep() / revert() ответ на вопрос (или сам откат по таймеру)
//   Displays.primaryName       основной монитор (на нём доки)
//
// Сохранённые параметры — Settings `monitors` (поля как в delta-apply),
// монитор опознаётся по "desc:<описание из EDID>", поэтому переезд на другой
// порт ничего не ломает. Для каждого набора подключённых мониторов отдельно
// хранится раскладка (`display.layouts`): при подключении/отключении оболочка
// (manageProfiles) переписывает `monitors` раскладкой этого набора.
//
// Отладка без железа: DELTA_DISPLAYS_MOCK=/путь/monitors.json в формате
// `hyprctl monitors all -j` (+ необязательные поля "edid": "<hex>",
// "_brightness": "backlight" | "ddc"). Тогда в Hyprland ничего не пишется.
Singleton {
    id: root

    readonly property string mockPath: Quickshell.env("DELTA_DISPLAYS_MOCK") || ""
    readonly property bool mock: mockPath.length > 0
    // Целимся в тот экземпляр Hyprland, в котором запущены сами (во вложенной
    // сессии это вложенный), и передаём его явно через -i.
    readonly property string instance: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
    readonly property bool nested: (Quickshell.env("DELTA_NESTED") || "") !== ""
    // пробный режим «Настроек» вне вложенной сессии — мониторы не трогаем
    readonly property bool dryRun: Quickshell.env("DELTA_DRY_RUN") === "1" && !nested
    readonly property bool canWrite: !mock && !dryRun && instance.length > 0

    property var monitors: []
    property bool ready: false
    property var edids: ({})          // порт → разбор EDID (edid.js)
    // профили по наборам мониторов меняет только оболочка, не «Настройки»
    property bool manageProfiles: false

    readonly property var saved: Settings.get("monitors", [])
    readonly property string setKey: monitors.map(m => m.key).sort().join(" + ")

    // --- подтверждение новых параметров ---
    readonly property int timeout: 15
    property bool pending: false
    property int countdown: 0
    property string error: ""
    property var pendingSave: []      // записи для `monitors` после «Оставить»
    property string revertLua: ""
    property var mockBefore: null
    signal kept()
    signal reverted()

    // --- основной монитор ---
    readonly property string primarySetting: Settings.get("display.primary", "")
    readonly property string primaryName: {
        const on = monitors.filter(m => !m.disabled && !m.mirrorOf);
        if (on.some(m => m.name === primarySetting)) return primarySetting;
        const desc = Settings.get("display.primaryDesc", "");
        const byDesc = on.find(m => desc.length > 0 && m.description === desc);
        if (byDesc) return byDesc.name;
        const origin = on.find(m => m.x === 0 && m.y === 0);
        return origin ? origin.name : (on.length ? on[0].name : "");
    }

    function setPrimary(name) {
        const m = byName(name);
        if (!m) return;
        Settings.set("display.primary", m.name);
        Settings.set("display.primaryDesc", m.description);
    }

    // Авто-HDR для полноэкранных игр (render.cm_auto_hdr) — общий параметр
    // Hyprland. Сохраняется в display.autoHdr; сразу применяем и на лету,
    // чтобы не ждать, пока delta-apply научится его писать (см. отчёт).
    readonly property bool anyHdr: monitors.some(m => m.hdr.hdr)
    function setAutoHdr(on) {
        Settings.set("display.autoHdr", on);
        if (canWrite)
            run(["hyprctl", "-i", instance, "eval", "hl.config({ render = { cm_auto_hdr = " + (on ? 1 : 0) + " } })"], (code, out) => {
                if (code !== 0) console.warn("[delta] cm_auto_hdr: " + out.trim());
            });
    }

    function byName(name) { return monitors.find(m => m.name === name) || null; }
    function clone(v) { return v === undefined ? undefined : JSON.parse(JSON.stringify(v)); }

    // --- чтение -------------------------------------------------------------

    function isInternal(name) { return /^(eDP|LVDS|DSI)-/.test(name); }

    // JSON Hyprland → наш объект монитора
    function normalize(list) {
        const descCount = {};
        for (const m of list) descCount[m.description || ""] = (descCount[m.description || ""] || 0) + 1;
        const byId = {};
        for (const m of list) byId[String(m.id)] = m.name;
        return list.map(m => {
            const desc = String(m.description || "").trim();
            let modes = (m.availableModes || []).map(L.parseMode).filter(x => x !== null);
            if (modes.length === 0 && m.width > 0)
                modes = [{ w: m.width, h: m.height, hz: Math.round((m.refreshRate || 60) * 100) / 100 }];
            const mir = String(m.mirrorOf ?? "none");
            const e = edids[m.name] || (m.edid ? Edid.parse(m.edid) : null);
            return {
                id: m.id,
                name: m.name,
                description: desc,
                make: m.make || "",
                model: m.model || "",
                serial: m.serial || "",
                // по описанию, только если оно есть и не повторяется (два одинаковых монитора без серийника)
                key: desc.length > 0 && descCount[m.description] === 1 ? "desc:" + desc : m.name,
                width: m.width || 0,
                height: m.height || 0,
                refreshRate: Math.round((m.refreshRate || 0) * 100) / 100,
                x: m.x || 0,
                y: m.y || 0,
                scale: m.scale || 1,
                transform: m.transform || 0,
                vrrActive: m.vrr === true,
                disabled: m.disabled === true,
                mirrorOf: mir === "none" || mir === "" ? "" : (byId[mir] || mir),
                currentFormat: m.currentFormat || "",
                tenBit: /2101010/.test(m.currentFormat || ""),
                cmPreset: m.colorManagementPreset || "srgb",
                sdrBrightness: m.sdrBrightness ?? 1,
                sdrSaturation: m.sdrSaturation ?? 1,
                physicalWidth: m.physicalWidth || 0,
                physicalHeight: m.physicalHeight || 0,
                focused: m.focused === true,
                internal: isInternal(m.name),
                modes: modes,
                hdr: e ? e : { valid: false, hdr: false, hlg: false, wideColor: false, maxLuminance: 0, maxAvgLuminance: 0, minLuminance: 0 },
                brightnessKind: m._brightness || ""
            };
        });
    }

    property var rawList: []
    function setRaw(list) {
        // опрос раздела «Экран» приходит часто — без изменений ничего не пересчитываем
        if (ready && JSON.stringify(list) === JSON.stringify(rawList)) return;
        rawList = list;
        monitors = normalize(list);
        ready = true;
        // EDID читаем заново, только когда меняется состав портов
        const names = list.map(m => m.name).sort().join(",");
        if (!mock && names !== edidNames) { edidNames = names; readEdid(); }
    }
    property string edidNames: ""

    function refresh() {
        // мок читается один раз при запуске, дальше живёт в памяти (simulate)
        if (mock) return;
        run(["hyprctl", "-i", instance, "-j", "monitors", "all"], (code, out) => {
            if (code !== 0) { console.warn("[delta] hyprctl monitors: " + out.trim()); return; }
            try { setRaw(JSON.parse(out)); }
            catch (e) { console.warn("[delta] не разобрал hyprctl monitors: " + e); }
        });
    }

    function readEdid() {
        run(["delta-monitors", "edid"], (code, out) => {
            const map = {};
            for (const line of out.split("\n")) {
                const sp = line.indexOf(" ");
                if (sp > 0) map[line.slice(0, sp)] = Edid.parse(line.slice(sp + 1));
            }
            edids = map;
            monitors = normalize(rawList);
        });
    }

    // --- сохранённые записи и параметры для UI --------------------------------

    function matches(entry, m) {
        const k = String(entry.match ?? entry.output ?? "");
        if (k === m.key || k === m.name) return true;
        return k.startsWith("desc:") && m.description.length > 0 && m.description.startsWith(k.slice(5).trim());
    }
    function savedFor(m) { return (Array.isArray(saved) ? saved : []).find(e => e && matches(e, m)) || null; }

    readonly property var colorModes: ["srgb", "auto", "wide", "edid", "dcip3", "dp3", "adobe"]

    // cfg — то, что редактирует раздел: { name, key, enabled, mode, x, y, scale,
    // transform, vrr, mirror, hdr, sdrBrightness, sdrSaturation, tenBit, cm, icc }
    function configFor(m) {
        // применённое на лету, но ещё не сохранённое: Hyprland не сообщает
        // режим VRR (только «активен ли сейчас»), ICC и выбранный cm
        const s = Object.assign({}, savedFor(m) || {}, live[m.name] || {});
        let mode = { w: m.width, h: m.height, hz: m.refreshRate };
        if (m.disabled || m.width === 0) mode = L.parseMode(s.mode) || m.modes[0] || { w: 1920, h: 1080, hz: 60 };
        const near = L.nearestMode(m.modes, mode.w, mode.h, mode.hz);
        if (near) mode = near;
        const scales = L.validScales(mode.w, mode.h);
        const hdrOn = m.cmPreset === "hdr" || m.cmPreset === "hdredid";
        const cm = colorModes.indexOf(s.cm) !== -1 ? s.cm : (colorModes.indexOf(m.cmPreset) !== -1 ? m.cmPreset : "srgb");
        return {
            name: m.name,
            key: m.key,
            enabled: !m.disabled,
            mode: { w: mode.w, h: mode.h, hz: mode.hz },
            x: m.x,
            y: m.y,
            scale: L.nearestScale(scales, m.scale),
            transform: m.transform,
            vrr: typeof s.vrr === "number" ? Math.max(0, Math.min(3, s.vrr)) : (m.vrrActive ? 1 : 0),
            mirror: m.mirrorOf,
            hdr: hdrOn,
            sdrBrightness: Math.round((hdrOn ? m.sdrBrightness : (s.sdrBrightness ?? 1)) * 100) / 100,
            sdrSaturation: Math.round((hdrOn ? m.sdrSaturation : (s.sdrSaturation ?? 1)) * 100) / 100,
            tenBit: hdrOn || m.tenBit,
            cm: cm,
            icc: typeof s.icc === "string" ? s.icc : ""
        };
    }

    function configs() {
        const out = {};
        for (const m of monitors) out[m.name] = configFor(m);
        return out;
    }

    // cfg → запись Settings `monitors` (поля delta-apply)
    function entryFor(cfg) {
        if (!cfg.enabled) return { match: cfg.key, name: cfg.name, disabled: true };
        const e = {
            match: cfg.key,
            name: cfg.name,
            mode: L.modeString(cfg.mode),
            position: Math.round(cfg.x) + "x" + Math.round(cfg.y),
            scale: L.scaleValue(cfg.scale),
            transform: cfg.transform,
            vrr: cfg.vrr
        };
        if (cfg.mirror) e.mirror = cfg.mirror;
        if (cfg.hdr) {
            e.hdr = true;
            e.sdrBrightness = cfg.sdrBrightness;
            e.sdrSaturation = cfg.sdrSaturation;
        } else if (cfg.cm !== "srgb" || cfg.tenBit) {
            // delta-apply пишет bitdepth только вместе с cm
            e.cm = cfg.cm;
            if (cfg.tenBit) e.bitdepth = 10;
        }
        if (cfg.icc && cfg.icc.startsWith("/")) e.icc = cfg.icc;
        return e;
    }

    // Запись → hl.monitor(...) — так же, как это делает delta-apply, чтобы
    // применённое на лету совпало с тем, что потом будет в generated.lua.
    function lstr(s) { return JSON.stringify(String(s).replace(/[\u0000-\u001f\u007f]/g, "")); }
    function luaFor(e) {
        const f = ["output = " + lstr(e.match)];
        if (e.disabled) f.push("disabled = true");
        else {
            f.push("mode = " + lstr(e.mode), "position = " + lstr(e.position), "scale = " + e.scale,
                   "transform = " + e.transform, "vrr = " + e.vrr);
            if (e.mirror) f.push("mirror = " + lstr(e.mirror));
            if (e.hdr) f.push('cm = "hdr"', "bitdepth = 10", "sdrbrightness = " + e.sdrBrightness, "sdrsaturation = " + e.sdrSaturation);
            else if (e.cm) { f.push("cm = " + lstr(e.cm)); if (e.bitdepth === 10) f.push("bitdepth = 10"); }
            if (e.icc) f.push("icc = " + lstr(e.icc));
        }
        return "hl.monitor({ " + f.join(", ") + " })";
    }

    // Сначала включаем, потом выключаем: в любой момент хоть один экран горит.
    function scriptFor(entries) {
        const on = entries.filter(e => !e.disabled), off = entries.filter(e => e.disabled);
        return on.concat(off).map(luaFor).join("\n");
    }

    // Что не даст чёрного экрана: хотя бы один включённый монитор, который
    // ничего не повторяет; повтор только с включённого и без цепочек.
    function validate(next) {
        const list = Object.keys(next).map(k => next[k]);
        const shown = list.filter(c => c.enabled && !c.mirror);
        if (shown.length === 0) return "Должен остаться хотя бы один включённый экран, который ничего не повторяет.";
        for (const c of list) {
            if (!c.enabled || !c.mirror) continue;
            const src = next[c.mirror];
            if (!src || !src.enabled) return "Экран " + c.name + " повторяет выключенный монитор.";
            if (src.mirror) return "Нельзя повторять экран, который сам что-то повторяет.";
        }
        return "";
    }

    // --- применение ----------------------------------------------------------

    function apply(next, base) {
        if (pending) return false;
        error = validate(next);
        if (error) return false;
        const changed = Object.keys(next).filter(n => base[n] && JSON.stringify(next[n]) !== JSON.stringify(base[n]));
        if (changed.length === 0) return false;

        const newEntries = changed.map(n => entryFor(next[n]));
        const oldEntries = changed.map(n => entryFor(base[n]));
        const script = scriptFor(newEntries);
        revertLua = scriptFor(oldEntries);
        pendingSave = Object.keys(next).map(n => entryFor(next[n]));
        console.info("[delta] применяю мониторы:\n" + script);

        remember(next, changed);
        liveBefore = changed.map(n => base[n]);
        if (!canWrite) {
            // мок и пробный режим: изображаем Hyprland у себя в памяти
            mockBefore = clone(rawList);
            startCountdown();
            simulate(next);
            return true;
        }
        // сторож откатит, даже если этот процесс не доживёт до конца отсчёта
        Quickshell.execDetached(["delta-monitors", "guard", String(timeout + 5), revertLua]);
        startCountdown();
        run(["hyprctl", "-i", instance, "eval", script], (code, out) => {
            if (code !== 0 || /^error/m.test(out)) {
                error = "Hyprland не принял параметры: " + out.trim().split("\n")[0];
                revert();
                return;
            }
            settleTimer.restart();
        });
        return true;
    }

    function startCountdown() {
        countdown = timeout;
        pending = true;
        countdownTimer.restart();
    }

    function keep() {
        if (!pending) return;
        countdownTimer.stop();
        pending = false;
        if (!mock) Quickshell.execDetached(["delta-monitors", "cancel"]);
        save(pendingSave);
        kept();
    }

    function revert() {
        if (!pending) return;
        countdownTimer.stop();
        pending = false;
        if (canWrite) {
            Quickshell.execDetached(["delta-monitors", "cancel"]);
            run(["hyprctl", "-i", instance, "eval", revertLua], (code, out) => {
                if (code !== 0) console.warn("[delta] откат не удался: " + out.trim());
                settleTimer.restart();
            });
        }
        const back = {};
        for (const c of liveBefore) back[c.name] = c;
        remember(back, Object.keys(back));
        if (!canWrite && mockBefore) {
            setRaw(mockBefore);
            mockBefore = null;
        }
        reverted();
    }

    // Записать подтверждённые параметры: записи этого набора мониторов плюс
    // записи мониторов, которых сейчас нет (их правила пригодятся при подключении).
    function save(entries) {
        if (dryRun) { console.info("[delta] пробный режим: monitors не записываю"); return; }
        const here = monitors;
        const foreign = (Array.isArray(saved) ? saved : []).filter(e => e && !here.some(m => matches(e, m)));
        Settings.set("monitors", entries.concat(foreign));
        const layouts = clone(Settings.get("display.layouts", {})) || {};
        layouts[setKey] = entries;
        Settings.set("display.layouts", layouts);
    }

    // В моке: как будто Hyprland применил параметры.
    function simulate(next) {
        const list = clone(rawList);
        const ids = {};
        for (const m of list) ids[m.name] = m.id;
        for (const m of list) {
            const c = next[m.name];
            if (!c) continue;
            m.disabled = !c.enabled;
            m.width = c.mode.w; m.height = c.mode.h; m.refreshRate = c.mode.hz;
            m.x = c.x; m.y = c.y;
            m.scale = c.scale; m.transform = c.transform;
            m.vrr = c.vrr === 1;
            m.mirrorOf = c.mirror ? String(ids[c.mirror]) : "none";
            m.colorManagementPreset = c.hdr ? "hdr" : c.cm;
            m.currentFormat = c.hdr || c.tenBit ? "XBGR2101010" : "XRGB8888";
            m.sdrBrightness = c.sdrBrightness; m.sdrSaturation = c.sdrSaturation;
        }
        setRaw(list);
    }

    property var live: ({})
    property var liveBefore: []
    function remember(cfgs, names) {
        const l = Object.assign({}, live);
        for (const n of names) {
            const c = cfgs[n];
            if (c) l[n] = { vrr: c.vrr, cm: c.cm, icc: c.icc, sdrBrightness: c.sdrBrightness, sdrSaturation: c.sdrSaturation };
        }
        live = l;
    }

    // --- профили по набору мониторов ------------------------------------------

    function syncProfile() {
        if (!manageProfiles || pending || monitors.length === 0 || dryRun) return;
        const layouts = Settings.get("display.layouts", {}) || {};
        const want = layouts[setKey];
        const list = Array.isArray(saved) ? saved : [];
        const current = monitors.map(m => savedFor(m)).filter(e => e);
        if (Array.isArray(want) && want.length > 0) {
            if (JSON.stringify(current) !== JSON.stringify(want)) {
                console.info("[delta] набор мониторов «" + setKey + "»: восстанавливаю сохранённую раскладку");
                const foreign = list.filter(e => e && !monitors.some(m => matches(e, m)));
                Settings.set("monitors", want.concat(foreign));
            }
            return;
        }
        // Раскладки нет. Если по старым записям все подключённые экраны
        // выключены (например, ноутбук закрыли с отключённым внутренним) —
        // снимаем «выключен», иначе останется чёрный экран.
        const shown = monitors.filter(m => { const e = savedFor(m); return !(e && e.disabled) && !(e && e.mirror); });
        if (shown.length === 0) {
            console.warn("[delta] все подключённые экраны выключены в настройках — включаю");
            Settings.set("monitors", list.map(e => e && e.disabled && monitors.some(m => matches(e, m))
                ? { match: e.match, name: e.name } : e));
        }
    }

    // --- служебное -------------------------------------------------------------

    Component { id: runComp; Run {} }
    function run(argv, done) { runComp.createObject(root, { argv: argv, done: done }); }

    Timer { id: refreshTimer; interval: 300; onTriggered: root.refresh() }
    // после смены режима монитор переподключается не сразу
    Timer { id: settleTimer; interval: 900; onTriggered: root.refresh() }
    Timer { id: profileTimer; interval: 1500; onTriggered: root.syncProfile() }
    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown -= 1;
            if (root.countdown <= 0) root.revert();
        }
    }

    Connections {
        target: Hyprland
        enabled: !root.mock
        function onRawEvent(event) {
            const n = event.name;
            if (n === "monitoradded" || n === "monitorremoved" || n === "monitoraddedv2" || n === "monitorremovedv2") {
                refreshTimer.restart();
                profileTimer.restart();
            } else if (n === "configreloaded") {
                refreshTimer.restart();
            }
        }
    }

    FileView {
        id: mockFile
        path: root.mockPath
        blockLoading: true
        onLoaded: {
            try { root.setRaw(JSON.parse(text())); }
            catch (e) { console.warn("[delta] мок мониторов не разобран: " + e); }
        }
    }

    Component.onCompleted: if (!mock) refresh()

    // Окно «Оставить эти параметры?» — на всех экранах сразу: тот, где открыты
    // «Настройки», мог погаснуть или стать повтором другого.
    LazyLoader {
        active: root.pending
        KeepDialog {}
    }
}
