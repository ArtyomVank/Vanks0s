pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.common
import qs.common.ui
import qs.docks
import qs.docks.parts

// Сетка верхнего дока: 16 ячеек вдоль края, модуль занимает span ячеек.
//
// full — ячейки одинаковые и растянуты на всю длину;
// tiles — острова: модули, стоящие в сетке вплотную, — один стеклянный
// остров, внутри модули — чипы по размеру содержимого (соседние маленькие
// значки — колокольчик, раскладка, сеть, звук — в одном чипе); пустые
// клетки разделяют острова. Разброс (docks.top.spread, 0…1) раздвигает
// острова от центра к краям: 0 — вплотную по центру, 1 — первый у левого
// края, последний у правого, средние — по месту в сетке;
// compact — ячейки с модулем ужимаются до содержимого, пустые почти
// исчезают (док — пилюля по размеру содержимого). В режиме правки ячейки
// снова одинаковые и видны, модуль можно перетащить (занятая ячейка
// меняется местами), убрать крестиком.
Item {
    id: grid

    property string edge: "top"
    readonly property bool vertical: edge === "left" || edge === "right"
    property string length: "full"
    property real fullAlong: 1200
    property real thick: 48
    property bool editing: false
    property ShellScreen screen
    signal activated(string id, Item slot)

    readonly property var modules: DockService.modules
    readonly property int cells: DockService.cells
    readonly property real pad: 8
    readonly property bool compact: length === "compact"
    readonly property bool tiles: length === "tiles"
    readonly property bool uniform: (!compact && !tiles) || editing
    // в плитках клетка маленькая и фиксированная: модули «сжимаются»,
    // а не растягиваются на пол-экрана, как в полном доке
    readonly property real tileCell: 54
    readonly property real cw: tiles ? tileCell : compact ? 46 : (fullAlong - 2 * pad) / cells
    // ширина компактного и плиточного вида (Настройки → Доки → Ширина)
    readonly property real wk: DockService.topWidth

    // естественный размер модулей вдоль края (для compact)
    property var naturals: ({})
    function setNatural(id, v) {
        if (naturals[id] === v) return;
        const n = Object.assign({}, naturals);
        n[id] = v;
        naturals = n;
    }

    readonly property var sizes: {
        const out = [];
        if (uniform) { for (let i = 0; i < cells; i++) out.push(cw); return out; }
        for (let i = 0; i < cells; i++) out.push(-1);
        for (const m of modules) {
            // плитки: каждая ячейка фиксированная, ширина модуля = span × клетка;
            // компактный: по естественной ширине содержимого
            const per = tiles ? tileCell : (naturals[m.id] ?? 36) * wk / m.span;
            for (let c = m.cell; c < m.cell + m.span; c++) out[c] = per;
        }
        // пустые ячейки по краям не нужны, между модулями — маленький зазор
        const used = out.map(v => v >= 0);
        const first = used.indexOf(true), last = used.lastIndexOf(true);
        for (let i = 0; i < cells; i++)
            if (out[i] < 0) out[i] = first === -1 || i < first || i > last ? 0 : (tiles ? 8 : 4) * wk;
        return out;
    }
    readonly property var starts: {
        const out = [];
        let acc = pad;
        for (let i = 0; i < cells; i++) { out.push(acc); acc += sizes[i]; }
        out.push(acc);
        return out;
    }
    // --- острова: раскладка по содержимому ---
    readonly property bool tileLayout: tiles && !editing
    readonly property real tileSmall: 34      // значок без подписи
    readonly property real chipGap: 3         // между чипами острова
    readonly property real islandPad: 4       // от края острова до чипа
    readonly property real groupGap: 12       // между островами
    readonly property real islandAcross: 40
    readonly property real chipAcross: 32
    readonly property color acrylicChip: Theme.light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.09)
    readonly property real spread: Math.max(0, Math.min(1, Number(Settings.get("docks.top.spread", 0)) || 0))
    // без своего чипа: логотип, рабочие столы и часы лежат прямо на острове
    readonly property var bare: ["launcher", "workspaces", "calendar"]
    function isSmall(m) { return m.span === 1 && (naturals[m.id] ?? 36) <= 52; }
    // { start[c], end[c] — по ячейкам модулей; islands: [{ from, to }];
    //   groups: [{ from, to }] — общие чипы соседних значков; chip: { id: bool }; total }
    readonly property var tl: {
        const start = [], end = [], groups = [], islands = [], chip = {};
        const list = modules.filter(m => (naturals[m.id] ?? 36) > 0).slice().sort((a, b) => a.cell - b.cell);
        // 1) острова и раскладка внутри них. Пустых клеток нет совсем (так
        // стоят модули по умолчанию) — часы сами становятся островом посередине.
        // Скрытые сейчас модули (пустой трей, нет батареи) клетки всё равно занимают.
        const occ = [];
        for (const m of modules) for (let c = m.cell; c < m.cell + m.span; c++) occ[c] = true;
        const firstC = modules.reduce((a, m) => Math.min(a, m.cell), cells);
        const lastC = modules.reduce((a, m) => Math.max(a, m.cell + m.span - 1), -1);
        let gapless = true;
        for (let c = firstC; c <= lastC; c++) if (!occ[c]) gapless = false;
        function joined(a, b) {
            for (let c = a.cell + a.span; c < b.cell; c++) if (!occ[c]) return false;
            return !(gapless && (a.id === "calendar" || b.id === "calendar"));
        }
        let isl = null, prev = null;
        for (const m of list) {
            const touching = prev !== null && joined(prev, m);
            if (!touching) { isl = { mods: [], w: islandPad * wk, first: m.cell, last: m.cell }; islands.push(isl); }
            const small = isSmall(m);
            const together = touching && small && isSmall(prev);
            if (touching && !together) isl.w += chipGap * wk;
            const w = (small ? tileSmall : Math.max(48, (naturals[m.id] ?? 36) + 6)) * wk;
            isl.mods.push({ m: m, off: isl.w, w: w, small: small, together: together });
            isl.w += w;
            isl.last = m.cell + m.span - 1;
            prev = m;
        }
        for (const i of islands) i.w += islandPad * wk;
        // 2) где стоят острова: разброс раздвигает их от центра к краям
        const gap = groupGap * wk;
        const packed = islands.reduce((a, i) => a + i.w, 0) + Math.max(0, islands.length - 1) * gap + 2 * pad;
        const W = Math.max(packed, packed + (fullAlong - packed) * spread);
        const n = islands.length;
        const xs = islands.map((i, k) => n === 1 ? (W - i.w) / 2 : k === 0 ? pad : k === n - 1 ? W - pad - i.w
            : (i.first + i.last + 1) / 2 / cells * W - i.w / 2);
        for (let k = 1; k < n; k++) xs[k] = Math.max(xs[k], xs[k - 1] + islands[k - 1].w + gap);
        for (let k = n - 2; k >= 0; k--) xs[k] = Math.min(xs[k], xs[k + 1] - gap - islands[k].w);
        // 3) ячейки, чипы и общие чипы маленьких значков
        const rects = [];
        for (let k = 0; k < n; k++) {
            const i = islands[k], x = xs[k];
            rects.push({ from: x, to: x + i.w });
            let group = null;
            for (const e of i.mods) {
                const a = x + e.off;
                for (let c = e.m.cell; c < e.m.cell + e.m.span; c++) {
                    start[c] = a + (c - e.m.cell) * e.w / e.m.span;
                    end[c] = a + (c - e.m.cell + 1) * e.w / e.m.span;
                }
                if (e.together) { group.to = a + e.w; group.n++; }
                else if (e.small) { group = { from: a, to: a + e.w, n: 1 }; groups.push(group); }
                else group = null;
                // один модуль на острове — сам остров и есть чип
                chip[e.m.id] = i.mods.length > 1 && bare.indexOf(e.m.id) === -1;
            }
        }
        return { start: start, end: end, islands: rects, groups: groups.filter(g => g.n > 1), chip: chip, total: W };
    }

    // --- появление островов: сначала средний, из него в стороны — остальные ---
    property bool sidesOut: true      // TopDock: средний остров уже на месте
    property real sideT: sidesOut ? 1 : 0
    Behavior on sideT {
        NumberAnimation {
            duration: (grid.sidesOut ? 640 : 180) * Theme.anim.k
            easing.type: grid.sidesOut ? Easing.OutBack : Easing.InCubic
            easing.overshoot: 0.7
        }
    }
    // средний — ближайший к середине дока; с одним островом выходить неоткуда
    readonly property int midIsle: {
        const rects = tl.islands, c = tl.total / 2;
        let best = -1, dist = Infinity;
        for (let k = 0; k < rects.length; k++) {
            const d = Math.abs((rects[k].from + rects[k].to) / 2 - c);
            if (d < dist) { dist = d; best = k; }
        }
        return best;
    }
    readonly property bool isleIntro: tileLayout && tl.islands.length > 1
    readonly property real midAlong: isleIntro ? tl.islands[midIsle].to - tl.islands[midIsle].from : 0
    readonly property real midOffset: isleIntro ? (tl.islands[midIsle].from + tl.islands[midIsle].to - tl.total) / 2 : 0
    function isleAt(p) {
        return tl.islands.findIndex(r => p >= r.from - 0.5 && p < r.to + 0.5);
    }
    function isSide(p) {
        const k = isleAt(p);
        return k !== -1 && k !== midIsle;
    }
    // сдвиг к среднему острову и видимость того, что стоит на месте p
    function isleShift(p) {
        if (!isleIntro || sideT === 1) return 0;
        const k = isleAt(p);
        if (k === -1 || k === midIsle) return 0;
        const m = tl.islands[midIsle], r = tl.islands[k];
        return (1 - sideT) * ((m.from + m.to) - (r.from + r.to)) / 2;
    }
    function isleAlpha(p, from) {
        if (!isleIntro || sideT >= 1 || !isSide(p)) return 1;
        return Math.max(0, Math.min(1, (sideT - from) / 0.3));
    }

    readonly property real implicitAlong: tileLayout ? Math.max(80, tl.total)
        : compact && !editing ? Math.max(80, starts[cells] + pad) : ((compact || tiles) ? cells * cw + 2 * pad : fullAlong)

    width: vertical ? thick : implicitAlong
    height: vertical ? implicitAlong : thick

    function cellAt(pos) {
        return Math.max(0, Math.min(cells - 1, Math.floor((pos - pad) / cw)));
    }
    // прямоугольник модуля в координатах сетки (для меню)
    function slotFor(id) {
        for (let i = 0; i < slots.count; i++) {
            const s = slots.itemAt(i);
            if (s && s.mid === id) return s;
        }
        return null;
    }

    // острова: общее стекло под модулями, стоящими вплотную
    // (их прямоугольники нужны и маске ввода дока — islandItems)
    property var islandItems: []
    Repeater {
        id: islandRep
        model: grid.tileLayout ? grid.tl.islands : []
        onItemAdded: grid.islandItems = Array.from({ length: count }, (_, i) => itemAt(i)).filter(x => x)
        onItemRemoved: Qt.callLater(() => grid.islandItems = Array.from({ length: islandRep.count }, (_, i) => islandRep.itemAt(i)).filter(x => x))
        delegate: Rectangle {
            id: isle
            required property var modelData
            x: grid.vertical ? (grid.thick - grid.islandAcross) / 2 : modelData.from
            y: grid.vertical ? modelData.from : (grid.thick - grid.islandAcross) / 2
            width: grid.vertical ? grid.islandAcross : modelData.to - modelData.from
            height: grid.vertical ? modelData.to - modelData.from : grid.islandAcross
            radius: grid.islandAcross / 2
            color: DockService.topGlass
            border.width: Theme.liquid || Theme.acrylic ? 0 : 1
            border.color: Theme.line
            Sheen { radius: parent.radius; strength: 0.9 }
            // боковые выходят из-под среднего
            readonly property real along0: modelData.from
            readonly property real squeeze: grid.isleIntro && grid.isSide(along0) ? 0.35 + 0.65 * Math.min(1, grid.sideT) : 1
            z: grid.isleIntro && !grid.isSide(along0) ? 0.5 : 0
            opacity: grid.isleAlpha(along0, 0)
            // остров вздрагивает вместе с модулями
            transform: [
                Translate { x: grid.vertical ? 0 : grid.isleShift(isle.along0); y: grid.vertical ? grid.isleShift(isle.along0) : 0 },
                Scale {
                    origin.x: isle.width / 2; origin.y: isle.height / 2
                    xScale: grid.vertical ? 1 : isle.squeeze; yScale: grid.vertical ? isle.squeeze : 1
                },
                Scale { origin.x: isle.width / 2; origin.y: isle.height / 2; xScale: 1 + ij.value * 0.3; yScale: 1 - ij.value }
            ]
            Spring { id: ij; stiffness: 280; damping: 10 }
            Connections {
                target: ShellState
                function onDockPoked(dockId, strength) { if (dockId === "top") ij.kick(0.7 * strength); }
            }
            Behavior on x { NumberAnimation { duration: 320 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
            Behavior on y { NumberAnimation { duration: 320 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
            Behavior on width { NumberAnimation { duration: 320 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
            Behavior on height { NumberAnimation { duration: 320 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        }
    }
    // общий чип соседних маленьких значков
    Repeater {
        model: grid.tileLayout ? grid.tl.groups : []
        delegate: Rectangle {
            required property var modelData
            opacity: grid.isleAlpha(modelData.from, 0.6)
            transform: Translate {
                x: grid.vertical ? 0 : grid.isleShift(modelData.from)
                y: grid.vertical ? grid.isleShift(modelData.from) : 0
            }
            x: grid.vertical ? (grid.thick - grid.chipAcross) / 2 : modelData.from
            y: grid.vertical ? modelData.from : (grid.thick - grid.chipAcross) / 2
            width: grid.vertical ? grid.chipAcross : modelData.to - modelData.from
            height: grid.vertical ? modelData.to - modelData.from : grid.chipAcross
            radius: grid.chipAcross / 2
            color: Theme.acrylic ? grid.acrylicChip : Theme.soft
            Behavior on x { NumberAnimation { duration: 320 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
            Behavior on y { NumberAnimation { duration: 320 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
            Behavior on width { NumberAnimation { duration: 320 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
            Behavior on height { NumberAnimation { duration: 320 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        }
    }

    // ячейки сетки в режиме правки
    Repeater {
        model: grid.editing ? grid.cells : 0
        delegate: Rectangle {
            required property int index
            readonly property real p: grid.starts[index] + 2
            readonly property real s: grid.sizes[index] - 4
            x: grid.vertical ? 5 : p
            y: grid.vertical ? p : 5
            width: grid.vertical ? grid.thick - 10 : s
            height: grid.vertical ? s : grid.thick - 10
            radius: 12
            color: "transparent"
            border.width: 1.5
            border.color: Theme.fg3
            opacity: 0.45
        }
    }

    // куда встанет перетаскиваемый модуль
    Rectangle {
        id: ghost
        property bool ok: true
        property int cell: 0
        property int span: 1
        visible: false
        readonly property real p: grid.starts[cell]
        readonly property real s: grid.starts[Math.min(grid.cells, cell + span)] - p
        x: grid.vertical ? 3 : p
        y: grid.vertical ? p : 3
        width: grid.vertical ? grid.thick - 6 : s
        height: grid.vertical ? s : grid.thick - 6
        radius: 14
        color: ok ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2) : Qt.rgba(0.9, 0.28, 0.3, 0.15)
        border.width: 2
        border.color: ok ? Theme.accent : "#E5484D"
    }

    // ScriptModel по id: при перестановке делегаты не пересоздаются,
    // а переезжают пружиной на новую ячейку
    Repeater {
        id: slots
        model: ScriptModel { values: grid.modules; objectProp: "id" }

        delegate: Item {
            id: slot
            required property var modelData
            required property int index
            readonly property string mid: modelData.id
            readonly property var entry: grid.modules.find(m => m.id === mid) ?? modelData
            readonly property int cell: entry.cell
            readonly property int span: entry.span
            readonly property bool menuOpen: ShellState.menu === mid && ShellState.menuScreen === grid.screen
            readonly property Item mod: loader.item
            readonly property bool hiddenMod: mod ? mod.hidden === true : true
            readonly property real modAlong: mod ? (grid.vertical ? mod.implicitHeight : mod.implicitWidth) : 0
            readonly property real natural: hiddenMod ? 0 : Math.max(36, modAlong + (grid.vertical ? 16 : 20))
            onNaturalChanged: grid.setNatural(mid, natural)
            Component.onCompleted: grid.setNatural(mid, natural)

            readonly property real start: grid.tileLayout ? (grid.tl.start[cell] ?? 0) : grid.starts[cell]
            readonly property real size: grid.tileLayout ? (grid.tl.end[cell + span - 1] ?? start) - start : grid.starts[cell + span] - start
            // в общем чипе: свой не рисуем, подсветка — кружком
            readonly property bool grouped: grid.tileLayout && grid.tl.groups.some(g => start >= g.from - 0.5 && start < g.to - 0.5)
            readonly property bool chip: grid.tileLayout && !grouped && grid.tl.chip[mid] === true
            property real dragOff: 0
            property bool dragging: false
            property bool resizing: false

            x: grid.vertical ? 0 : start + dragOff
            y: grid.vertical ? start + dragOff : 0
            width: grid.vertical ? grid.thick : size
            height: grid.vertical ? size : grid.thick
            z: dragging || resizing ? 5 : 1
            opacity: grid.isleAlpha(start, 0.6)
            transform: Translate {
                x: grid.vertical ? 0 : grid.isleShift(slot.start)
                y: grid.vertical ? grid.isleShift(slot.start) : 0
            }
            Behavior on x { enabled: !slot.dragging; NumberAnimation { duration: 380 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
            Behavior on y { enabled: !slot.dragging; NumberAnimation { duration: 380 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
            Behavior on width { enabled: !slot.dragging && !slot.resizing; NumberAnimation { duration: 320 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
            Behavior on height { enabled: !slot.dragging && !slot.resizing; NumberAnimation { duration: 320 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

            readonly property bool tiles: grid.length === "tiles"
            readonly property real btnAcross: grid.tileLayout ? grid.chipAcross : tiles ? 40 : (grid.thick < 46 ? 30 : 36)
            readonly property real btnAlong: grid.tileLayout ? Math.max(btnAcross, size)
                : tiles ? Math.max(btnAcross, size - 6) : Math.max(btnAcross, Math.min(natural, size - 4))

            // кнопка модуля: подсветка при наведении, стекло в плиточном режиме
            Item {
                id: btn
                anchors.centerIn: parent
                width: grid.vertical ? slot.btnAcross : slot.btnAlong
                height: grid.vertical ? slot.btnAlong : slot.btnAcross
                visible: !slot.hiddenMod || grid.editing
                opacity: slot.hiddenMod ? 0.4 : 1

                // из модуля вытекает капля меню (или «Настроек» у V): кнопка
                // тянется за ней от края и пружинит (как плитки дока приложений)
                property real pull: ShellState.pullKey === (grid.screen?.name ?? "") + "/top:" + slot.mid ? ShellState.pull : 0
                Behavior on pull { SpringAnimation { spring: 4.5; damping: 0.2; epsilon: 0.002 } }
                transform: [
                    Scale {
                        origin.x: grid.edge === "left" ? 0 : grid.edge === "right" ? btn.width : btn.width / 2
                        origin.y: grid.edge === "top" ? 0 : grid.edge === "bottom" ? btn.height : btn.height / 2
                        xScale: grid.vertical ? 1 + 0.32 * btn.pull : 1 - 0.1 * btn.pull
                        yScale: grid.vertical ? 1 - 0.1 * btn.pull : 1 + 0.32 * btn.pull
                    },
                    // «желе» плитки: колышется от наведения, нажатия и толчков дока
                    Scale {
                        origin.x: btn.width / 2
                        origin.y: btn.height / 2
                        xScale: 1 + jx.value
                        yScale: 1 + jy.value
                    }
                ]

                // на острове у модуля свой чип — пусть он и живёт
                readonly property real jk: slot.tiles ? 1 : 0.45
                Spring { id: jx; stiffness: 320; damping: 10 }
                Spring { id: jy; stiffness: 320; damping: 10 }
                function wobble(k) { jx.kick(k * btn.jk); jy.kick(-0.8 * k * btn.jk); }
                Connections {
                    target: area
                    function onContainsMouseChanged() { if (area.containsMouse && !grid.editing) btn.wobble(0.9); }
                    function onPressedChanged() {
                        if (grid.editing) return;
                        // нажатие сплющивает, отпускание подбрасывает
                        if (area.pressed) { jx.kick(1.3 * btn.jk); jy.kick(-1.6 * btn.jk); }
                        else { jx.kick(-0.8 * btn.jk); jy.kick(1.1 * btn.jk); }
                    }
                }
                // толчок дока (смена стола, раскладки) расходится волной по плиткам
                Timer { id: ripple; property real k: 0; onTriggered: btn.wobble(k) }
                Connections {
                    target: ShellState
                    function onDockPoked(dockId, strength) {
                        if (dockId !== "top" || grid.editing) return;
                        ripple.k = 1.4 * strength;
                        ripple.interval = 30 + 45 * slot.index;
                        ripple.restart();
                    }
                }

                // чип модуля на острове; в правке — своя стеклянная плитка
                Rectangle {
                    anchors.fill: parent
                    radius: Math.min(width, height) / 2
                    visible: slot.chip || (slot.tiles && grid.editing)
                    // «Акрил»: чипы как у Serpantinium — ровная светлая подложка,
                    // а модуль может попросить залить свой акцентом (батарея)
                    color: !slot.chip ? DockService.topGlass
                        : Theme.acrylic && loader.item?.chipAccent === true ? Theme.accent
                        : Theme.acrylic ? grid.acrylicChip : Theme.soft
                    border.width: slot.chip || Theme.liquid ? 0 : 1
                    border.color: Theme.line
                    Sheen { visible: !slot.chip && (Theme.liquid || Theme.acrylic); radius: parent.radius; strength: 0.9 }
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: slot.grouped ? 3 : 0
                    radius: Math.min(width, height) / 2
                    // у жидкого стекла под курсором — светлая бусина с бликом
                    color: Theme.liquid ? Qt.rgba(1, 1, 1, Theme.light ? 0.30 : 0.14) : Theme.soft2
                    opacity: slot.menuOpen || (area.containsMouse && !grid.editing) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 * Theme.anim.k } }
                    Sheen { radius: parent.radius; strength: 0.8 }
                }

                Loader {
                    id: loader
                    anchors.centerIn: parent
                    z: 1
                    source: Qt.resolvedUrl("modules/" + DockService.cap(slot.mid) + "Module.qml")
                    onLoaded: {
                        item.screen = Qt.binding(() => grid.screen);
                        item.vertical = Qt.binding(() => grid.vertical);
                        item.full = Qt.binding(() => !grid.compact);
                    }
                }

                // покачивание в режиме правки, как значки на телефоне
                rotation: 0
                SequentialAnimation on rotation {
                    running: grid.editing && !slot.dragging
                    loops: Animation.Infinite
                    PauseAnimation { duration: (Math.max(0, (slot.index * 70) % 300)) * Theme.anim.k }
                    SequentialAnimation {
                        loops: Animation.Infinite
                        NumberAnimation { to: -1.4; duration: 160 * Theme.anim.k; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.4; duration: 320 * Theme.anim.k; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0; duration: 160 * Theme.anim.k; easing.type: Easing.InOutSine }
                    }
                    onRunningChanged: if (!running) btn.rotation = 0
                }

                // убрать модуль
                Rectangle {
                    visible: grid.editing
                    z: 3
                    width: 18; height: 18; radius: 9
                    anchors { right: parent.right; top: parent.top; rightMargin: -4; topMargin: -4 }
                    color: "#E5484D"
                    Label { anchors.centerIn: parent; text: "×"; color: "#ffffff"; font.pixelSize: 13; font.weight: Font.Bold }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -3
                        cursorShape: Qt.PointingHandCursor
                        onClicked: DockService.removeModule(slot.mid)
                    }
                }
            }

            // Изменение ширины модуля: тянем за правый (нижний) край.
            // В плитках это сразу уменьшает/увеличивает число клеток.
            Rectangle {
                id: grip
                visible: grid.editing && !slot.hiddenMod
                z: 6
                width: grid.vertical ? slot.width : 14
                height: grid.vertical ? 14 : slot.height
                x: grid.vertical ? 0 : slot.width - width
                y: grid.vertical ? slot.height - height : 0
                color: "transparent"
                Rectangle {
                    anchors.centerIn: parent
                    width: grid.vertical ? parent.width - 4 : 4
                    height: grid.vertical ? 4 : parent.height - 4
                    radius: 2
                    color: Theme.accent
                    opacity: gripArea.pressed ? 1 : 0.55
                }
                MouseArea {
                    id: gripArea
                    anchors.fill: parent
                    anchors.margins: -4
                    preventStealing: true
                    cursorShape: grid.vertical ? Qt.SizeVerCursor : Qt.SizeHorCursor
                    onPressed: { slot.resizing = true; grid.forceActiveFocus(); }
                    onPositionChanged: m => {
                        if (!slot.resizing) return;
                        const p = mapToItem(grid, m.x, m.y);
                        const pos = grid.vertical ? p.y : p.x;
                        const end = Math.max(slot.cell + 1, Math.min(grid.cells, Math.round((pos - grid.pad) / grid.cw)));
                        const span = end - slot.cell;
                        ghost.cell = slot.cell;
                        ghost.span = span;
                        ghost.ok = DockService.planSpan(slot.mid, span) !== null;
                        ghost.visible = true;
                    }
                    onReleased: {
                        if (!slot.resizing) return;
                        const span = ghost.span;
                        ghost.visible = false;
                        slot.resizing = false;
                        DockService.setSpan(slot.mid, span);
                    }
                    onCanceled: { ghost.visible = false; slot.resizing = false; }
                }
            }

            MouseArea {
                id: area
                anchors.fill: btn
                z: grid.editing ? 2 : 0
                hoverEnabled: true
                preventStealing: grid.editing
                acceptedButtons: Qt.LeftButton
                cursorShape: grid.editing ? (slot.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.PointingHandCursor
                property real pressAt: 0

                function along(m) { return grid.vertical ? mapToItem(grid, m.x, m.y).y : mapToItem(grid, m.x, m.y).x; }

                onPressed: m => { if (grid.editing) pressAt = along(m); }
                // модуль, который сам разбирает щелчки (рабочие столы), узнаёт и о наведении
                function own() { return !grid.editing && slot.mod && typeof slot.mod.click === "function"; }
                onExited: if (slot.mod && typeof slot.mod.hoverAt === "function") slot.mod.hoverAt(-1, -1)
                onPositionChanged: m => {
                    if (own() && typeof slot.mod.hoverAt === "function") {
                        const p = mapToItem(slot.mod, m.x, m.y);
                        slot.mod.hoverAt(p.x, p.y);
                    }
                    if (!grid.editing || !pressed) return;
                    const d = along(m) - pressAt;
                    if (!slot.dragging && Math.abs(d) < 4) return;
                    slot.dragging = true;
                    slot.dragOff = d;
                    const target = Math.max(0, Math.min(grid.cells - slot.span, Math.round((slot.start + d - grid.pad) / grid.cw)));
                    ghost.cell = target;
                    ghost.span = slot.span;
                    ghost.ok = DockService.planMove(slot.mid, target) !== null;
                    ghost.visible = true;
                }
                onReleased: {
                    if (!slot.dragging) return;
                    const target = ghost.cell;
                    ghost.visible = false;
                    slot.dragging = false;
                    // Behavior вернёт модуль на новое место (или на старое) пружиной
                    slot.dragOff = 0;
                    DockService.moveModule(slot.mid, target);
                }
                onClicked: m => {
                    if (grid.editing) return;
                    if (own()) {
                        const p = mapToItem(slot.mod, m.x, m.y);
                        slot.mod.click(p.x, p.y);
                        return;
                    }
                    grid.activated(slot.mid, slot);
                }
                onWheel: w => {
                    if (!grid.editing && slot.mod && typeof slot.mod.wheel === "function")
                        // второе — сам сдвиг (120 — щелчок колеса; тачпад — мелкими долями)
                        slot.mod.wheel(w.angleDelta.y > 0 ? 1 : -1, w.angleDelta.y);
                }
            }
        }
    }
}
