pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.common
import qs.common.ui

// Сетка виджетов — рабочий стол (place: "desktop") или экран блокировки
// (place: "lock"; назвать свойство «layer» нельзя — у Item это FINAL-свойство). Самодостаточна: сама читает и пишет widgets.<place>,
// в редакторе (editing) показывает сетку, панель редактора и обрабатывает
// перетаскивание. Заполняет родителя:
//     Loader { anchors.fill: parent; source: Quickshell.shellDir + "/widgets/WidgetGrid.qml"
//              onLoaded: { item.place = "lock"; item.editing = Qt.binding(() => ShellState.lockEditing) } }
//
// Сетка подстраивается под экран: клетки квадратные, их не меньше 17×9
// (как в концепте), позиции хранятся в клетках — {id, c, r, w, h, bg, mode, style, color}.
Item {
    id: root

    property string place: "desktop"
    property bool editing: false
    // «Готово» или Esc; ShellState.widgetEditing / lockEditing сбрасываются здесь же
    signal finished()

    readonly property string key: "widgets." + (place === "lock" ? "lock" : "desktop")

    // ---------- геометрия сетки ----------
    // поля как в концепте (1440×900: слева 40, сверху 70 под док, снизу 110)
    readonly property real marginX: width * 0.028
    readonly property real marginTop: height * 0.078
    readonly property real marginBottom: height * 0.122
    readonly property real availW: Math.max(1, width - marginX * 2)
    readonly property real availH: Math.max(1, height - marginTop - marginBottom)
    readonly property real cell: Math.max(24, Math.floor(Math.min(availW / 17, availH / 9)))
    readonly property int cols: Math.max(17, Math.floor(availW / cell))
    readonly property int rows: Math.max(9, Math.floor(availH / cell))
    readonly property real gx: Math.round((width - cols * cell) / 2)
    readonly property real gy: Math.round(marginTop + (availH - rows * cell) / 2)
    // масштаб относительно клетки концепта (80 px) — для рамок, «×», отступов
    readonly property real unit: cell / 80
    readonly property real inset: 4 * unit

    function box(c, r, w, h) {
        return { x: gx + c * cell + inset, y: gy + r * cell + inset, w: w * cell - inset * 2, h: h * cell - inset * 2 };
    }

    // ---------- данные ----------
    readonly property var raw: Settings.get(key, [])
    readonly property var items: normalize(raw)
    // прямоугольники виджетов — для маски ввода окна
    readonly property var boxes: items.map(it => box(it.c, it.r, it.w, it.h))

    function clampInt(v, lo, hi) { return Math.max(lo, Math.min(hi, Math.round(Number(v) || 0))); }

    function normalize(list) {
        const out = [], seen = {};
        for (const x of Array.isArray(list) ? list : []) {
            if (!x || typeof x.id !== "string" || seen[x.id] || !WidgetTypes.available(place, x.id)) continue;
            seen[x.id] = true;
            const t = WidgetTypes.info(place, x.id);
            const mode = t.modes.some(m => m[0] === x.mode) ? x.mode : WidgetTypes.defaultMode(place, x.id);
            const lim = WidgetTypes.limits(place, x.id, mode);
            const w = clampInt(x.w ?? t.def[0], lim.min[0], Math.min(lim.max[0], cols));
            const h = clampInt(x.h ?? t.def[1], lim.min[1], Math.min(lim.max[1], rows));
            // сетка на другом мониторе могла быть шире — прижимаем к краю
            const c = clampInt(x.c, 0, cols - w), r = clampInt(x.r, 0, rows - h);
            out.push(Object.assign({}, x, { c: c, r: r, w: w, h: h, mode: mode, bg: x.bg !== false }));
        }
        return out;
    }

    function find(id) { return items.find(x => x.id === id) || null; }

    // запись: правим «сырой» список, чтобы не потерять скрытые виджеты (батарея без батареи)
    function save(update) {
        const list = Settings.clone(Array.isArray(raw) ? raw : []) || [];
        update(list);
        Settings.set(key, list);
    }
    function patch(id, changes) {
        save(list => {
            const i = list.findIndex(x => x && x.id === id);
            const cur = find(id) || {};
            if (i >= 0) list[i] = Object.assign({}, list[i], cur, changes);
        });
    }

    // свободно ли место; other — переопределения позиций {id: {c, r, w, h}}
    function fits(id, c, r, w, h, other) {
        if (c < 0 || r < 0 || c + w > cols || r + h > rows) return false;
        for (const o of items) {
            if (o.id === id) continue;
            const p = other && other[o.id] ? other[o.id] : o;
            if (c < p.c + p.w && p.c < c + w && r < p.r + p.h && p.r < r + h) return false;
        }
        return true;
    }
    function overlapping(id, c, r, w, h) {
        return items.filter(o => o.id !== id && c < o.c + o.w && o.c < c + w && r < o.r + o.h && o.r < r + h);
    }

    // место для нового виджета: рабочий стол — сверху справа, как в концепте;
    // экран блокировки — ниже часов, ближе к центру
    function findSpot(id, w, h) {
        if (place === "lock") {
            const cs = [];
            for (let c = 0; c <= cols - w; c++) cs.push(c);
            cs.sort((a, b) => Math.abs(a + w / 2 - cols / 2) - Math.abs(b + w / 2 - cols / 2));
            for (let r = Math.min(4, rows - h); r <= rows - h; r++)
                for (const c of cs) if (fits(id, c, r, w, h)) return { c: c, r: r };
            for (let r = 0; r < Math.min(4, rows - h); r++)
                for (const c of cs) if (fits(id, c, r, w, h)) return { c: c, r: r };
            return null;
        }
        for (let r = 0; r <= rows - h; r++)
            for (let c = cols - w; c >= 0; c--) if (fits(id, c, r, w, h)) return { c: c, r: r };
        return null;
    }
    // ближайшее к (c, r) свободное место
    function nearestSpot(id, w, h, c0, r0) {
        let best = null, bestD = Infinity;
        for (let r = 0; r <= rows - h; r++)
            for (let c = 0; c <= cols - w; c++) {
                const d = (c - c0) * (c - c0) + (r - r0) * (r - r0);
                if (d < bestD && fits(id, c, r, w, h)) { best = { c: c, r: r }; bestD = d; }
            }
        return best;
    }

    // ---------- выбор и подсказки ----------
    property string sel: ""
    property string caption: ""
    function say(text) { caption = text; captionTimer.restart(); }
    Timer { id: captionTimer; interval: 3500; onTriggered: root.caption = "" }

    function select(id) { sel = find(id) ? id : ""; }
    function nameOf(id) { const t = WidgetTypes.info(place, id); return t ? t.name : id; }

    onEditingChanged: {
        drag = null;
        if (editing) {
            sel = find(pendingSel) ? pendingSel : find("clock") ? "clock" : "";
            pendingSel = "";
            forceActiveFocus();
        } else {
            sel = "";
        }
    }
    property string pendingSel: ""

    function finish() {
        drag = null;
        if (place === "lock") ShellState.lockEditing = false;
        else ShellState.widgetEditing = false;
        finished();
    }
    // долгое нажатие на виджет вне редактора
    function requestEdit(id) {
        if (place === "lock") return;
        pendingSel = id;
        ShellState.widgetEditing = true;
    }

    // ---------- действия редактора (их же зовёт IPC в dev-widgets.qml) ----------
    function add(id) {
        if (find(id) || !WidgetTypes.available(place, id)) return false;
        const t = WidgetTypes.info(place, id), mode = WidgetTypes.defaultMode(place, id);
        const lim = WidgetTypes.limits(place, id, mode);
        const w = Math.max(t.def[0], lim.min[0]), h = Math.max(t.def[1], lim.min[1]);
        const spot = findSpot(id, w, h);
        if (!spot) { say("На сетке нет места для «" + t.name + "»"); return false; }
        const it = { id: id, c: spot.c, r: spot.r, w: w, h: h, bg: id !== "clock" && id !== "bars" };
        if (mode) it.mode = mode;
        save(list => {
            const i = list.findIndex(x => x && x.id === id);
            if (i >= 0) list.splice(i, 1);
            list.push(it);
        });
        sel = id;
        return true;
    }
    function remove(id) {
        save(list => {
            const i = list.findIndex(x => x && x.id === id);
            if (i >= 0) list.splice(i, 1);
        });
        if (sel === id) sel = "";
    }
    function toggle(id) { if (find(id)) remove(id); else add(id); }

    function resizeTo(id, w, h) {
        const it = find(id);
        if (!it) return false;
        const lim = WidgetTypes.limits(place, id, it.mode);
        w = Math.max(lim.min[0], Math.min(lim.max[0], Math.round(w)));
        h = Math.max(lim.min[1], Math.min(lim.max[1], Math.round(h)));
        if (!fits(id, it.c, it.r, w, h)) {
            // не влезает на месте — ищем рядом, а не отказываем сразу
            const spot = nearestSpot(id, w, h, it.c, it.r);
            if (!spot) { say("Для такого размера не хватает места"); return false; }
            patch(id, { c: spot.c, r: spot.r, w: w, h: h });
            return true;
        }
        patch(id, { w: w, h: h });
        return true;
    }
    function setMode(id, mode) {
        const it = find(id);
        if (!it) return;
        const lim = WidgetTypes.limits(place, id, mode);
        const w = Math.max(it.w, lim.min[0]), h = Math.max(it.h, lim.min[1]);
        let spot = { c: it.c, r: it.r };
        if (!fits(id, it.c, it.r, w, h)) {
            spot = nearestSpot(id, w, h, it.c, it.r);
            if (!spot) { say("Не хватает места для этого режима"); return; }
        }
        patch(id, { mode: mode, c: spot.c, r: spot.r, w: w, h: h });
    }
    function setBg(id, on) { patch(id, { bg: !!on }); }
    function setStyle(id, style) { patch(id, { style: style }); }
    function setColor(id, color) { patch(id, { color: color }); }
    function setOpacity(id, v) { patch(id, { opacity: Math.round(v * 100) / 100 }); }
    function setTallWidth(id, v) { patch(id, { tallWidth: Math.round(v * 100) / 100 }); }
    function moveTo(id, c, r) {
        const it = find(id);
        if (!it) return;
        beginDrag("move", id);
        updateDrag((c - it.c) * cell, (r - it.r) * cell);
        endDrag();
    }

    // ---------- перетаскивание ----------
    // { type: "move" | "resize", id, dx, dy } — смещение указателя в пикселях
    property var drag: null
    readonly property var plan: drag ? makePlan(drag) : null

    function beginDrag(type, id) { if (editing && find(id)) drag = { type: type, id: id, dx: 0, dy: 0 }; }
    function updateDrag(dx, dy) { if (drag) drag = { type: drag.type, id: drag.id, dx: dx, dy: dy }; }
    function cancelDrag() { drag = null; }

    function makePlan(d) {
        const it = find(d.id);
        if (!it) return null;
        if (d.type === "resize") {
            const lim = WidgetTypes.limits(place, it.id, it.mode);
            const w = Math.max(lim.min[0], Math.min(lim.max[0], cols - it.c, Math.round(it.w + d.dx / cell)));
            const h = Math.max(lim.min[1], Math.min(lim.max[1], rows - it.r, Math.round(it.h + d.dy / cell)));
            return { c: it.c, r: it.r, w: w, h: h, ok: fits(it.id, it.c, it.r, w, h), swap: null };
        }
        const c = Math.max(0, Math.min(cols - it.w, Math.round(it.c + d.dx / cell)));
        const r = Math.max(0, Math.min(rows - it.h, Math.round(it.r + d.dy / cell)));
        if (fits(it.id, c, r, it.w, it.h)) return { c: c, r: r, w: it.w, h: it.h, ok: true, swap: null };
        // занято одним виджетом — меняемся местами, если он влезет на наше место
        const hits = overlapping(it.id, c, r, it.w, it.h);
        if (hits.length === 1) {
            const b = hits[0], moved = {};
            moved[it.id] = { c: c, r: r, w: it.w, h: it.h };
            if (fits(b.id, it.c, it.r, b.w, b.h, moved))
                return { c: c, r: r, w: it.w, h: it.h, ok: true, swap: { id: b.id, c: it.c, r: it.r } };
        }
        // иначе — ближайшее свободное место к точке броска
        const spot = nearestSpot(it.id, it.w, it.h, c, r);
        return spot ? { c: spot.c, r: spot.r, w: it.w, h: it.h, ok: true, swap: null, near: true }
                    : { c: c, r: r, w: it.w, h: it.h, ok: false, swap: null };
    }

    function endDrag() {
        const d = drag, p = plan;
        drag = null;
        if (!d || !p) return;
        // короткое касание — просто выбор
        if (Math.abs(d.dx) + Math.abs(d.dy) < 5) return;
        if (!p.ok) {
            say(d.type === "resize" ? "Для такого размера не хватает места" : "Сюда не помещается");
            return;
        }
        Sounds.play("drop", 60);
        if (d.type === "resize") { patch(d.id, { w: p.w, h: p.h }); return; }
        save(list => {
            for (let i = 0; i < list.length; i++) {
                const x = list[i];
                if (!x) continue;
                if (x.id === d.id) list[i] = Object.assign({}, x, find(x.id), { c: p.c, r: p.r });
                else if (p.swap && x.id === p.swap.id) list[i] = Object.assign({}, x, find(x.id), { c: p.swap.c, r: p.swap.r });
            }
        });
    }

    // ---------- клавиатура в редакторе ----------
    focus: editing
    Keys.onEscapePressed: if (editing) finish()
    Keys.onPressed: e => {
        if (!editing || !sel) return;
        const it = find(sel);
        const dx = e.key === Qt.Key_Left ? -1 : e.key === Qt.Key_Right ? 1 : 0;
        const dy = e.key === Qt.Key_Up ? -1 : e.key === Qt.Key_Down ? 1 : 0;
        if (e.key === Qt.Key_Delete) { remove(sel); e.accepted = true; return; }
        if (!dx && !dy) return;
        // стрелки двигают выбранный виджет, Shift+стрелки меняют размер
        if (e.modifiers & Qt.ShiftModifier) resizeTo(sel, it.w + dx, it.h + dy);
        else if (fits(sel, it.c + dx, it.r + dy, it.w, it.h)) patch(sel, { c: it.c + dx, r: it.r + dy });
        e.accepted = true;
    }

    // ---------- отрисовка ----------
    // пустое место в редакторе снимает выбор
    MouseArea {
        anchors.fill: parent
        enabled: root.editing
        onPressed: { root.sel = ""; root.forceActiveFocus(); }
    }

    GridOverlay {
        x: root.gx; y: root.gy
        width: root.cols * root.cell
        height: root.rows * root.cell
        cell: root.cell
        unit: root.unit
        shown: root.editing
    }

    // «тень» места, куда встанет виджет
    Rectangle {
        readonly property var b: root.plan ? root.box(root.plan.c, root.plan.r, root.plan.w, root.plan.h) : null
        visible: b !== null
        x: b ? b.x : 0; y: b ? b.y : 0
        width: b ? b.w : 0; height: b ? b.h : 0
        radius: 24 * root.unit
        color: Qt.rgba(c.r, c.g, c.b, 0.16)
        border.width: 2
        border.color: c
        readonly property color c: root.plan && !root.plan.ok ? Theme.accents[5] : Theme.accent
        Behavior on x { NumberAnimation { duration: 120 * Theme.anim.k } }
        Behavior on y { NumberAnimation { duration: 120 * Theme.anim.k } }
        Behavior on width { NumberAnimation { duration: 120 * Theme.anim.k } }
        Behavior on height { NumberAnimation { duration: 120 * Theme.anim.k } }
    }

    Repeater {
        // модель — только id: при правке настроек карточки не пересоздаются
        model: ScriptModel { values: root.items.map(x => x.id) }
        delegate: WidgetCard {
            id: card
            required property string modelData
            readonly property var it: root.find(modelData) || { id: modelData, c: 0, r: 0, w: 1, h: 1 }
            readonly property bool moving: root.drag !== null && root.drag.type === "move" && root.drag.id === modelData
            readonly property bool sizing: root.drag !== null && root.drag.type === "resize" && root.drag.id === modelData
            readonly property bool swapped: root.plan !== null && root.plan.swap !== null && root.plan.swap.id === modelData
            readonly property var b: sizing && root.plan ? root.box(it.c, it.r, root.plan.w, root.plan.h)
                                   : swapped ? root.box(root.plan.swap.c, root.plan.swap.r, it.w, it.h)
                                   : root.box(it.c, it.r, it.w, it.h)
            grid: root
            item: it
            place: root.place
            editing: root.editing
            selected: root.sel === modelData
            dragging: moving
            dragDx: moving ? root.drag.dx : 0
            dragDy: moving ? root.drag.dy : 0
            resizing: sizing
            bx: b.x; by: b.y; bw: b.w; bh: b.h
            unit: root.unit
        }
    }

    // Панель свёрстана под экран концепта (1440 px): на маленьком экране
    // (или при крупном масштабе) она уменьшается целиком, а не переносится в столбик.
    EditorBar {
        readonly property real k: Math.min(1, root.width / 1440)
        grid: root
        shown: root.editing
        transformOrigin: Item.Bottom
        scale: k
        x: (root.width - width) / 2
        y: shown ? root.height - height - 10 * root.unit : root.height + 20
        width: Math.min(root.width - 32, 880 * root.unit) / k
    }
}
