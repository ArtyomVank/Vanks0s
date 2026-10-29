pragma ComponentBehavior: Bound

import QtQuick
import qs.common
import qs.common.ui
import "../layout.js" as L

// Холст расположения мониторов. Перетаскивание с подсказкой, куда монитор
// встанет (вплотную к соседу, с прилипанием к краям и центру).
//
//   rects:    [{ name, x, y, w, h, title, sub, primary }] — логические пиксели
//   selected: имя выбранного
//   select(name), dropped(name, x, y) — x, y в логических пикселях
Item {
    id: root

    property var rects: []
    property string selected
    signal select(string name)
    signal dropped(string name, real x, real y)

    implicitHeight: 250

    readonly property int pad: 24
    // рамка всей раскладки с запасом под перетаскивание
    readonly property var box: {
        if (rects.length === 0) return { x: 0, y: 0, w: 1, h: 1 };
        const x0 = Math.min.apply(null, rects.map(r => r.x)), y0 = Math.min.apply(null, rects.map(r => r.y));
        const x1 = Math.max.apply(null, rects.map(r => r.x + r.w)), y1 = Math.max.apply(null, rects.map(r => r.y + r.h));
        return { x: x0, y: y0, w: Math.max(1, x1 - x0), h: Math.max(1, y1 - y0) };
    }
    readonly property real k: Math.min((width - pad * 2) / box.w, (height - pad * 2) / box.h) * 0.86
    readonly property real ox: (width - box.w * k) / 2
    readonly property real oy: (height - box.h * k) / 2
    // прилипание ~10 экранных пикселей
    readonly property real snap: 10 / Math.max(k, 0.0001)

    function toX(lx) { return ox + (lx - box.x) * k; }
    function toY(ly) { return oy + (ly - box.y) * k; }

    // подсказка во время перетаскивания: куда встанет монитор
    property var ghost: null

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius - 6
        color: Qt.rgba(0, 0, 0, Theme.light ? 0.04 : 0.16)
        border.width: 1
        border.color: Theme.line
    }

    Label {
        visible: root.rects.length === 0
        anchors.centerIn: parent
        text: "Нет включённых мониторов"
        tone: 3
    }

    Rectangle {
        visible: root.ghost !== null
        x: root.ghost ? root.toX(root.ghost.x) : 0
        y: root.ghost ? root.toY(root.ghost.y) : 0
        width: root.ghost ? root.ghost.w * root.k : 0
        height: root.ghost ? root.ghost.h * root.k : 0
        radius: 8
        color: "transparent"
        border.width: 2
        border.color: Theme.accent
        opacity: 0.7
    }

    Repeater {
        model: root.rects
        delegate: Rectangle {
            id: tile
            required property var modelData
            readonly property bool sel: modelData.name === root.selected
            property real dx: 0
            property real dy: 0

            x: root.toX(modelData.x) + dx
            y: root.toY(modelData.y) + dy
            width: Math.max(8, modelData.w * root.k - 3)
            height: Math.max(8, modelData.h * root.k - 3)
            z: drag.pressed ? 10 : sel ? 2 : 1
            radius: 8
            color: sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.30) : Theme.soft2
            border.width: sel ? 2 : 1
            border.color: sel ? Theme.accent : Theme.line
            Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
            scale: drag.pressed ? 1.02 : 1
            Behavior on scale { NumberAnimation { duration: Theme.anim.fast } }

            Column {
                anchors.centerIn: parent
                width: parent.width - 12
                spacing: 2
                visible: tile.height > 34
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: tile.modelData.title
                    font.weight: Font.DemiBold
                    size: tile.width > 120 ? "body" : "caption"
                }
                Label {
                    width: parent.width
                    visible: tile.height > 56
                    horizontalAlignment: Text.AlignHCenter
                    text: tile.modelData.sub
                    size: "caption"
                    tone: 2
                }
            }
            // основной экран — значок дока в углу
            Sym {
                visible: tile.modelData.primary && tile.width > 40
                anchors { right: parent.right; bottom: parent.bottom; margins: 6 }
                name: "dock"
                size: 14
                color: tile.sel ? Theme.accent : Theme.fg3
            }

            MouseArea {
                id: drag
                anchors.fill: parent
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                preventStealing: true
                property point start
                onPressed: m => {
                    start = mapToItem(root, m.x, m.y);
                    root.select(tile.modelData.name);
                }
                onPositionChanged: m => {
                    if (!pressed || root.rects.length < 2) return;
                    const p = mapToItem(root, m.x, m.y);
                    tile.dx = p.x - start.x;
                    tile.dy = p.y - start.y;
                    const r = tile.modelData;
                    const lx = r.x + tile.dx / root.k, ly = r.y + tile.dy / root.k;
                    const others = root.rects.filter(o => o.name !== r.name);
                    const at = L.place(r, Math.round(lx), Math.round(ly), others, root.snap);
                    root.ghost = { x: at.x, y: at.y, w: r.w, h: r.h };
                }
                onReleased: {
                    const r = tile.modelData;
                    const moved = Math.abs(tile.dx) + Math.abs(tile.dy) > 3;
                    const lx = r.x + tile.dx / root.k, ly = r.y + tile.dy / root.k;
                    tile.dx = 0;
                    tile.dy = 0;
                    root.ghost = null;
                    if (moved) root.dropped(r.name, lx, ly);
                }
            }
        }
    }
}
