import QtQuick
import Quickshell.Io
import qs.common
import qs.common.ui
import qs.widgets.parts

// Скорость сети: приём и отдача по /proc/net/dev раз в секунду, сумма по
// настоящим интерфейсам (без lo, мостов и контейнеров). «График» — две
// волны за последнюю минуту, «Числа» — только скорости.
Base {
    id: root

    readonly property bool graph: root.mode !== "numbers"
    property real down: -1          // байт/с
    property real up: -1
    property var downHist: []
    property var upHist: []
    property var last: null

    FileView {
        id: dev
        path: "/proc/net/dev"
        blockLoading: true
        printErrors: false
    }
    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.visible
        onTriggered: {
            dev.reload();
            root.sample(dev.text());
        }
    }

    function sample(t) {
        let rx = 0, tx = 0;
        for (const line of String(t || "").split("\n").slice(2)) {
            const m = line.trim().match(/^([^:]+):\s*(.*)$/);
            if (!m || /^(lo|veth|docker|virbr|br-|vnet)/.test(m[1])) continue;
            const f = m[2].split(/\s+/).map(Number);
            rx += f[0] || 0;
            tx += f[8] || 0;
        }
        const now = Date.now();
        if (last && now > last.t) {
            const dt = (now - last.t) / 1000;
            down = Math.max(0, (rx - last.rx) / dt);
            up = Math.max(0, (tx - last.tx) / dt);
            downHist = downHist.concat([down]).slice(-60);
            upHist = upHist.concat([up]).slice(-60);
        }
        last = { t: now, rx: rx, tx: tx };
    }

    function speed(v) {
        if (v < 0) return "—";
        const u = ["Б/с", "КБ/с", "МБ/с", "ГБ/с"].map(x => I18n.tr(x));
        let i = 0;
        while (v >= 1000 && i < u.length - 1) { v /= 1024; i++; }
        return (v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1).replace(".", ",")) + " " + u[i];
    }
    // обе волны в одном масштабе — по самому быстрому за минуту
    readonly property real peak: Math.max(64 * 1024, ...downHist, ...upHist)
    function pct(list) { return list.map(v => v / peak * 100); }

    WCaption { id: cap; cm: root.cm; text: I18n.tr("Сеть"); color: root.pal.c2; width: parent.width }

    Item {
        id: waves
        visible: root.graph
        anchors { left: parent.left; right: parent.right; top: cap.bottom; topMargin: 2 * root.ch; bottom: nums.top; bottomMargin: 2 * root.ch }
        Wave { anchors.fill: parent; values: root.pct(root.downHist); color: Theme.accent; step: 10 }
        Wave { anchors.fill: parent; values: root.pct(root.upHist); color: Theme.accents[3]; step: 10; opacity: 0.85 }
    }

    // скорости: снизу под графиком или крупно посередине
    Flow {
        id: nums
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.bottomMargin: root.graph ? 0 : (parent.height - cap.height - height) / 2
        spacing: 6 * root.cm

        component Speed: Row {
            id: sp
            property string icon
            property string value
            property color tone
            spacing: 2 * root.cm
            Sym {
                anchors.verticalCenter: parent.verticalCenter
                name: sp.icon
                size: Math.round(txt.px * 0.9)
                color: sp.tone
            }
            WText {
                id: txt
                anchors.verticalCenter: parent.verticalCenter
                text: sp.value
                px: root.graph ? 10 * root.cm : 14 * root.cm
                display: true
                color: root.pal.c1
            }
        }
        Speed { icon: "chevron-down"; value: root.speed(root.down); tone: Theme.accent }
        Speed { icon: "chevron-up"; value: root.speed(root.up); tone: Theme.accents[3] }
    }
}
