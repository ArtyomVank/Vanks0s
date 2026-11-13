pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.common
import qs.common.ui
import qs.settings.parts

// Файлы Delta (delta-files): проводник со встроенным архиватором.
// Слева — места и диски, сверху — путь крошками (двойной щелчок или Ctrl+L —
// ввести путь), в середине — плитки или список. Архив открывается как папка
// (как в 7-Zip): внутри можно ходить, открыть файл, распаковать всё или
// выделенное. Распаковка, сжатие и вставка — delta-files с ключами, в фоне,
// с ходом в строке состояния. Удаление — в корзину (gio trash).
FloatingWindow {
    id: win

    readonly property string home: Quickshell.env("HOME") || "/"
    property string path: home
    property var back: []
    property var fwd: []

    // архив, открытый как папка: файл, его записи и папка внутри него
    property string archive: ""
    property var arcEntries: []
    property string arcDir: ""
    property bool arcLoading: false
    property string arcPassword: ""

    property string view: Settings.get("files.view", "grid")
    property bool hidden: false
    property string filter: ""
    property int sortBy: 0               // 0 — имя, 1 — дата, 2 — размер
    property var selected: ({})
    property int anchorIndex: -1
    property var clip: ({ mode: "", paths: [] })

    // фоновая работа: что идёт, ход, ошибка
    property string jobText: ""
    property int jobProgress: -1
    property string notice: ""
    property bool noticeBad: false

    title: archive ? baseName(archive) + " — " + I18n.tr("Файлы") : (path === home ? I18n.tr("Домашняя папка") : baseName(path)) + " — " + I18n.tr("Файлы")
    implicitWidth: 1080
    implicitHeight: 700
    minimumSize: Qt.size(640, 420)
    color: "transparent"
    onClosed: Qt.quit()

    // ---------- пути и типы ----------
    function baseName(p) { const s = p.replace(/\/+$/, ""); return s.slice(s.lastIndexOf("/") + 1) || "/"; }
    function parentOf(p) { const s = p.replace(/\/+$/, ""); const i = s.lastIndexOf("/"); return i <= 0 ? "/" : s.slice(0, i); }
    function join(a, b) { return a === "/" ? "/" + b : a + "/" + b; }
    function url(p) { return "file://" + p.split("/").map(encodeURIComponent).join("/"); }
    function ext(name) {
        const l = name.toLowerCase();
        for (const e of [".tar.gz", ".tar.xz", ".tar.bz2", ".tar.zst", ".tar.lz4"]) if (l.endsWith(e)) return e.slice(1);
        const i = l.lastIndexOf(".");
        return i > 0 ? l.slice(i + 1) : "";
    }
    readonly property var arcExts: ["zip", "7z", "rar", "tar", "tar.gz", "tar.xz", "tar.bz2", "tar.zst", "tar.lz4", "tgz", "tbz", "tbz2", "txz", "tzst",
        "iso", "cab", "cpio", "deb", "rpm", "xar", "lha", "lzh", "jar", "apk", "zipx", "cbz", "cbr", "cb7", "gz", "bz2", "xz", "zst", "lz4", "lzma", "whl", "xpi"]
    readonly property var imgExts: ["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "avif", "tif", "tiff", "ico", "jxl", "heic"]
    readonly property var vidExts: ["mp4", "mkv", "webm", "avi", "mov", "m4v", "wmv", "flv", "mpg", "mpeg", "ts", "m2ts", "3gp", "ogv"]
    readonly property var audExts: ["mp3", "flac", "ogg", "opus", "wav", "m4a", "aac", "wma", "aiff"]
    readonly property var docExts: ["txt", "md", "log", "conf", "ini", "json", "xml", "yaml", "yml", "csv", "sh", "py", "js", "qml", "rs", "c", "cpp", "h", "java", "kt", "html", "css", "toml", "lua"]
    function kindOf(it) {
        if (it.dir) return "dir";
        const e = ext(it.name);
        if (imgExts.indexOf(e) !== -1) return "image";
        if (vidExts.indexOf(e) !== -1) return "video";
        if (audExts.indexOf(e) !== -1) return "audio";
        if (arcExts.indexOf(e) !== -1) return "archive";
        if (e === "pdf") return "pdf";
        if (e === "exe" || e === "msi" || e === "bat" || e === "lnk") return "exe";
        if (docExts.indexOf(e) !== -1) return "text";
        return "file";
    }
    readonly property var themeIcon: ({ dir: "folder", image: "image-x-generic", video: "video-x-generic", audio: "audio-x-generic",
        archive: "package-x-generic", pdf: "application-pdf", exe: "application-x-ms-dos-executable", text: "text-x-generic", file: "text-x-generic" })
    readonly property var symIcon: ({ dir: "folder", image: "image", video: "video", audio: "music", archive: "archive", pdf: "file",
        exe: "windows", text: "file", file: "file" })
    function sizeText(b) {
        if (b >= 1073741824) return (b / 1073741824).toFixed(1).replace(".", ",") + " " + I18n.tr("ГБ");
        if (b >= 1048576) return (b / 1048576).toFixed(1).replace(".", ",") + " " + I18n.tr("МБ");
        if (b >= 1024) return Math.round(b / 1024) + " " + I18n.tr("КБ");
        return b + " " + I18n.tr("Б");
    }
    function dateText(d) {
        if (!d) return "";
        const now = new Date();
        if (d.toDateString() === now.toDateString()) return I18n.tr("Сегодня") + ", " + Qt.formatTime(d, "hh:mm");
        return Qt.formatDateTime(d, d.getFullYear() === now.getFullYear() ? "d MMM, hh:mm" : "d MMM yyyy");
    }

    // ---------- переходы ----------
    function go(p, keepFwd) {
        if (p === path && !archive) return;
        back = back.concat([archive ? { archive: archive, arcDir: arcDir, path: path } : { path: path }]);
        if (!keepFwd) fwd = [];
        closeArchive();
        path = p;
        clearSel();
    }
    function restore(st) {
        if (st.archive) { path = st.path; openArchive(st.archive, true); arcDir = st.arcDir; }
        else { closeArchive(); path = st.path; }
        clearSel();
    }
    function here() { return archive ? { archive: archive, arcDir: arcDir, path: path } : { path: path }; }
    function goBack() {
        if (!back.length) return;
        fwd = fwd.concat([here()]);
        const st = back[back.length - 1];
        back = back.slice(0, -1);
        restore(st);
    }
    function goFwd() {
        if (!fwd.length) return;
        back = back.concat([here()]);
        const st = fwd[fwd.length - 1];
        fwd = fwd.slice(0, -1);
        restore(st);
    }
    function goUp() {
        if (archive) {
            if (arcDir) { arcDir = arcDir.indexOf("/") === -1 ? "" : arcDir.slice(0, arcDir.lastIndexOf("/")); clearSel(); }
            else { closeArchive(); clearSel(); }
            return;
        }
        if (path !== "/") go(parentOf(path));
    }

    // ---------- архив как папка ----------
    function openArchive(file, quiet) {
        if (!quiet) back = back.concat([here()]);
        archive = file;
        arcDir = "";
        arcEntries = [];
        arcLoading = true;
        arcPassword = "";
        path = parentOf(file);
        clearSel();
        lister.command = ["delta-files", "--list", file];
        lister.running = true;
    }
    function closeArchive() { archive = ""; arcEntries = []; arcDir = ""; arcLoading = false; }
    Process {
        id: lister
        environment: ({ DELTA_FILES_PASSWORD: win.arcPassword })
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {}, out = [];
                for (const line of text.split("\n")) {
                    const f = line.split("\t");
                    if (f.length < 3 || !f[2]) continue;
                    const p = f[2].replace(/^\.\//, "").replace(/\/+$/, "");
                    if (!p) continue;
                    // папки, которых нет отдельной записью, — по путям файлов
                    const parts = p.split("/");
                    for (let i = 1; i < parts.length; i++) {
                        const d = parts.slice(0, i).join("/");
                        if (!seen[d]) { seen[d] = true; out.push({ t: "d", s: 0, p: d }); }
                    }
                    if (seen[p]) continue;
                    seen[p] = true;
                    out.push({ t: f[0], s: parseInt(f[1]) || 0, p: p });
                }
                win.arcEntries = out;
                win.arcLoading = false;
            }
        }
        onExited: code => {
            if (code !== 0 && win.archive) {
                win.arcLoading = false;
                win.say(I18n.tr("Не удалось прочитать архив — он повреждён или этот формат не поддерживается"), true);
            }
        }
    }

    // ---------- содержимое ----------
    FolderListModel {
        id: folder
        folder: win.url(win.path)
        showDirsFirst: true
        showHidden: win.hidden
        showDotAndDotDot: false
        sortCaseSensitive: false
        sortField: [FolderListModel.Name, FolderListModel.Time, FolderListModel.Size][win.sortBy]
        sortReversed: win.sortBy !== 0
        onStatusChanged: if (status === FolderListModel.Ready) win.rebuild()
        onCountChanged: rebuildTimer.restart()
    }
    Timer { id: rebuildTimer; interval: 60; onTriggered: win.rebuild() }
    property var items: []
    function rebuild() {
        if (archive) return;
        const out = [];
        for (let i = 0; i < folder.count; i++) {
            out.push({ name: folder.get(i, "fileName"), path: folder.get(i, "filePath"), dir: folder.get(i, "fileIsDir"),
                       size: folder.get(i, "fileSize"), mtime: folder.get(i, "fileModified") });
        }
        items = out;
        if (pendingSelect) { const p = pendingSelect; pendingSelect = ""; selectOnly(p); }
    }
    property string pendingSelect: ""
    readonly property var arcItems: {
        if (!archive) return [];
        const pre = arcDir ? arcDir + "/" : "";
        const out = [];
        for (const e of arcEntries) {
            if (!e.p.startsWith(pre)) continue;
            const rest = e.p.slice(pre.length);
            if (!rest || rest.indexOf("/") !== -1) continue;
            out.push({ name: rest, path: e.p, dir: e.t === "d", size: e.s, mtime: null, inArc: true });
        }
        out.sort((a, b) => (a.dir === b.dir ? a.name.localeCompare(b.name) : (a.dir ? -1 : 1)));
        return out;
    }
    readonly property var shown: {
        const src = archive ? arcItems : items;
        const q = filter.trim().toLowerCase();
        return q ? src.filter(it => it.name.toLowerCase().indexOf(q) !== -1) : src;
    }

    // ---------- выделение ----------
    function clearSel() { selected = {}; anchorIndex = -1; }
    function selectOnly(p) { const s = {}; s[p] = true; selected = s; anchorIndex = shown.findIndex(it => it.path === p); }
    function toggle(p) { const s = Object.assign({}, selected); if (s[p]) delete s[p]; else s[p] = true; selected = s; }
    function selectRange(to) {
        const from = anchorIndex < 0 ? to : anchorIndex;
        const s = {};
        for (let i = Math.min(from, to); i <= Math.max(from, to); i++) s[shown[i].path] = true;
        selected = s;
    }
    function selectAll() { const s = {}; for (const it of shown) s[it.path] = true; selected = s; }
    readonly property var selItems: shown.filter(it => selected[it.path])
    function clickItem(index, mods) {
        const it = shown[index];
        if (mods & Qt.ControlModifier) { toggle(it.path); anchorIndex = index; }
        else if (mods & Qt.ShiftModifier) selectRange(index);
        else selectOnly(it.path);
    }

    // ---------- открыть ----------
    function open(it) {
        if (it.inArc) {
            if (it.dir) { arcDir = it.path; clearSel(); filter = ""; return; }
            extractEntries([it.path], openTmp(), true);
            return;
        }
        if (it.dir) { go(it.path); filter = ""; return; }
        if (kindOf(it) === "archive") { openArchive(it.path); filter = ""; return; }
        Quickshell.execDetached(["xdg-open", it.path]);
    }
    function openTmp() { return (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/delta/files-open/" + Date.now(); }

    // ---------- фоновая работа ----------
    function say(t, bad) { notice = t; noticeBad = !!bad; noticeTimer.restart(); }
    Timer { id: noticeTimer; interval: 5000; onTriggered: win.notice = "" }

    Process {
        id: job
        property string kind                 // extract · compress · paste · trash · plain
        property var retry: null              // распаковка, которой нужен пароль
        property bool openAfter: false
        property string done: ""
        property string err: ""
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("::progress:: ")) win.jobProgress = parseInt(line.slice(13)) || 0;
                else if (line.startsWith("::done:: ")) job.done = line.slice(9);
            }
        }
        stderr: SplitParser { onRead: line => { if (line.trim() && !line.startsWith("x ")) job.err = line.trim(); } }
        onExited: code => {
            const k = job.kind;
            win.jobText = "";
            win.jobProgress = -1;
            if (code === 3 && job.retry) { win.ask({ kind: "password", retry: job.retry }); return; }
            if (code !== 0) {
                Sounds.play("dialog-warning", 60);
                win.say((k === "extract" ? I18n.tr("Не удалось распаковать") : k === "compress" ? I18n.tr("Не удалось сжать")
                         : k === "trash" ? I18n.tr("Не удалось удалить") : I18n.tr("Не получилось")) + (job.err ? ": " + job.err : ""), true);
                return;
            }
            if (job.openAfter && job.done) { Quickshell.execDetached(["xdg-open", job.done]); return; }
            if (k === "extract") { Sounds.play("oobe-select", 60); win.say(I18n.tr("Распаковано: ") + win.baseName(job.done)); if (!win.archive) win.pendingSelect = job.done; }
            else if (k === "compress") { Sounds.play("oobe-select", 60); win.say(I18n.tr("Архив готов: ") + win.baseName(job.done)); win.pendingSelect = job.done; }
            rebuildTimer.restart();
        }
    }
    function runJob(kind, text, cmd, env, retry, openAfter) {
        if (job.running) { say(I18n.tr("Подождите — ещё идёт прошлая операция"), true); return; }
        job.kind = kind; job.retry = retry || null; job.openAfter = !!openAfter; job.done = ""; job.err = "";
        job.environment = env || ({ DELTA_FILES_PASSWORD: "" });
        jobText = text;
        jobProgress = kind === "extract" ? 0 : -1;
        job.command = cmd;
        job.running = true;
    }
    function extract(file, dest, smart, password) {
        const cmd = ["delta-files", "--extract", file, dest].concat(smart ? ["--smart"] : []);
        runJob("extract", I18n.tr("Распаковка ") + baseName(file), cmd, { DELTA_FILES_PASSWORD: password || "" },
               { file: file, dest: dest, smart: smart });
    }
    // записи из открытого архива: в папку рядом с ним, или во временную — открыть
    function extractEntries(entries, dest, openAfter, password) {
        let cmd = ["delta-files", "--extract", archive, dest];
        for (const e of entries) cmd = cmd.concat(["--entry", e]);
        runJob("extract", openAfter ? I18n.tr("Открываю ") + baseName(entries[0]) : I18n.tr("Распаковка ") + baseName(archive), cmd,
               { DELTA_FILES_PASSWORD: password || arcPassword }, { file: archive, dest: dest, entries: entries, openAfter: openAfter }, openAfter);
    }
    function retryWith(r, password) {
        if (r.entries) { arcPassword = password; extractEntries(r.entries, r.dest, r.openAfter, password); }
        else extract(r.file, r.dest, r.smart, password);
    }
    function compress(names, dir, name, fmt) {
        runJob("compress", I18n.tr("Сжатие в ") + name + "." + fmt,
               ["delta-files", "--compress", fmt, join(dir, name + "." + fmt), dir].concat(names));
    }
    function trash(paths) {
        if (!paths.length) return;
        Sounds.play("drop", 0);
        runJob("trash", I18n.tr("В корзину…"), ["gio", "trash", "--"].concat(paths));
        clearSel();
    }
    function paste() {
        if (!clip.paths.length || archive) return;
        runJob("paste", clip.mode === "move" ? I18n.tr("Перемещение…") : I18n.tr("Копирование…"),
               ["delta-files", "--paste", clip.mode === "move" ? "move" : "copy", path].concat(clip.paths));
        if (clip.mode === "move") clip = { mode: "", paths: [] };
    }
    function copySel(move) {
        const paths = selItems.map(it => it.path);
        if (!paths.length || archive) return;
        clip = { mode: move ? "move" : "copy", paths: paths };
        Quickshell.clipboardText = paths.join("\n");
        say((move ? I18n.tr("Вырезано: ") : I18n.tr("Скопировано: ")) + paths.length);
    }
    Process { id: plain; onExited: code => { if (code !== 0) win.say(I18n.tr("Не получилось — нет прав или имя занято"), true); rebuildTimer.restart(); } }
    function runPlain(cmd) { plain.command = cmd; plain.running = true; }

    // ---------- места ----------
    property var places: []
    Process {
        running: true
        command: ["sh", "-c", "for d in DESKTOP DOWNLOAD DOCUMENTS PICTURES MUSIC VIDEOS; do printf '%s\\t%s\\n' \"$d\" \"$(xdg-user-dir $d 2>/dev/null)\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = { DESKTOP: ["Рабочий стол", "monitor"], DOWNLOAD: ["Загрузки", "download"], DOCUMENTS: ["Документы", "file"],
                                PICTURES: ["Изображения", "image"], MUSIC: ["Музыка", "music"], VIDEOS: ["Видео", "video"] };
                const out = [{ title: I18n.tr("Домашняя папка"), icon: "home", path: win.home }];
                for (const l of text.split("\n")) {
                    const f = l.split("\t");
                    if (f.length < 2 || !f[1] || f[1] === win.home || f[1] === win.home + "/") continue;
                    out.push({ title: I18n.tr(names[f[0]][0]), icon: names[f[0]][1], path: f[1].replace(/\/+$/, "") });
                }
                win.places = out;
            }
        }
    }
    readonly property string trashDir: (Quickshell.env("XDG_DATA_HOME") || home + "/.local/share") + "/Trash/files"
    FolderListModel {
        id: drives
        folder: win.url("/run/media/" + (Quickshell.env("USER") || ""))
        showFiles: false
        showDotAndDotDot: false
    }

    // ---------- диалоги и меню ----------
    property var dialog: null           // { kind: rename|mkdir|compress|password|empty, … }
    function ask(d) { dialog = d; }
    property var menu: null             // { x, y, items: [{ text, icon, act, danger }] }

    function itemMenu(it, x, y) {
        if (!selected[it.path]) selectOnly(it.path);
        const many = selItems.length > 1;
        const l = [];
        if (it.inArc) {
            if (!many) l.push({ text: I18n.tr("Открыть"), icon: it.dir ? "folder" : "file", act: () => win.open(it) });
            l.push({ text: I18n.tr("Распаковать выделенное"), icon: "download",
                     act: () => win.extractEntries(win.selItems.map(s => s.path), win.path, false) });
            menu = { x: x, y: y, items: l };
            return;
        }
        if (!many) l.push({ text: I18n.tr("Открыть"), icon: it.dir ? "folder" : "file", act: () => win.open(it) });
        if (!many && kindOf(it) === "archive") {
            l.push({ text: I18n.tr("Распаковать сюда"), icon: "archive", act: () => win.extract(it.path, win.path, true) });
            l.push({ text: I18n.tr("Распаковать в «") + win.baseName(it.path).replace(/\.(tar\.)?[^.]+$/, "") + "»", icon: "folder-plus",
                     act: () => win.extract(it.path, win.path, false) });
        }
        if (!many && !it.dir && kindOf(it) !== "archive")
            l.push({ text: I18n.tr("Открыть в другой программе"), icon: "apps", act: () => Quickshell.execDetached(["xdg-open", it.path]) });
        l.push({ text: I18n.tr("Сжать…"), icon: "archive", act: () => win.ask({ kind: "compress", fmt: "zip",
                 name: many ? win.baseName(win.path) : it.name.replace(/\.[^.]+$/, "") || it.name, names: win.selItems.map(s => s.name) }) });
        l.push({ sep: true });
        l.push({ text: I18n.tr("Копировать"), icon: "copy", act: () => win.copySel(false) });
        l.push({ text: I18n.tr("Вырезать"), icon: "edit", act: () => win.copySel(true) });
        if (!many) l.push({ text: I18n.tr("Переименовать"), icon: "edit", act: () => win.ask({ kind: "rename", item: it, name: it.name }) });
        l.push({ text: I18n.tr("Копировать путь"), icon: "link", act: () => { Quickshell.clipboardText = win.selItems.map(s => s.path).join("\n"); } });
        l.push({ sep: true });
        l.push({ text: win.path === win.trashDir ? I18n.tr("Удалить навсегда") : I18n.tr("В корзину"), icon: "trash", danger: true,
                 act: () => win.path === win.trashDir ? win.ask({ kind: "erase", paths: win.selItems.map(s => s.path) }) : win.trash(win.selItems.map(s => s.path)) });
        menu = { x: x, y: y, items: l };
    }
    function bgMenu(x, y) {
        clearSel();
        if (archive) {
            menu = { x: x, y: y, items: [
                { text: I18n.tr("Распаковать всё сюда"), icon: "archive", act: () => win.extract(win.archive, win.path, true) },
                { text: I18n.tr("Закрыть архив"), icon: "close", act: () => win.goUp() }
            ] };
            return;
        }
        const l = [{ text: I18n.tr("Новая папка"), icon: "folder-plus", act: () => win.ask({ kind: "mkdir", name: I18n.tr("Новая папка") }) }];
        if (clip.paths.length) l.push({ text: I18n.tr("Вставить") + " (" + clip.paths.length + ")", icon: "copy", act: () => win.paste() });
        l.push({ text: I18n.tr("Выделить всё"), icon: "check", act: () => win.selectAll() });
        l.push({ sep: true });
        l.push({ text: win.hidden ? I18n.tr("Не показывать скрытые") : I18n.tr("Показать скрытые"), icon: win.hidden ? "eye-off" : "eye",
                 act: () => { win.hidden = !win.hidden; } });
        l.push({ text: I18n.tr("Открыть в терминале"), icon: "terminal",
                 act: () => Quickshell.execDetached(["sh", "-c", "cd \"$1\" && exec xdg-terminal-exec", "sh", win.path]) });
        if (path === trashDir) l.push({ text: I18n.tr("Очистить корзину"), icon: "trash", danger: true, act: () => win.ask({ kind: "empty" }) });
        menu = { x: x, y: y, items: l };
    }

    Component.onCompleted: {
        const p = Quickshell.env("DELTA_FILES_OPEN") || "";
        if (!p) return;
        if (Quickshell.env("DELTA_FILES_KIND") === "file") {
            if (kindOf({ name: baseName(p), dir: false }) === "archive") openArchive(p, true);
            else { path = parentOf(p); pendingSelect = p; }
        } else path = p;
    }

    // ================= вид =================
    Rectangle {
        id: frame
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.glass2
        border.width: 1
        border.color: Theme.line
        clip: true

        focus: true
        Keys.onPressed: event => win.key(event)

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ---------- места ----------
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 212
                color: Theme.soft
                Flickable {
                    anchors { fill: parent; margins: 12 }
                    contentHeight: side.implicitHeight
                    clip: true
                    ColumnLayout {
                        id: side
                        width: parent.width
                        spacing: 2
                        RowLayout {
                            spacing: 10
                            Layout.margins: 6
                            Layout.bottomMargin: 12
                            Rectangle {
                                implicitWidth: 34; implicitHeight: 34; radius: 11
                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2)
                                Sym { anchors.centerIn: parent; name: "folder"; size: 18; color: Theme.accent }
                            }
                            Label { text: I18n.tr("Файлы"); size: "title"; font.weight: Font.DemiBold }
                        }
                        Repeater {
                            model: win.places
                            delegate: PlaceRow {}
                        }
                        PlaceRow { modelData: ({ title: I18n.tr("Корзина"), icon: "trash", path: win.trashDir }) }
                        Label { text: I18n.tr("Диски"); tone: 3; size: "caption"; Layout.topMargin: 14; Layout.leftMargin: 10; Layout.bottomMargin: 4 }
                        PlaceRow { modelData: ({ title: I18n.tr("Система"), icon: "disk", path: "/" }) }
                        Repeater {
                            model: drives
                            delegate: PlaceRow {
                                required property string fileName
                                required property string filePath
                                modelData: ({ title: fileName, icon: "disk", path: filePath })
                            }
                        }
                    }
                }
            }
            Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Theme.line }

            // ---------- основная часть ----------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // панель: назад/вперёд/вверх, путь, поиск, вид
                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 12
                    spacing: 6
                    Btn { icon: "chevron-left"; kind: "ghost"; enabled: win.back.length > 0; onClicked: win.goBack() }
                    Btn { icon: "chevron-right"; kind: "ghost"; enabled: win.fwd.length > 0; onClicked: win.goFwd() }
                    Btn { icon: "chevron-up"; kind: "ghost"; enabled: win.archive !== "" || win.path !== "/"; onClicked: win.goUp() }

                    // путь крошками; двойной щелчок — ввести вручную
                    Rectangle {
                        id: crumbBox
                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: 12
                        color: Theme.soft2
                        border.width: 1
                        border.color: pathField.visible ? Theme.accent : Theme.line
                        property bool editing: false
                        Flickable {
                            id: crumbFlick
                            visible: !crumbBox.editing
                            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                            contentWidth: crumbs.implicitWidth
                            flickableDirection: Flickable.HorizontalFlick
                            clip: true
                            onContentWidthChanged: contentX = Math.max(0, contentWidth - width)
                            Row {
                                id: crumbs
                                height: parent.height
                                spacing: 0
                                Repeater {
                                    model: win.crumbList
                                    delegate: Row {
                                        id: cr
                                        required property var modelData
                                        required property int index
                                        height: crumbs.height
                                        Sym { visible: cr.index > 0; name: "chevron-right"; size: 12; color: Theme.fg3; anchors.verticalCenter: parent.verticalCenter }
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            implicitWidth: crl.implicitWidth + (crs.visible ? 26 : 16)
                                            implicitHeight: 28
                                            radius: 9
                                            color: crh.hovered ? Theme.soft : "transparent"
                                            Sym { id: crs; visible: !!cr.modelData.icon; name: cr.modelData.icon || ""; size: 14; color: Theme.fg2
                                                  anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter } }
                                            Label {
                                                id: crl
                                                anchors { left: crs.visible ? crs.right : parent.left; leftMargin: crs.visible ? 5 : 8; verticalCenter: parent.verticalCenter }
                                                text: cr.modelData.title
                                                font.weight: cr.index === win.crumbList.length - 1 ? Font.DemiBold : Font.Normal
                                            }
                                            HoverHandler { id: crh; cursorShape: Qt.PointingHandCursor }
                                            TapHandler { onTapped: win.crumbGo(cr.modelData) }
                                        }
                                    }
                                }
                            }
                            TapHandler {
                                acceptedButtons: Qt.LeftButton
                                onDoubleTapped: crumbBox.startEdit()
                            }
                        }
                        function startEdit() {
                            if (win.archive) return;
                            editing = true;
                            pathField.text = win.path;
                            pathField.forceActiveFocus();
                            pathField.selectAll();
                        }
                        TextInput {
                            id: pathField
                            visible: crumbBox.editing
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.fg
                            selectionColor: Theme.accent
                            selectedTextColor: Theme.onAccent
                            font.family: Theme.font
                            font.pixelSize: 14
                            clip: true
                            onAccepted: {
                                let p = text.trim().replace(/^~(?=\/|$)/, win.home);
                                crumbBox.editing = false;
                                frame.forceActiveFocus();
                                if (p) win.go(p.replace(/\/+$/, "") || "/");
                            }
                            onActiveFocusChanged: if (!activeFocus) crumbBox.editing = false
                            Keys.onEscapePressed: { crumbBox.editing = false; frame.forceActiveFocus(); }
                        }
                    }

                    Field {
                        id: search
                        implicitWidth: 200
                        icon: "search"
                        placeholder: I18n.tr("Поиск в папке")
                        clearable: true
                        onEdited: win.filter = text
                        Connections { target: win; function onPathChanged() { search.text = ""; } function onArcDirChanged() { search.text = ""; } }
                    }
                    Btn {
                        icon: win.view === "grid" ? "list" : "grid"
                        kind: "ghost"
                        onClicked: { win.view = win.view === "grid" ? "list" : "grid"; Settings.set("files.view", win.view); }
                    }
                    Btn {
                        icon: "sliders"
                        kind: "ghost"
                        onClicked: {
                            const p = mapToItem(frame, 0, height + 4);
                            win.menu = { x: p.x - 160, y: p.y, items: [
                                { text: I18n.tr("По имени"), icon: win.sortBy === 0 ? "check" : "", act: () => { win.sortBy = 0; } },
                                { text: I18n.tr("Сначала новые"), icon: win.sortBy === 1 ? "check" : "", act: () => { win.sortBy = 1; } },
                                { text: I18n.tr("Сначала большие"), icon: win.sortBy === 2 ? "check" : "", act: () => { win.sortBy = 2; } },
                                { sep: true },
                                { text: I18n.tr("Скрытые файлы"), icon: win.hidden ? "check" : "", act: () => { win.hidden = !win.hidden; } }
                            ] };
                        }
                    }
                }

                // полоса архива: что открыто и «Распаковать»
                Rectangle {
                    visible: win.archive !== ""
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.bottomMargin: 8
                    implicitHeight: 52
                    radius: 14
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                    border.width: 1
                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                    RowLayout {
                        anchors { fill: parent; leftMargin: 14; rightMargin: 8 }
                        spacing: 10
                        Sym { name: "archive"; size: 20; color: Theme.accent }
                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            Label { text: win.baseName(win.archive); font.weight: Font.DemiBold; elide: Text.ElideMiddle; Layout.fillWidth: true }
                            Label {
                                text: win.arcLoading ? I18n.tr("Читаю архив…")
                                    : win.arcEntries.filter(e => e.t !== "d").length + " " + I18n.tr("файлов") + " · "
                                      + win.sizeText(win.arcEntries.reduce((a, e) => a + e.s, 0)) + " " + I18n.tr("без сжатия")
                                tone: 3; size: "small"
                            }
                        }
                        Btn {
                            visible: win.selItems.length > 0
                            text: I18n.tr("Распаковать выделенное")
                            icon: "download"
                            onClicked: win.extractEntries(win.selItems.map(s => s.path), win.path, false)
                        }
                        Btn { text: I18n.tr("Распаковать всё"); icon: "archive"; kind: "accent"; onClicked: win.extract(win.archive, win.path, true) }
                        Btn { icon: "close"; kind: "ghost"; onClicked: win.goUp() }
                    }
                }

                // ---------- файлы ----------
                Item {
                    id: area
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onPressed: mouse => {
                            frame.forceActiveFocus();
                            if (mouse.button === Qt.RightButton) { const p = mapToItem(frame, mouse.x, mouse.y); win.bgMenu(p.x, p.y); }
                            else win.clearSel();
                        }
                    }

                    GridView {
                        id: grid
                        visible: win.view === "grid"
                        anchors { fill: parent; leftMargin: 12; rightMargin: 4 }
                        cellWidth: Math.floor((width - 8) / Math.max(1, Math.floor((width - 8) / 118)))
                        cellHeight: 128
                        model: visible ? win.shown : []
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: true
                        delegate: Tile {}
                        footer: Item { height: 12 }
                    }
                    ListView {
                        id: list
                        visible: win.view === "list"
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        model: visible ? win.shown : []
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        spacing: 2
                        header: RowLayout {
                            width: list.width
                            height: 30
                            spacing: 12
                            Item { implicitWidth: 26 }
                            Label { text: I18n.tr("Имя"); tone: 3; size: "caption"; Layout.fillWidth: true }
                            Label { text: I18n.tr("Изменён"); tone: 3; size: "caption"; Layout.preferredWidth: 150; visible: !win.archive }
                            Label { text: I18n.tr("Размер"); tone: 3; size: "caption"; Layout.preferredWidth: 90; horizontalAlignment: Text.AlignRight }
                            Item { implicitWidth: 4 }
                        }
                        delegate: Row_ {}
                    }

                    // пусто, читается, ошибка
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: win.shown.length === 0
                        spacing: 8
                        Sym {
                            Layout.alignment: Qt.AlignHCenter
                            name: win.arcLoading ? "refresh" : win.filter ? "search" : "folder"
                            size: 40
                            color: Theme.fg3
                            RotationAnimation on rotation { running: win.arcLoading; from: 0; to: 360; duration: 1200; loops: Animation.Infinite }
                        }
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: win.arcLoading ? I18n.tr("Читаю архив…") : win.filter ? I18n.tr("Ничего не нашлось") : I18n.tr("Папка пуста")
                            tone: 3
                        }
                    }
                }

                // ---------- строка состояния ----------
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    color: "transparent"
                    Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: Theme.line }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                        spacing: 12
                        Label {
                            text: {
                                const n = win.shown.length, s = win.selItems;
                                let t = n + " " + I18n.tr("объектов");
                                if (s.length) {
                                    const bytes = s.filter(it => !it.dir).reduce((a, it) => a + it.size, 0);
                                    t += " · " + I18n.tr("выделено ") + s.length + (bytes ? " (" + win.sizeText(bytes) + ")" : "");
                                }
                                return t;
                            }
                            tone: 3; size: "small"
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            visible: win.notice !== "" && win.jobText === ""
                            text: win.notice
                            size: "small"
                            color: win.noticeBad ? "#ff6b6b" : Theme.fg2
                            elide: Text.ElideRight
                            Layout.maximumWidth: 460
                        }
                        RowLayout {
                            visible: win.jobText !== ""
                            spacing: 10
                            Sym {
                                name: "refresh"; size: 14; color: Theme.accent
                                RotationAnimation on rotation { running: win.jobText !== ""; from: 0; to: 360; duration: 1200; loops: Animation.Infinite }
                            }
                            Label { text: win.jobText + (win.jobProgress > 0 ? " · " + win.jobProgress + "%" : ""); size: "small"; tone: 2 }
                            Rectangle {
                                visible: win.jobProgress >= 0
                                implicitWidth: 140; implicitHeight: 6; radius: 3
                                color: Theme.soft2
                                Rectangle {
                                    width: parent.width * Math.max(0, win.jobProgress) / 100
                                    height: parent.height; radius: 3
                                    color: Theme.accent
                                    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---------- меню ----------
        MouseArea {
            anchors.fill: parent
            visible: win.menu !== null
            acceptedButtons: Qt.AllButtons
            onPressed: win.menu = null
        }
        Rectangle {
            id: menuBox
            visible: win.menu !== null
            readonly property var m: win.menu ?? ({ x: 0, y: 0, items: [] })
            x: Math.max(8, Math.min(m.x, frame.width - width - 8))
            y: Math.max(8, Math.min(m.y, frame.height - height - 8))
            width: 250
            height: menuCol.implicitHeight + 12
            radius: 16
            color: Theme.glass2
            border.width: 1
            border.color: Theme.line
            scale: visible ? 1 : 0.92
            transformOrigin: Item.TopLeft
            Behavior on scale { NumberAnimation { duration: Theme.anim.fast; easing.type: Easing.OutBack } }
            Sheen { radius: parent.radius; strength: 0.6 }
            Column {
                id: menuCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                Repeater {
                    model: menuBox.m.items
                    delegate: Item {
                        id: mi
                        required property var modelData
                        width: menuCol.width
                        height: modelData.sep ? 9 : 36
                        Rectangle { visible: !!mi.modelData.sep; anchors.centerIn: parent; width: parent.width - 16; height: 1; color: Theme.line }
                        Rectangle {
                            visible: !mi.modelData.sep
                            anchors.fill: parent
                            radius: 10
                            color: mih.hovered ? (mi.modelData.danger ? Qt.rgba(1, 0.42, 0.42, 0.16) : Theme.soft2) : "transparent"
                            RowLayout {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                spacing: 10
                                Item {
                                    implicitWidth: 18; implicitHeight: 18
                                    Sym { anchors.centerIn: parent; visible: !!mi.modelData.icon; name: mi.modelData.icon || ""; size: 16
                                          color: mi.modelData.danger ? "#ff6b6b" : Theme.fg2 }
                                }
                                Label { text: mi.modelData.text || ""; Layout.fillWidth: true; elide: Text.ElideRight
                                        color: mi.modelData.danger ? "#ff6b6b" : Theme.fg }
                            }
                            HoverHandler { id: mih }
                            TapHandler {
                                onTapped: {
                                    const f = mi.modelData.act;
                                    win.menu = null;
                                    if (f) f();
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---------- диалог ----------
        Rectangle {
            anchors.fill: parent
            visible: win.dialog !== null
            color: Qt.rgba(0, 0, 0, 0.35)
            radius: Theme.radius
            MouseArea { anchors.fill: parent; onPressed: win.dialog = null }
            Rectangle {
                id: dlg
                anchors.centerIn: parent
                width: 420
                height: dlgCol.implicitHeight + 40
                radius: 22
                color: Theme.glass2
                border.width: 1
                border.color: Theme.line
                MouseArea { anchors.fill: parent }
                readonly property var d: win.dialog ?? ({ kind: "" })
                readonly property bool needsName: d.kind === "rename" || d.kind === "mkdir" || d.kind === "compress" || d.kind === "password"
                onDChanged: if (needsName) {
                    dlgField.text = d.kind === "password" ? "" : (d.name || "");
                    Qt.callLater(() => {
                        dlgField.focusInput();
                        // имя без расширения — выделено, как в Windows
                        const n = dlgField.text, dot = d.kind === "rename" && !d.item?.dir ? n.lastIndexOf(".") : -1;
                        if (dot > 0) dlgField.input.select(0, dot); else dlgField.input.selectAll();
                    });
                }
                function accept() {
                    const v = dlgField.text.trim(), dd = d;
                    if (needsName && !v) return;
                    if (needsName && dd.kind !== "password" && (v.indexOf("/") !== -1 || v === "." || v === "..")) { dlgField.error = true; return; }
                    win.dialog = null;
                    frame.forceActiveFocus();
                    if (dd.kind === "rename") { if (v !== dd.item.name) win.runPlain(["mv", "-n", "--", dd.item.path, win.join(win.parentOf(dd.item.path), v)]); win.pendingSelect = win.join(win.parentOf(dd.item.path), v); }
                    else if (dd.kind === "mkdir") { win.runPlain(["mkdir", "--", win.join(win.path, v)]); win.pendingSelect = win.join(win.path, v); }
                    else if (dd.kind === "compress") win.compress(dd.names, win.path, v, dd.fmt);
                    else if (dd.kind === "password") win.retryWith(dd.retry, dlgField.text);
                    else if (dd.kind === "empty") win.runJob("trash", I18n.tr("Очистка корзины…"), ["gio", "trash", "--empty"]);
                    else if (dd.kind === "erase") { win.runJob("trash", I18n.tr("Удаление…"), ["rm", "-rf", "--"].concat(dd.paths)); win.clearSel(); }
                }
                ColumnLayout {
                    id: dlgCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                    spacing: 14
                    Label {
                        text: ({ rename: I18n.tr("Переименовать"), mkdir: I18n.tr("Новая папка"), compress: I18n.tr("Сжать в архив"),
                                 password: I18n.tr("Архив защищён паролем"), empty: I18n.tr("Очистить корзину?"),
                                 erase: I18n.tr("Удалить навсегда?") })[dlg.d.kind] ?? ""
                        size: "title"; font.weight: Font.DemiBold
                    }
                    Label {
                        visible: text !== ""
                        text: dlg.d.kind === "empty" ? I18n.tr("Все файлы в корзине будут удалены без возможности восстановления.")
                            : dlg.d.kind === "erase" ? I18n.tr("Выделенные файлы будут удалены без возможности восстановления.")
                            : dlg.d.kind === "password" ? I18n.tr("Введите пароль, чтобы распаковать.") : ""
                        tone: 3; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    Field {
                        id: dlgField
                        visible: dlg.needsName
                        Layout.fillWidth: true
                        password: dlg.d.kind === "password"
                        onAccepted: dlg.accept()
                        onEdited: error = false
                        Keys.onEscapePressed: { win.dialog = null; frame.forceActiveFocus(); }
                    }
                    Chips {
                        visible: dlg.d.kind === "compress"
                        model: [{ value: "zip", label: "ZIP" }, { value: "7z", label: "7z" }, { value: "tar.zst", label: "tar.zst" }, { value: "tar.gz", label: "tar.gz" }]
                        current: dlg.d.fmt ?? "zip"
                        onPicked: v => { win.dialog = Object.assign({}, win.dialog, { fmt: v, name: dlgField.text }); }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Item { Layout.fillWidth: true }
                        Btn { text: I18n.tr("Отмена"); kind: "ghost"; onClicked: { win.dialog = null; frame.forceActiveFocus(); } }
                        Btn {
                            text: dlg.d.kind === "empty" || dlg.d.kind === "erase" ? I18n.tr("Удалить") : dlg.d.kind === "compress" ? I18n.tr("Сжать")
                                : dlg.d.kind === "password" ? I18n.tr("Распаковать") : dlg.d.kind === "mkdir" ? I18n.tr("Создать") : I18n.tr("Готово")
                            kind: dlg.d.kind === "empty" || dlg.d.kind === "erase" ? "danger" : "accent"
                            onClicked: dlg.accept()
                        }
                    }
                }
            }
        }
    }

    // ---------- крошки пути ----------
    readonly property var crumbList: {
        const out = [];
        let base = "/", rest = path;
        if (path === home || path.startsWith(home + "/")) { out.push({ title: I18n.tr("Домашняя"), icon: "home", path: home }); base = home; rest = path.slice(home.length); }
        else if (path === trashDir) return [{ title: I18n.tr("Корзина"), icon: "trash", path: trashDir }];
        else out.push({ title: I18n.tr("Система"), icon: "disk", path: "/" });
        let acc = base;
        for (const s of rest.split("/").filter(x => x)) { acc = join(acc, s); out.push({ title: s, path: acc }); }
        if (archive) {
            out.push({ title: baseName(archive), icon: "archive", arc: "" });
            let a = "";
            for (const s of arcDir.split("/").filter(x => x)) { a = a ? a + "/" + s : s; out.push({ title: s, arc: a }); }
        }
        return out;
    }
    function crumbGo(c) {
        if (c.arc !== undefined) { arcDir = c.arc; clearSel(); return; }
        if (archive) { back = back.concat([here()]); closeArchive(); path = c.path; clearSel(); return; }
        go(c.path);
    }

    // ---------- клавиши ----------
    function key(e) {
        const ctrl = e.modifiers & Qt.ControlModifier, alt = e.modifiers & Qt.AltModifier;
        const cur = anchorIndex;
        const cols = view === "grid" ? Math.max(1, Math.floor(grid.width / grid.cellWidth)) : 1;
        const moveTo = i => {
            if (!shown.length) return;
            i = Math.max(0, Math.min(shown.length - 1, i));
            if (e.modifiers & Qt.ShiftModifier) selectRange(i); else selectOnly(shown[i].path);
            anchorIndex = (e.modifiers & Qt.ShiftModifier) ? anchorIndex : i;
            (view === "grid" ? grid : list).positionViewAtIndex(i, GridView.Contain);
        };
        if (e.key === Qt.Key_Backspace || (alt && e.key === Qt.Key_Up)) goUp();
        else if (alt && e.key === Qt.Key_Left) goBack();
        else if (alt && e.key === Qt.Key_Right) goFwd();
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { if (selItems.length === 1) open(selItems[0]); }
        else if (e.key === Qt.Key_Delete) { if (!archive && selItems.length) { if (path === trashDir || (e.modifiers & Qt.ShiftModifier)) ask({ kind: "erase", paths: selItems.map(s => s.path) }); else trash(selItems.map(s => s.path)); } }
        else if (e.key === Qt.Key_F2) { if (!archive && selItems.length === 1) ask({ kind: "rename", item: selItems[0], name: selItems[0].name }); }
        else if (e.key === Qt.Key_F5) { if (archive) openArchive(archive, true); else rebuild(); }
        else if (ctrl && e.key === Qt.Key_A) selectAll();
        else if (ctrl && e.key === Qt.Key_C) copySel(false);
        else if (ctrl && e.key === Qt.Key_X) copySel(true);
        else if (ctrl && e.key === Qt.Key_V) paste();
        else if (ctrl && e.key === Qt.Key_H) hidden = !hidden;
        else if (ctrl && e.key === Qt.Key_L) crumbBox.startEdit();
        else if (ctrl && e.key === Qt.Key_F) search.focusInput();
        else if (ctrl && e.modifiers & Qt.ShiftModifier && e.key === Qt.Key_N) { if (!archive) ask({ kind: "mkdir", name: I18n.tr("Новая папка") }); }
        else if (e.key === Qt.Key_Right) moveTo(cur + 1);
        else if (e.key === Qt.Key_Left) moveTo(cur - 1);
        else if (e.key === Qt.Key_Down) moveTo(cur < 0 ? 0 : cur + cols);
        else if (e.key === Qt.Key_Up) moveTo(cur - cols);
        else if (e.key === Qt.Key_Escape) { if (menu) menu = null; else clearSel(); }
        else return;
        e.accepted = true;
    }

    // ================= части =================
    component PlaceRow: Rectangle {
        id: pr
        required property var modelData
        readonly property bool here: !win.archive && win.path === (modelData?.path ?? "")
        Layout.fillWidth: true
        implicitHeight: 36
        radius: 11
        color: here ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2) : prh.hovered ? Theme.soft2 : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
        RowLayout {
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            spacing: 10
            Sym { name: pr.modelData?.icon ?? "folder"; size: 16; color: pr.here ? Theme.accent : Theme.fg2 }
            Label { text: pr.modelData?.title ?? ""; Layout.fillWidth: true; elide: Text.ElideRight; font.weight: pr.here ? Font.DemiBold : Font.Normal }
        }
        HoverHandler { id: prh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { win.go(pr.modelData.path); frame.forceActiveFocus(); } }
    }

    // значок файла: миниатюра картинки, значок темы или свой
    component FileIcon: Item {
        id: fi
        property var item
        property int size: 48
        property bool thumb: false
        readonly property string kind: item ? win.kindOf(item) : "file"
        readonly property string themed: Quickshell.iconPath(win.themeIcon[kind] ?? "", true)
        implicitWidth: size; implicitHeight: size
        Image {
            id: th
            anchors.fill: parent
            visible: fi.thumb && fi.kind === "image" && !fi.item.inArc && status === Image.Ready
            source: visible || (fi.thumb && fi.kind === "image" && !fi.item.inArc) ? win.url(fi.item.path) : ""
            sourceSize: Qt.size(fi.size * 2, fi.size * 2)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
            smooth: true
        }
        IconImage {
            id: ti
            anchors.fill: parent
            visible: !th.visible && fi.themed !== "" && status === Image.Ready
            source: fi.themed
            asynchronous: true
        }
        Rectangle {
            anchors.fill: parent
            visible: !th.visible && !ti.visible
            radius: fi.size * 0.28
            color: fi.kind === "dir" ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22) : Theme.soft2
            Sym { anchors.centerIn: parent; name: win.symIcon[fi.kind] ?? "file"; size: fi.size * 0.5; color: fi.kind === "dir" ? Theme.accent : Theme.fg2 }
        }
    }

    component Tile: Item {
        id: tile
        required property var modelData
        required property int index
        readonly property bool sel: !!win.selected[modelData.path]
        readonly property bool cut: win.clip.mode === "move" && win.clip.paths.indexOf(modelData.path) !== -1
        width: grid.cellWidth
        height: grid.cellHeight
        Rectangle {
            anchors { fill: parent; margins: 4 }
            radius: 16
            color: tile.sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22) : tma.containsMouse ? Theme.soft : "transparent"
            border.width: tile.sel ? 1 : 0
            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5)
            Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
            opacity: tile.cut ? 0.5 : 1
            FileIcon {
                id: tic
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 10 }
                item: tile.modelData
                size: 56
                thumb: true
            }
            Label {
                anchors { left: parent.left; right: parent.right; top: tic.bottom; topMargin: 6; leftMargin: 6; rightMargin: 6 }
                text: tile.modelData.name
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 2
                elide: Text.ElideMiddle
                size: "small"
            }
        }
        MouseArea {
            id: tma
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: mouse => {
                frame.forceActiveFocus();
                if (mouse.button === Qt.RightButton) { const p = mapToItem(frame, mouse.x, mouse.y); win.itemMenu(tile.modelData, p.x, p.y); }
                else win.clickItem(tile.index, mouse.modifiers);
            }
            onDoubleClicked: mouse => { if (mouse.button === Qt.LeftButton) win.open(tile.modelData); }
        }
    }

    component Row_: Rectangle {
        id: rw
        required property var modelData
        required property int index
        readonly property bool sel: !!win.selected[modelData.path]
        width: list.width
        height: 38
        radius: 10
        color: sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22) : rma.containsMouse ? Theme.soft : "transparent"
        opacity: win.clip.mode === "move" && win.clip.paths.indexOf(modelData.path) !== -1 ? 0.5 : 1
        RowLayout {
            anchors { fill: parent; leftMargin: 8; rightMargin: 12 }
            spacing: 12
            FileIcon { item: rw.modelData; size: 24 }
            Label { text: rw.modelData.name; Layout.fillWidth: true; elide: Text.ElideMiddle }
            Label { visible: !win.archive; text: win.dateText(rw.modelData.mtime); tone: 3; size: "small"; Layout.preferredWidth: 150 }
            Label {
                text: rw.modelData.dir ? "" : win.sizeText(rw.modelData.size)
                tone: 3; size: "small"; Layout.preferredWidth: 90; horizontalAlignment: Text.AlignRight
            }
        }
        MouseArea {
            id: rma
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: mouse => {
                frame.forceActiveFocus();
                if (mouse.button === Qt.RightButton) { const p = mapToItem(frame, mouse.x, mouse.y); win.itemMenu(rw.modelData, p.x, p.y); }
                else win.clickItem(rw.index, mouse.modifiers);
            }
            onDoubleClicked: mouse => { if (mouse.button === Qt.LeftButton) win.open(rw.modelData); }
        }
    }
}
