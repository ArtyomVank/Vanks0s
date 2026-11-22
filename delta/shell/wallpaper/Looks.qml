pragma Singleton

import QtQuick
import Quickshell
import qs.common
import "media.js" as Media

// Готовые виды и свои пресеты (Настройки → Пресеты): обои, часы и виджеты
// одним нажатием — и на столе, и на экране блокировки. Прежние обои, часы и
// раскладки виджетов сохраняются в looks.undo: «Вернуть как было» ставит их
// обратно.
//   list              [{ id, title, note, wall, clock, desktop, lock }]
//   apply(look)       поставить вид
//   undo()            вернуть то, что было до последнего вида или пресета
//   presets           свои пресеты (presets.list), не больше max
//   save()            сохранить то, что стоит сейчас, новым пресетом
//   applyPreset(p)    поставить пресет
//   remove(id)        удалить пресет
// clock — часы экрана блокировки (lock.clock.*) и виджетов часов в раскладках;
// desktop и lock — раскладки виджетов (widgets.desktop, widgets.lock), сетка
// от 17 колонок; поле входа на экране блокировки сетка ставит сама.
Singleton {
    id: root

    readonly property var list: [
        { id: "sunset-glass", title: "Закат", note: "«Длинные» часы стеклом, погода и календарь",
          wall: "acrylic-sunset",
          clock: { style: "tall", color: "white", tallKind: "mixed", tallWidth: 0.3, tallThick: 1 },
          desktop: [
              { id: "clock", c: 5, r: 1, w: 7, h: 4, bg: false },
              { id: "weather", c: 13, r: 1, w: 3, h: 2, bg: true },
              { id: "calendar", c: 1, r: 1, w: 3, h: 2, bg: true }
          ],
          lock: [
              { id: "clock", c: 4, r: 0, w: 9, h: 4, bg: false },
              { id: "weather", c: 0, r: 0, w: 3, h: 2, bg: true, mode: "block" },
              { id: "calendar", c: 14, r: 0, w: 3, h: 2, bg: true, mode: "month" }
          ] },
        { id: "dots", title: "Точки", note: "Часы из точек на чёрном, календарь и показатели ПК",
          wall: "dots-black",
          clock: { style: "dots", color: "white" },
          desktop: [
              { id: "clock", c: 4, r: 1, w: 9, h: 3, bg: false },
              { id: "calendar", c: 4, r: 4, w: 3, h: 2, bg: true },
              { id: "pc", c: 8, r: 4, w: 5, h: 2, bg: true }
          ],
          lock: [
              { id: "clock", c: 4, r: 1, w: 9, h: 3, bg: false },
              { id: "calendar", c: 0, r: 0, w: 3, h: 1, bg: true, mode: "day" },
              { id: "battery", c: 14, r: 0, w: 2, h: 1, bg: true, mode: "number" }
          ] },
        { id: "peak-glass", title: "Вершина", note: "Стеклянные часы, погода, восход и закат",
          wall: "peak",
          clock: { style: "ios", color: "glass" },
          desktop: [
              { id: "clock", c: 5, r: 1, w: 7, h: 3, bg: false },
              { id: "weather", c: 5, r: 4, w: 3, h: 2, bg: true },
              { id: "sun", c: 9, r: 4, w: 3, h: 2, bg: true }
          ],
          lock: [
              { id: "clock", c: 4, r: 0, w: 9, h: 3, bg: false },
              { id: "weather", c: 6, r: 3, w: 2, h: 1, bg: true, mode: "row" },
              { id: "calendar", c: 9, r: 3, w: 2, h: 1, bg: true, mode: "day" }
          ] },
        { id: "silk-stack", title: "Шёлк", note: "Часы столбиком акцентом, музыка и стрелки",
          wall: "waves-silk",
          clock: { style: "stack", color: "accent" },
          desktop: [
              { id: "clock", c: 1, r: 1, w: 5, h: 5, bg: false },
              { id: "music", c: 12, r: 1, w: 4, h: 2, bg: true },
              { id: "analog", c: 12, r: 4, w: 2, h: 2, bg: true }
          ],
          lock: [
              { id: "clock", c: 1, r: 0, w: 5, h: 4, bg: false },
              { id: "music", c: 12, r: 0, w: 4, h: 2, bg: true, mode: "wide" },
              { id: "analog", c: 12, r: 2, w: 2, h: 2, bg: true, mode: "date" }
          ] }
    ]

    readonly property var saved: Settings.get("looks.undo", null)
    readonly property string currentId: Settings.get("looks.current", "") || ""

    // виджеты часов в раскладке получают часы вида (у них свой style, color…)
    function withClock(items, clock) {
        return items.map(x => x.id === "clock" ? Object.assign({ mode: "" }, x, clock) : Object.assign({ mode: "" }, x));
    }

    // копия, а не ссылка на объект настроек: иначе снимок поменяется вместе с ними
    function copy(v) { return v === undefined || v === null ? null : JSON.parse(JSON.stringify(v)); }
    // что стоит сейчас: обои стола и экрана блокировки, часы, раскладки виджетов
    function snapshot() {
        return {
            wallpaper: { super: Settings.get("wallpaper.super", ""), path: Settings.get("wallpaper.path", ""),
                         video: Settings.get("wallpaper.video", false) === true, poster: Settings.get("wallpaper.poster", "") },
            lockWallpaper: Settings.get("lock.wallpaper", ""),
            clock: copy(Settings.get("clock", null)), lockClock: copy(Settings.get("lock.clock", null)),
            desktop: copy(Settings.get("widgets.desktop", [])) || [], lock: copy(Settings.get("widgets.lock", [])) || []
        };
    }
    function restore(s) {
        const w = s.wallpaper || {};
        Settings.set("wallpaper.video", w.video === true);
        Settings.set("wallpaper.super", w.super || "");
        Settings.set("wallpaper.path", w.path || "");
        if (w.video === true && w.poster) Settings.set("wallpaper.poster", w.poster);
        if (s.lockWallpaper !== undefined) Settings.set("lock.wallpaper", s.lockWallpaper || "");
        if (s.clock) Settings.set("clock", copy(s.clock));
        if (s.lockClock) Settings.set("lock.clock", copy(s.lockClock));
        Settings.set("widgets.desktop", copy(s.desktop) || []);
        Settings.set("widgets.lock", copy(s.lock) || []);
    }
    // что было — один раз, до первого вида подряд: «Вернуть» ведёт к своему
    function remember() { if (!saved) Settings.set("looks.undo", snapshot()); }

    function apply(look) {
        remember();
        const w = SuperWalls.flows.concat(SuperWalls.builtin).find(x => x.id === look.wall);
        if (w) SuperWalls.apply(w);
        for (const k in look.clock) Settings.set("lock.clock." + k, look.clock[k]);
        Settings.set("widgets.desktop", withClock(look.desktop, look.clock));
        Settings.set("widgets.lock", withClock(look.lock, look.clock));
        Settings.set("looks.current", look.id);
    }

    function undo() {
        const u = saved;
        if (!u) return;
        restore(u);
        Settings.set("looks.undo", null);
        Settings.set("looks.current", "");
    }

    // --- свои пресеты ---
    readonly property int max: 5
    readonly property var presets: Settings.get("presets.list", []) || []
    readonly property bool full: presets.length >= max

    function save() {
        if (full) return null;
        // «Пресет N» — наименьший свободный номер
        let n = 1;
        while (presets.some(p => p.name === "Пресет " + n)) n++;
        const p = Object.assign({ id: "p" + Date.now(), name: "Пресет " + n, time: Date.now() }, snapshot());
        Settings.set("presets.list", presets.concat([p]));
        Settings.set("looks.current", p.id);
        return p;
    }
    function applyPreset(p) {
        if (!p) return;
        remember();
        restore(p);
        Settings.set("looks.current", p.id);
    }
    function remove(id) {
        Settings.set("presets.list", presets.filter(p => p.id !== id));
        if (currentId === id) Settings.set("looks.current", "");
    }
    // обои пресета — живые: оживить их у оболочки
    function isFlow(p) {
        const id = p && p.wallpaper ? p.wallpaper.super : "";
        return !!id && SuperWalls.flows.some(x => x.id === id);
    }

    // обои стола и экрана блокировки пресета (у видео — кадр-заставка)
    function deskWall(p) {
        const w = p.wallpaper || {};
        return w.video === true || Media.isVideo(w.path || "") ? (w.poster || "") : (w.path || "");
    }
    function lockWall(p) { return p.lockWallpaper || deskWall(p); }
    // «Пресет 3» сохранён по-русски: номер оставляем, слово переводим
    function nameOf(p, word) { return String(p.name || "").replace(/^Пресет /, word + " "); }
    // «Настройки» — отдельный процесс: живые обои оживают у оболочки
    function introAtShell() { Quickshell.execDetached(["delta-shell", "ipc", "call", "shell", "wallpaperIntro"]); }
}
