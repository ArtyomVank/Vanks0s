import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import qs.common.ui

// Загрузка процессора и памяти. Читаем /proc раз в 3 с и только пока
// модуль стоит в доке; подробности (видеокарта, температуры) — в PcMenu.
Item {
    id: root

    property bool vertical: false
    property bool full: true
    property ShellScreen screen
    property bool hidden: false

    property int cpu: 0
    property int ram: 0
    property var last: null

    implicitWidth: vertical ? 20 : row.implicitWidth
    implicitHeight: 20

    FileView { id: stat; path: "/proc/stat"; blockLoading: true }
    FileView { id: mem; path: "/proc/meminfo"; blockLoading: true }

    function sample() {
        stat.reload();
        mem.reload();
        const f = (stat.text().split("\n")[0] || "").trim().split(/\s+/).slice(1).map(Number);
        if (f.length >= 5) {
            const idle = f[3] + (f[4] || 0);
            const total = f.reduce((a, b) => a + b, 0);
            if (last) {
                const dt = total - last.total, di = idle - last.idle;
                if (dt > 0) cpu = Math.round(100 * (1 - di / dt));
            }
            last = { total: total, idle: idle };
        }
        const m = mem.text();
        const total = Number((/MemTotal:\s+(\d+)/.exec(m) || [])[1] || 0);
        const avail = Number((/MemAvailable:\s+(\d+)/.exec(m) || [])[1] || 0);
        if (total > 0) ram = Math.round(100 * (1 - avail / total));
    }

    Timer { interval: 3000; running: root.visible; repeat: true; triggeredOnStart: true; onTriggered: root.sample() }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Sym { anchors.verticalCenter: parent.verticalCenter; name: "cpu"; size: 18; color: Theme.fg2 }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.vertical
            text: root.full ? "ЦП " + root.cpu + "% · ОЗУ " + root.ram + "%" : root.cpu + "%"
            size: "small"
            tone: 2
            font.weight: Font.Bold
            font.features: { "tnum": 1 }
        }
    }
}
