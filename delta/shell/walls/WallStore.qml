pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import "../wallpaper/media.js" as Media

// Папка с обоями: список файлов, миниатюры и основной цвет каждого файла.
//
// Миниатюры (384 px) делает ffmpeg — и для картинок, и для видео, — в
// ~/.cache; цвет считает ColorQuantizer уже по миниатюре и тоже кэшируется.
// Поэтому повторное открытие выбора обоев ничего не пересчитывает.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    // папка из настроек или по умолчанию: «Изображения/Обои», если есть, иначе «Изображения»
    property string defaultFolder: ""
    readonly property string folder: {
        const f = String(Settings.get("wallpaper.folder", "") || "");
        return f.startsWith("~/") ? home + f.slice(1) : (f || defaultFolder);
    }

    // [{ path, name, video, key, thumb, mtime }]
    property var items: []
    property bool scanning: false
    property bool folderMissing: false
    // key → true, когда миниатюра готова
    property var thumbs: ({})
    // key → { b: "violet", c: "#rrggbb", v: версия групп }
    property var colors: ({})

    readonly property string thumbDir: Quickshell.cachePath("walls")
    readonly property var buckets: [
        { id: "red",    label: "Красные",    color: "#FF4A1C" },
        { id: "orange", label: "Оранжевые",  color: "#FFA200" },
        { id: "yellow", label: "Жёлтые",     color: "#FFD60A" },
        { id: "green",  label: "Зелёные",    color: "#30C93B" },
        { id: "blue",   label: "Синие",      color: "#1E8EFF" },
        { id: "violet", label: "Фиолетовые", color: "#8A2BE2" },
        { id: "pink",   label: "Розовые",    color: "#FF6EB4" },
        { id: "gray",   label: "Серые",      color: "#A8A8A8" }
    ]
    // версия набора групп: цвета из старого кэша раскладываются по новым
    readonly property int bucketsVersion: 2

    function pretty(p) { return Media.pretty(p, home); }

    // --- папка по умолчанию ---
    Process {
        running: true
        command: ["sh", "-c",
            "p=$(xdg-user-dir PICTURES 2>/dev/null); " +
            "if [ -z \"$p\" ] || [ \"$p\" = \"$HOME\" ]; then for d in \"$HOME/Изображения\" \"$HOME/Pictures\"; do [ -d \"$d\" ] && p=$d && break; done; fi; " +
            "[ -n \"$p\" ] || p=\"$HOME/Pictures\"; " +
            "if [ -d \"$p/Обои\" ]; then echo \"$p/Обои\"; elif [ -d \"$p/Wallpapers\" ]; then echo \"$p/Wallpapers\"; else echo \"$p\"; fi"]
        stdout: StdioCollector { onStreamFinished: root.defaultFolder = text.trim() }
    }

    // --- список файлов ---
    property bool wanted: false     // кто-то открыл выбор или включена смена по таймеру
    function scan() {
        wanted = true;
        if (!folder) return;
        scanProc.running = false;
        scanProc.running = true;
    }
    onFolderChanged: if (wanted) scan()

    Process {
        id: scanProc
        command: ["sh", "-c",
            "[ -d \"$1\" ] || { echo MISSING; exit 0; }; " +
            "find -L \"$1\" -maxdepth 3 -type d -name '.*' -prune -o -type f -printf '%T@\\t%s\\t%p\\n' 2>/dev/null",
            "sh", root.folder]
        onStarted: root.scanning = true
        stdout: StdioCollector {
            onStreamFinished: {
                root.scanning = false;
                if (text.trim() === "MISSING") {
                    root.folderMissing = true;
                    root.items = [];
                    return;
                }
                root.folderMissing = false;
                const out = [];
                for (const line of text.split("\n")) {
                    const parts = line.split("\t");
                    if (parts.length < 3) continue;
                    const path = parts.slice(2).join("\t");
                    const video = Media.isVideo(path);
                    if (!video && !Media.isImage(path)) continue;
                    const key = Qt.md5(path + "|" + parts[0] + "|" + parts[1]);
                    out.push({ path, name: Media.baseName(path), video, key, thumb: root.thumbDir + "/" + key + ".jpg", mtime: Number(parts[0]) || 0 });
                }
                out.sort((a, b) => a.name.localeCompare(b.name));
                root.items = out;
                root.makeThumbs();
            }
        }
    }

    // --- миниатюры: по 3 файла параллельно, готовые печатают свой ключ ---
    function makeThumbs() {
        const args = [];
        for (const it of items) args.push(it.key, it.path, it.video ? "1" : "0");
        if (args.length === 0) return;
        thumbProc.running = false;
        thumbProc.command = ["sh", "-c",
            "d=$1; shift; mkdir -p \"$d\"; " +
            "while [ $# -ge 3 ]; do printf '%s\\0%s\\0%s\\0' \"$1\" \"$2\" \"$3\"; shift 3; done | " +
            "xargs -0 -n3 -P3 sh -c '" +
            "out=\"$0/$1.jpg\"; " +
            "if [ ! -s \"$out\" ]; then " +
            "  t=\"$out.tmp.jpg\"; " +
            "  if [ \"$3\" = 1 ]; then ffmpeg -v error -nostdin -y -ss 1 -i \"$2\" -frames:v 1 -vf scale=384:-2 -q:v 5 \"$t\" </dev/null; fi; " +
            "  [ -s \"$t\" ] || ffmpeg -v error -nostdin -y -i \"$2\" -frames:v 1 -vf scale=384:-2 -q:v 5 \"$t\" </dev/null; " +
            "  [ -s \"$t\" ] || magick \"$2[0]\" -thumbnail 384x \"$t\" 2>/dev/null; " +
            "  [ -s \"$t\" ] && mv -f \"$t\" \"$out\"; " +
            "fi; " +
            "[ -s \"$out\" ] && echo \"$1\"' \"$d\"",
            "sh", thumbDir].concat(args);
        thumbProc.running = true;
    }

    property var pendingThumbs: []
    Process {
        id: thumbProc
        stdout: SplitParser {
            onRead: line => {
                root.pendingThumbs.push(line.trim());
                if (!thumbFlush.running) thumbFlush.start();
            }
        }
    }
    // пачками раз в 120 мс, чтобы сетка не перестраивалась на каждый файл
    Timer {
        id: thumbFlush
        interval: 120
        onTriggered: {
            const t = Object.assign({}, root.thumbs);
            for (const k of root.pendingThumbs) {
                t[k] = true;
                if (!root.colors[k]) root.colorQueue.push(k);
            }
            root.pendingThumbs = [];
            root.thumbs = t;
            root.nextColor();
        }
    }

    // --- основной цвет ---
    FileView {
        id: colorFile
        path: root.thumbDir + "/colors.json"
        printErrors: false
        onLoaded: {
            try {
                const old = JSON.parse(text()) || {};
                // кэш со старыми группами — пересчитать группу по сохранённому цвету
                for (const k in old) {
                    const e = old[k];
                    if (e && e.c && e.v !== root.bucketsVersion) old[k] = { b: root.bucketOf(Qt.color(e.c)), c: e.c, v: root.bucketsVersion };
                }
                root.colors = Object.assign(old, root.colors);
            } catch (e) {}
        }
    }
    Timer {
        id: colorSave
        interval: 1500
        onTriggered: colorFile.setText(JSON.stringify(root.colors))
    }

    property var colorQueue: []
    property string colorKey: ""

    function bucketOf(c) {
        const s = c.hsvSaturation, v = c.hsvValue;
        if (s < 0.2 || v < 0.16) return "gray";
        const h = c.hsvHue * 360;
        if (h < 14 || h >= 345) return "red";
        if (h < 40) return "orange";
        if (h < 68) return "yellow";
        if (h < 165) return "green";
        if (h < 250) return "blue";
        if (h < 292) return "violet";
        return "pink";
    }

    function classify(list) {
        // ColorQuantizer делит картинку на 4 примерно равные по числу точек группы —
        // побеждает цвет, который встречается в группах чаще; при равенстве — более яркий
        const votes = {};
        let best = null, bestScore = -1, bestColor = null;
        for (const c of list) {
            const b = bucketOf(c);
            votes[b] = (votes[b] || 0) + 1;
        }
        for (const c of list) {
            const b = bucketOf(c);
            const sc = votes[b] * 10 + (b === "gray" ? 0 : c.hsvSaturation * c.hsvValue * 5);
            if (sc > bestScore) { bestScore = sc; best = b; bestColor = c; }
        }
        return best ? { b: best, c: bestColor.toString(), v: root.bucketsVersion } : null;
    }

    function nextColor() {
        if (colorKey !== "" || colorQueue.length === 0) return;
        colorKey = colorQueue.shift();
        quant.source = Media.fileUrl(thumbDir + "/" + colorKey + ".jpg");
        colorWatchdog.restart();
    }
    function finishColor() {
        if (colorKey === "") return;
        colorWatchdog.stop();
        const r = classify(quant.colors);
        if (r) {
            const c = Object.assign({}, colors);
            c[colorKey] = r;
            colors = c;
            colorSave.restart();
        }
        colorKey = "";
        Qt.callLater(nextColor);
    }

    ColorQuantizer {
        id: quant
        depth: 2
        rescaleSize: 48
        onColorsChanged: if (root.colorKey !== "" && colors.length > 0) root.finishColor()
    }
    // одинаковый результат подряд не даёт сигнала — не застреваем
    Timer {
        id: colorWatchdog
        interval: 1500
        onTriggered: root.finishColor()
    }

    // --- применить ---
    function apply(item) {
        if (!item) return;
        // сначала признак видео, потом путь: обои реагируют на смену пути
        Settings.set("wallpaper.video", item.video);
        Settings.set("wallpaper.path", item.path);
    }
}
