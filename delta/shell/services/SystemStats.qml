pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Показатели ПК для виджетов и меню «ПК».
//
// Опрос идёт только пока кто-то смотрит: виджеты и меню держат StatsUser {}
// (или зовут acquire/release). Без зрителей таймер стоит и nvidia-smi не запущен.
// Процессор, память и температуры читаются из /proc и /sys раз в секунду —
// без запуска процессов; диск — df раз в 30 с; NVIDIA — один долгоживущий
// nvidia-smi -l 1. Нет датчика — значение -1, виджет пишет «нет данных».
Singleton {
    id: root

    // --- кто смотрит ---
    property int users: 0
    property int gpuUsers: 0
    property int diskUsers: 0
    readonly property bool active: users > 0

    function acquire(gpu, disk) {
        users++;
        if (gpu) gpuUsers++;
        if (disk) diskUsers++;
    }
    function release(gpu, disk) {
        users = Math.max(0, users - 1);
        if (gpu) gpuUsers = Math.max(0, gpuUsers - 1);
        if (disk) diskUsers = Math.max(0, diskUsers - 1);
    }

    // --- значения (проценты 0–100, температуры в °C, байты) ---
    property real cpu: -1
    property real cpuTemp: -1
    property string cpuName: ""
    property real ram: -1
    property real ramUsed: 0
    property real ramTotal: 0
    property real swapUsed: 0
    property real swapTotal: 0
    property string gpuVendor: ""        // "amd" | "nvidia" | "intel" | ""
    property string gpuName: ""
    property real gpu: -1
    property real gpuTemp: -1
    property real vramUsed: 0
    property real vramTotal: 0
    property real disk: -1
    property real diskUsed: 0
    property real diskTotal: 0

    readonly property bool hasCpuTemp: cpuTemp >= 0
    readonly property bool hasGpuLoad: gpu >= 0
    readonly property bool hasGpuTemp: gpuTemp >= 0

    // История для графиков «волна» и «столбцы»: последние historySize секунд.
    readonly property int historySize: 60
    property var cpuHist: []
    property var ramHist: []
    property var gpuHist: []

    function push(list, v) {
        const out = list.length >= historySize ? list.slice(list.length - historySize + 1) : list.slice();
        out.push(Math.max(0, Math.min(100, v)));
        return out;
    }

    // «12,4 ГБ»
    readonly property var units: ["Б", "КБ", "МБ", "ГБ", "ТБ"]
    function unitOf(v) {
        let i = 0;
        while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
        return i;
    }
    function num(v, i) {
        v /= Math.pow(1024, i);
        return (v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)).toString().replace(".", ",");
    }
    function bytes(v) { const i = unitOf(v); return num(v, i) + " " + units[i]; }
    // «7,7 из 15,4 ГБ» — короче, когда единица общая
    function pair(used, total) {
        const i = unitOf(total);
        return num(used, i) + " из " + num(total, i) + " " + units[i];
    }

    // --- поиск датчиков (один раз, при первом зрителе) ---
    property var paths: ({})
    property bool probed: false

    onActiveChanged: if (active && !probed) probe.running = true

    Process {
        id: probe
        command: ["sh", Quickshell.shellDir + "/services/sensors.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = {};
                for (const line of text.split("\n")) {
                    const i = line.indexOf("=");
                    if (i > 0) p[line.slice(0, i)] = line.slice(i + 1);
                }
                root.paths = p;
                root.cpuName = p.cpuname || "";
                root.gpuVendor = p.gpu || "";
                root.gpuName = p.gpuname || (p.gpu === "amd" ? "AMD Radeon" : p.gpu === "intel" ? "Intel Graphics" : "");
                root.probed = true;
                if (p.vramtotal) vramTotalFile.reload();
            }
        }
    }

    // --- опрос раз в секунду ---
    Timer {
        running: root.active && root.probed
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statFile.reload();
            memFile.reload();
            if (root.paths.cputemp) cpuTempFile.reload();
            if (root.gpuUsers > 0) {
                if (root.paths.gpubusy) gpuBusyFile.reload();
                if (root.paths.gputemp) gpuTempFile.reload();
                if (root.paths.vramused) vramUsedFile.reload();
            }
        }
    }

    property var lastCpu: null

    FileView {
        id: statFile
        path: "/proc/stat"
        printErrors: false
        onLoaded: {
            const t = text();
            const line = t.slice(0, t.indexOf("\n")).trim().split(/\s+/).slice(1, 9).map(Number);
            if (line.length < 4) return;
            const idle = line[3] + (line[4] || 0);
            const total = line.reduce((a, b) => a + b, 0);
            if (root.lastCpu && total > root.lastCpu.total) {
                const v = 100 * (1 - (idle - root.lastCpu.idle) / (total - root.lastCpu.total));
                root.cpu = Math.max(0, Math.min(100, v));
                root.cpuHist = root.push(root.cpuHist, root.cpu);
            }
            root.lastCpu = { idle: idle, total: total };
        }
    }

    FileView {
        id: memFile
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: {
            const m = {};
            for (const line of text().split("\n")) {
                const r = /^(\w+):\s+(\d+)/.exec(line);
                if (r) m[r[1]] = Number(r[2]) * 1024;
            }
            if (!m.MemTotal) return;
            root.ramTotal = m.MemTotal;
            root.ramUsed = m.MemTotal - (m.MemAvailable ?? m.MemFree ?? 0);
            root.swapTotal = m.SwapTotal || 0;
            root.swapUsed = (m.SwapTotal || 0) - (m.SwapFree || 0);
            root.ram = 100 * root.ramUsed / root.ramTotal;
            root.ramHist = root.push(root.ramHist, root.ram);
        }
    }

    FileView {
        id: cpuTempFile
        path: root.paths.cputemp || ""
        printErrors: false
        onLoaded: { const v = parseInt(text()); root.cpuTemp = isNaN(v) ? -1 : v / 1000; }
        onLoadFailed: root.cpuTemp = -1
    }

    FileView {
        id: gpuBusyFile
        path: root.paths.gpubusy || ""
        printErrors: false
        onLoaded: {
            const v = parseInt(text());
            if (isNaN(v)) return;
            root.gpu = v;
            root.gpuHist = root.push(root.gpuHist, v);
        }
    }

    FileView {
        id: gpuTempFile
        path: root.paths.gputemp || ""
        printErrors: false
        onLoaded: { const v = parseInt(text()); root.gpuTemp = isNaN(v) ? -1 : v / 1000; }
    }

    FileView {
        id: vramUsedFile
        path: root.paths.vramused || ""
        printErrors: false
        onLoaded: root.vramUsed = Number(text()) || 0
    }

    FileView {
        id: vramTotalFile
        path: root.paths.vramtotal || ""
        printErrors: false
        onLoaded: root.vramTotal = Number(text()) || 0
    }

    // NVIDIA: sysfs не отдаёт загрузку, поэтому один nvidia-smi с -l 1,
    // который живёт, только пока нужны данные видеокарты.
    Process {
        id: nvsmi
        running: root.probed && root.paths.nvsmi === "1" && root.active && root.gpuUsers > 0
        command: ["nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total",
                  "--format=csv,noheader,nounits", "-l", "1"]
        stdout: SplitParser {
            onRead: line => {
                const f = line.split(",").map(s => parseFloat(s));
                if (f.length < 4 || isNaN(f[0])) return;
                root.gpu = f[0];
                root.gpuHist = root.push(root.gpuHist, f[0]);
                root.gpuTemp = isNaN(f[1]) ? -1 : f[1];
                // nvidia-smi отдаёт память в МиБ
                root.vramUsed = (f[2] || 0) * 1048576;
                root.vramTotal = (f[3] || 0) * 1048576;
            }
        }
    }

    // Диск корня: df раз в 30 с, пока нужен.
    Timer {
        running: root.active && root.diskUsers > 0
        interval: 30000
        repeat: true
        triggeredOnStart: true
        onTriggered: df.running = true
    }
    Process {
        id: df
        command: ["df", "-B1", "--output=size,used,avail", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split("\n").pop().trim().split(/\s+/).map(Number);
                if (f.length < 3 || !f[0]) return;
                root.diskTotal = f[0];
                // «занято» как в df: от доступного пользователю места
                root.diskUsed = f[0] - f[2];
                root.disk = 100 * root.diskUsed / f[0];
            }
        }
    }
}
