pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Перетаскивание окна мышью — со слов Hyprland. Сам он о нём не сообщает:
// таймер в hyprland.lua (раздел «ПЕРЕТАСКИВАНИЕ») следит за окном, пока
// зажата левая кнопка, и пишет состояние в delta-drag.json рядом с сокетом
// экземпляра. Читают «желе» (Jelly.qml) и подсветка края (Snap.qml).
//     state: begin → move … → end;   zone: left/right/tl/tr/bl/br/max или ""
Singleton {
    id: root

    property string state: ""
    property string address: ""     // без 0x
    property string monitor: ""
    property rect win               // окно сейчас, глобальные координаты
    property point grab             // где его держат, от левого верхнего угла
    property string zone: ""
    property rect zoneRect
    readonly property bool dragging: state === "begin" || state === "move"

    signal began()
    signal moved()
    signal ended(bool snapped)

    property int seq: -1

    FileView {
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/hypr/"
              + (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "") + "/delta-drag.json"
        watchChanges: true
        printErrors: false
        blockLoading: true
        onFileChanged: reload()
        onLoaded: root.parse(text())
    }

    // таймер Hyprland мог умереть вместе с конфигом (перезагрузка посреди
    // перетаскивания) — без новых строк «тащат» не дольше трёх секунд
    Timer { id: stale; interval: 3000; onTriggered: if (root.dragging) root.finish(false) }

    function parse(t) {
        let d = null;
        try { d = JSON.parse(t); } catch (e) { return; }
        if (!d || d.seq === seq) return;
        const first = seq < 0;
        seq = d.seq;
        if (first) return;             // прошлое перетаскивание, не наше
        const wasDragging = dragging;
        address = String(d.address || "").replace(/^0x/, "");
        monitor = d.monitor || "";
        win = Qt.rect(d.x, d.y, d.w, d.h);
        grab = Qt.point(d.gx, d.gy);
        zone = d.zone || "";
        zoneRect = Qt.rect(d.zx, d.zy, d.zw, d.zh);
        if (d.state === "end") {
            if (wasDragging) finish(zone !== "");
            return;
        }
        state = d.state;
        stale.restart();
        if (!wasDragging) began();     // «begin» мог не дойти — хватит и «move»
        moved();
    }

    function finish(snapped) {
        stale.stop();
        state = "end";
        ended(snapped);
    }
}
