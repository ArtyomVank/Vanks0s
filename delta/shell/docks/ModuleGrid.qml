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
// tiles — каждый модуль — своя стеклянная плитка по размеру содержимого,
// ровные зазоры, а соседние маленькие значки (колокольчик, раскладка, сеть,
// звук) сливаются в одну капсулу; пустые клетки — чуть больший зазор;
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
    // --- плитки: раскладка по содержимому ---
    readonly property bool tileLayout: tiles && !editing
    readonly property real tileSmall: 40      // значок без подписи — кружок
    readonly property real tileGap: 6         // между плитками
    readonly property real groupGap: 14       // где в сетке пустые клетки
    function isSmall(m) { return m.span === 1 && (naturals[m.id] ?? 36) <= 52; }
    // { start[c], end[c] — по ячейкам модулей; groups: [{ from, to }] капсул; total }
    readonly property var tl: {
        const start = [], end = [], groups = [];
        const list = modules.filter(m => (naturals[m.id] ?? 36) > 0).slice().sort((a, b) => a.cell - b.cell);
        let acc = pad, prev = null, group = null;
        for (const m of list) {
            const small = isSmall(m);
            const touching = prev !== null && m.cell === prev.cell + prev.span;
            const together = touching && small && isSmall(prev);
            if (prev !== null) acc += together ? 0 : (touching ? tileGap : groupGap) * wk;
            const w = (small ? tileSmall : Math.max(52, (naturals[m.id] ?? 36) + 12)) * wk;
            for (let c = m.cell; c < m.cell + m.span; c++) {
                start[c] = acc + (c - m.cell) * w / m.span;
                end[c] = acc + (c - m.cell + 1) * w / m.span;
            }
            if (together) group.to = acc + w;
            else if (small) { group = { from: acc, to: acc + w, n: 0 }; groups.push(group); }
            else group = null;
            if (small) group.n++;
            acc += w;
            prev = m;
        }
        return { start: start, end: end, groups: groups.filter(g => g.n > 1), total: acc };
    }

    readonly property real implicitAlong: tileLayout ? Math.max(80, tl.total + pad)
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

    // капсулы из соседних маленьких значков — общее стекло под ними
    Repeater {
        model: grid.tileLayout ? grid.tl.groups : []
        delegate: Rectangle {
            required property var modelData
            readonly property real across: 40
            x: grid.vertical ? (grid.thick - across) / 2 : modelData.from
            y: grid.vertical ? modelData.from : (grid.thick - across) / 2
            width: grid.vertical ? across : modelData.to - modelData.from
            height: grid.vertical ? modelData.to - modelData.from : across
            radius: across / 2
            color: DockService.topGlass
            border.width: 1
            border.color: Theme.line
            // капсула вздрагивает вместе с плитками
            transform: Scale { origin.x: capsule.width / 2; origin.y: capsule.height / 2; xScale: 1 + cj.value * 0.6; yScale: 1 - cj.value }
            id: capsule
            Spring { id: cj; stiffness: 280; damping: 10 }
            Connections {
                target: ShellState
                function onDockPoked(dockId, strength) { if (dockId === "top") cj.kick(0.9 * strength); }
            }
            Behavior on x { NumberAnimation { duration: 320 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
            Behavior on width { NumberAnimation { duration: 320 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
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
            // в капсуле: своё стекло не рисуем, подсветка — кружком
            readonly property bool grouped: grid.tileLayout && grid.tl.groups.some(g => start >= g.from - 0.5 && start < g.to - 0.5)
            property real dragOff: 0
            property bool dragging: false
            property bool resizing: false

            x: grid.vertical ? 0 : start + dragOff
            y: grid.vertical ? start + dragOff : 0
            width: grid.vertical ? grid.thick : size
            height: grid.vertical ? size : grid.thick
            z: dragging || resizing ? 5 : 1
            Behavior on x { enabled: !slot.dragging; NumberAnimation { duration: 380 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
            Behavior on y { enabled: !slot.dragging; NumberAnimation { duration: 380 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
            Behavior on width { enabled: !slot.dragging && !slot.resizing; NumberAnimation { duration: 320 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
            Behavior on height { enabled: !slot.dragging && !slot.resizing; NumberAnimation { duration: 320 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

            readonly property bool tiles: grid.length === "tiles"
            readonly property real btnAcross: tiles ? (grid.compact ? 32 : 40) : (grid.thick < 46 ? 30 : 36)
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

                // в плиточном режиме у плитки своё стекло — пусть она и живёт
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

                Rectangle {
                    anchors.fill: parent
                    radius: Math.min(width, height) / 2
                    visible: slot.tiles && !slot.grouped
                    color: DockService.topGlass
                    border.width: 1
                    border.color: Theme.line
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: slot.grouped ? 3 : 0
                    radius: Math.min(width, height) / 2
                    color: Theme.soft2
                    opacity: slot.menuOpen || (area.containsMouse && !grid.editing) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 * Theme.anim.k } }
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
                        slot.mod.wheel(w.angleDelta.y > 0 ? 1 : -1);
                }
            }
        }
    }
}
