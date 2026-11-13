pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.common
import qs.common.ui

// Видео Delta (delta-video): плеер на QtMultimedia (FFmpeg).
// Снизу — стеклянная панель: перемотка, пауза, соседние видео из той же
// папки, громкость, скорость, дорожки звука и субтитров, весь экран. Пока
// видео идёт, панель и курсор прячутся через пару секунд без движения.
// Клавиши: пробел/K — пауза, ←/→ — 5 с (с Shift — 30 с), ↑/↓ — громкость,
// F или двойной щелчок — весь экран, M — без звука, N/P — следующее/прошлое,
// [ и ] — скорость. Позиция каждого файла запоминается (video-resume.json).
FloatingWindow {
    id: win

    property string source: Quickshell.env("DELTA_VIDEO_OPEN") || ""
    readonly property bool isFile: source !== "" && source.indexOf("://") === -1
    readonly property string name: source ? decodeURIComponent(source.slice(source.lastIndexOf("/") + 1)) : ""
    property bool full: false
    property bool chrome: true            // панель видна
    property string osd: ""
    property string osdIcon: ""
    property var menu: null               // { kind: speed|audio|subs }
    property string error: ""

    title: name ? name + " — " + I18n.tr("Видео") : I18n.tr("Видео")
    implicitWidth: 1100
    implicitHeight: 660
    minimumSize: Qt.size(480, 300)
    color: "black"
    onClosed: { saveResume(); Qt.quit(); }

    function url(p) { return p.indexOf("://") !== -1 ? p : "file://" + p.split("/").map(encodeURIComponent).join("/"); }
    function dirOf(p) { const i = p.lastIndexOf("/"); return i <= 0 ? "/" : p.slice(0, i); }
    function time(ms) {
        if (!(ms > 0)) return "0:00";
        const s = Math.floor(ms / 1000), h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, ss = s % 60;
        return (h ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(ss).padStart(2, "0");
    }
    function flash(text, icon) { osd = text; osdIcon = icon || ""; osdTimer.restart(); }
    Timer { id: osdTimer; interval: 900; onTriggered: win.osd = "" }

    // ---------- плеер ----------
    MediaPlayer {
        id: player
        source: win.source ? win.url(win.source) : ""
        videoOutput: video
        audioOutput: AudioOutput {
            id: audio
            volume: Number(Settings.get("video.volume", 1))
            muted: false
        }
        onSourceChanged: { win.error = ""; win.resumed = false; }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.LoadedMedia && !win.resumed) {
                win.resumed = true;
                const at = win.resume[win.source] || 0;
                // начать с места, где остановились (если не у самого конца)
                if (at > 5000 && (duration <= 0 || at < duration - 10000)) { position = at; win.flash(I18n.tr("Продолжаю с ") + win.time(at), "play"); }
                play();
            }
            if (mediaStatus === MediaPlayer.EndOfMedia) {
                delete win.resume[win.source];
                if (win.index >= 0 && win.index < win.siblings.length - 1) win.step(1);
                else win.chrome = true;
            }
        }
        onErrorOccurred: (err, text) => { win.error = text || I18n.tr("Не удалось открыть видео"); }
    }
    property bool resumed: false

    // где остановились: { путь: мс }
    property var resume: ({})
    FileView {
        id: resumeFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/delta/video-resume.json"
        blockLoading: true
        printErrors: false
        onLoaded: { try { win.resume = JSON.parse(text()) || {}; } catch (e) { win.resume = {}; } }
    }
    function saveResume() {
        if (!isFile) return;
        if (player.duration > 60000 && player.position > 5000 && player.position < player.duration - 10000) resume[source] = player.position;
        else delete resume[source];
        // не больше 200 файлов
        const keys = Object.keys(resume);
        if (keys.length > 200) for (const k of keys.slice(0, keys.length - 200)) delete resume[k];
        resumeFile.setText(JSON.stringify(resume));
    }

    // ---------- соседние видео из той же папки ----------
    FolderListModel {
        id: siblingsModel
        folder: win.isFile ? win.url(win.dirOf(win.source)) : ""
        showDirs: false
        sortCaseSensitive: false
        nameFilters: ["*.mp4", "*.mkv", "*.webm", "*.avi", "*.mov", "*.m4v", "*.wmv", "*.flv", "*.mpg", "*.mpeg", "*.ts", "*.m2ts", "*.3gp", "*.ogv",
                      "*.MP4", "*.MKV", "*.WEBM", "*.AVI", "*.MOV", "*.M4V"]
        onCountChanged: win.collect()
        onStatusChanged: win.collect()
    }
    property var siblings: []
    function collect() {
        const l = [];
        for (let i = 0; i < siblingsModel.count; i++) l.push(siblingsModel.get(i, "filePath"));
        siblings = l;
    }
    readonly property int index: siblings.indexOf(source)
    function step(d) {
        const i = index + d;
        if (index < 0 || i < 0 || i >= siblings.length) return;
        saveResume();
        source = siblings[i];
        flash(name, d > 0 ? "next" : "prev");
    }

    // ---------- открыть файл ----------
    Process {
        id: picker
        command: ["zenity", "--file-selection", "--title=" + I18n.tr("Открыть видео"),
                  "--file-filter=" + I18n.tr("Видео") + " | *.mp4 *.mkv *.webm *.avi *.mov *.m4v *.wmv *.flv *.mpg *.mpeg *.ts *.m2ts *.3gp *.ogv",
                  "--file-filter=" + I18n.tr("Все файлы") + " | *"]
        stdout: StdioCollector { onStreamFinished: { const p = text.trim(); if (p) { win.saveResume(); win.source = p; } } }
    }

    // ---------- действия ----------
    function toggle() {
        if (!source) { picker.running = true; return; }
        if (player.playbackState === MediaPlayer.PlayingState) { player.pause(); flash("", "pause"); }
        else { player.play(); flash("", "play"); }
        poke();
    }
    function seek(ms) {
        if (!player.seekable) return;
        player.position = Math.max(0, Math.min(player.duration, player.position + ms));
        flash((ms > 0 ? "+" : "−") + Math.abs(ms / 1000) + " " + I18n.tr("с"), ms > 0 ? "next" : "prev");
        poke();
    }
    function setVolume(v) {
        audio.volume = Math.max(0, Math.min(1, v));
        audio.muted = false;
        Settings.set("video.volume", Math.round(audio.volume * 100) / 100);
        flash(Math.round(audio.volume * 100) + "%", audio.volume === 0 ? "volume-mute" : audio.volume < 0.5 ? "volume-low" : "volume");
    }
    readonly property var rates: [0.5, 0.75, 1, 1.25, 1.5, 2]
    function setRate(r) { player.playbackRate = r; flash("×" + String(r).replace(".", ","), "gauge"); }
    function fullscreen() {
        full = !full;
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.fullscreen()"]);
    }
    function poke() { chrome = true; hideTimer.restart(); }
    Timer {
        id: hideTimer
        interval: 2600
        onTriggered: if (player.playbackState === MediaPlayer.PlayingState && !win.menu && !barArea.containsMouse && !panelHover.hovered) win.chrome = false
    }

    // название дорожки: язык и название из метаданных
    function trackName(md, i) {
        if (!md) return I18n.tr("Дорожка ") + (i + 1);
        const lang = md.stringValue(MediaMetaData.Language), t = md.stringValue(MediaMetaData.Title);
        return [t, lang].filter(x => x).join(" · ") || I18n.tr("Дорожка ") + (i + 1);
    }

    // ================= вид =================
    Item {
        id: root
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => win.key(event)

        VideoOutput {
            id: video
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectFit
        }

        // движение мыши — показать панель; двойной щелчок — весь экран
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: win.chrome || !win.source ? Qt.ArrowCursor : Qt.BlankCursor
            onPositionChanged: win.poke()
            onClicked: mouse => {
                root.forceActiveFocus();
                if (win.menu) { win.menu = null; return; }
                if (mouse.button === Qt.LeftButton) win.toggle();
            }
            onDoubleClicked: mouse => { if (mouse.button === Qt.LeftButton) { win.toggle(); win.fullscreen(); } }
            onWheel: wheel => win.setVolume(audio.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
        }
        DropArea {
            anchors.fill: parent
            onDropped: drop => {
                if (!drop.hasUrls) return;
                const u = drop.urls[0].toString();
                win.saveResume();
                win.source = u.startsWith("file://") ? decodeURIComponent(u.slice(7)) : u;
            }
        }

        // пусто: открыть файл
        ColumnLayout {
            anchors.centerIn: parent
            visible: !win.source
            spacing: 14
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 84; implicitHeight: 84; radius: 28
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2)
                Sym { anchors.centerIn: parent; name: "video"; size: 40; color: Theme.accent }
            }
            Label { Layout.alignment: Qt.AlignHCenter; text: I18n.tr("Видео"); size: "h1"; color: "white" }
            Label { Layout.alignment: Qt.AlignHCenter; text: I18n.tr("Перетащите файл сюда или откройте его"); color: Qt.rgba(1, 1, 1, 0.7) }
            Btn { Layout.alignment: Qt.AlignHCenter; text: I18n.tr("Открыть видео"); icon: "file"; kind: "accent"; onClicked: picker.running = true }
        }

        // ошибка
        Rectangle {
            anchors.centerIn: parent
            visible: win.error !== ""
            width: Math.min(parent.width - 40, errText.implicitWidth + 60)
            height: 64
            radius: 20
            color: Qt.rgba(0, 0, 0, 0.6)
            RowLayout {
                anchors.centerIn: parent
                spacing: 10
                Sym { name: "warning"; size: 20; color: "#ff8a80" }
                Label { id: errText; text: win.error; color: "white" }
            }
        }

        // всплывающая подсказка по центру: пауза, перемотка, громкость
        Rectangle {
            anchors.centerIn: parent
            visible: opacity > 0
            opacity: win.osdIcon !== "" && osdTimer.running ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.anim.fast } }
            width: Math.max(96, osdRow.implicitWidth + 40)
            height: 96
            radius: 30
            color: Qt.rgba(0, 0, 0, 0.45)
            scale: opacity > 0 ? 1 : 0.85
            Behavior on scale { NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.OutBack } }
            RowLayout {
                id: osdRow
                anchors.centerIn: parent
                spacing: 12
                Sym { name: win.osdIcon; size: 36; color: "white" }
                Label { visible: win.osd !== ""; text: win.osd; size: "title"; color: "white"; font.weight: Font.DemiBold
                        Layout.maximumWidth: 420; elide: Text.ElideMiddle }
            }
        }

        // ---------- название сверху ----------
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 72
            visible: opacity > 0 && win.source !== ""
            opacity: win.chrome ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.anim.normal } }
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.55) }
                GradientStop { position: 1; color: "transparent" }
            }
            Label {
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
                text: win.name + (win.siblings.length > 1 && win.index >= 0 ? "   ·   " + (win.index + 1) + " / " + win.siblings.length : "")
                color: "white"
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
            }
        }

        // ---------- панель снизу ----------
        Rectangle {
            id: panel
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 18 }
            width: Math.min(parent.width - 36, 980)
            height: 96
            radius: 26
            visible: opacity > 0 && win.source !== ""
            opacity: win.chrome ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.anim.normal } }
            transform: Translate { y: win.chrome ? 0 : 16; Behavior on y { NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.OutCubic } } }
            color: Theme.glass2
            border.width: 1
            border.color: Theme.line
            Sheen { radius: parent.radius; strength: 0.7 }
            HoverHandler { id: panelHover }

            ColumnLayout {
                anchors { fill: parent; leftMargin: 18; rightMargin: 18; topMargin: 12; bottomMargin: 10 }
                spacing: 6

                // перемотка: тонкая полоса, при наведении толще и с временем под курсором
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Label { text: win.time(bar.dragging ? bar.dragMs : player.position); num: true; size: "small"; tone: 2 }
                    Item {
                        id: bar
                        Layout.fillWidth: true
                        implicitHeight: 22
                        property bool dragging: false
                        property real dragMs: 0
                        readonly property real ratio: player.duration > 0 ? (dragging ? dragMs : player.position) / player.duration : 0
                        Rectangle {
                            id: track
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                            height: barArea.containsMouse || bar.dragging ? 8 : 5
                            Behavior on height { NumberAnimation { duration: Theme.anim.fast } }
                            radius: height / 2
                            color: Theme.soft2
                            Rectangle {
                                // буфер
                                height: parent.height; radius: parent.radius
                                width: parent.width * Math.max(0, Math.min(1, player.bufferProgress))
                                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.12)
                                visible: player.bufferProgress < 1
                            }
                            Rectangle {
                                height: parent.height; radius: parent.radius
                                width: parent.width * Math.max(0, Math.min(1, bar.ratio))
                                color: Theme.accent
                            }
                        }
                        Rectangle {
                            x: track.width * Math.max(0, Math.min(1, bar.ratio)) - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: barArea.containsMouse || bar.dragging ? 16 : 0
                            height: width
                            radius: width / 2
                            color: "white"
                            Behavior on width { NumberAnimation { duration: Theme.anim.fast; easing.type: Easing.OutBack } }
                        }
                        // время под курсором
                        Rectangle {
                            visible: barArea.containsMouse && player.duration > 0
                            x: Math.max(0, Math.min(bar.width - width, barArea.mouseX - width / 2))
                            y: -height - 8
                            width: hoverTime.implicitWidth + 16
                            height: 26
                            radius: 9
                            color: Theme.glass2
                            border.width: 1
                            border.color: Theme.line
                            Label { id: hoverTime; anchors.centerIn: parent; num: true; size: "small"
                                    text: win.time(player.duration * Math.max(0, Math.min(1, barArea.mouseX / bar.width))) }
                        }
                        MouseArea {
                            id: barArea
                            anchors { fill: parent; topMargin: -6; bottomMargin: -6 }
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            function at(x) { return player.duration * Math.max(0, Math.min(1, x / bar.width)); }
                            onPressed: mouse => { bar.dragging = true; bar.dragMs = at(mouse.x); }
                            onPositionChanged: mouse => { if (bar.dragging) bar.dragMs = at(mouse.x); win.poke(); }
                            onReleased: mouse => { player.position = at(mouse.x); bar.dragging = false; }
                        }
                    }
                    Label { text: win.time(player.duration); num: true; size: "small"; tone: 2 }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Btn { icon: "prev"; kind: "ghost"; enabled: win.index > 0; onClicked: win.step(-1) }
                    Btn {
                        icon: player.playbackState === MediaPlayer.PlayingState ? "pause" : "play"
                        kind: "accent"
                        onClicked: win.toggle()
                    }
                    Btn { icon: "next"; kind: "ghost"; enabled: win.index >= 0 && win.index < win.siblings.length - 1; onClicked: win.step(1) }
                    Item { implicitWidth: 6 }
                    Btn {
                        icon: audio.muted || audio.volume === 0 ? "volume-mute" : audio.volume < 0.5 ? "volume-low" : "volume"
                        kind: "ghost"
                        onClicked: { audio.muted = !audio.muted; win.flash(audio.muted ? I18n.tr("Без звука") : Math.round(audio.volume * 100) + "%", audio.muted ? "volume-mute" : "volume"); }
                    }
                    Slider {
                        Layout.preferredWidth: 130
                        from: 0; to: 1
                        value: audio.muted ? 0 : audio.volume
                        onMoved: v => win.setVolume(v)
                    }
                    Item { Layout.fillWidth: true }
                    Btn {
                        text: "×" + String(player.playbackRate).replace(".", ",")
                        kind: "ghost"
                        onClicked: win.menu = win.menu?.kind === "speed" ? null : { kind: "speed" }
                    }
                    Btn {
                        visible: player.audioTracks.length > 1
                        icon: "waveform"
                        kind: "ghost"
                        onClicked: win.menu = win.menu?.kind === "audio" ? null : { kind: "audio" }
                    }
                    Btn {
                        visible: player.subtitleTracks.length > 0
                        icon: "subtitles"
                        kind: "ghost"
                        active: player.activeSubtitleTrack >= 0
                        onClicked: win.menu = win.menu?.kind === "subs" ? null : { kind: "subs" }
                    }
                    Btn { icon: win.full ? "fullscreen-exit" : "fullscreen"; kind: "ghost"; onClicked: win.fullscreen() }
                }
            }
        }

        // ---------- меню скорости и дорожек ----------
        Rectangle {
            id: menuBox
            visible: win.menu !== null && panel.visible
            anchors { right: panel.right; bottom: panel.top; bottomMargin: 10 }
            width: 240
            height: menuCol.implicitHeight + 12
            radius: 18
            color: Theme.glass2
            border.width: 1
            border.color: Theme.line
            readonly property var items: {
                const k = win.menu?.kind;
                if (k === "speed") return win.rates.map(r => ({ text: "×" + String(r).replace(".", ","), on: player.playbackRate === r, act: () => win.setRate(r) }));
                if (k === "audio") return player.audioTracks.map((md, i) => ({ text: win.trackName(md, i), on: player.activeAudioTrack === i, act: () => { player.activeAudioTrack = i; } }));
                if (k === "subs") return [{ text: I18n.tr("Выключены"), on: player.activeSubtitleTrack < 0, act: () => { player.activeSubtitleTrack = -1; } }]
                    .concat(player.subtitleTracks.map((md, i) => ({ text: win.trackName(md, i), on: player.activeSubtitleTrack === i, act: () => { player.activeSubtitleTrack = i; } })));
                return [];
            }
            Column {
                id: menuCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                Repeater {
                    model: menuBox.items
                    delegate: Rectangle {
                        id: mi
                        required property var modelData
                        width: menuCol.width
                        height: 36
                        radius: 11
                        color: mih.hovered ? Theme.soft2 : "transparent"
                        RowLayout {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            Label { text: mi.modelData.text; Layout.fillWidth: true; elide: Text.ElideRight; font.weight: mi.modelData.on ? Font.DemiBold : Font.Normal }
                            Sym { visible: mi.modelData.on; name: "check"; size: 16; color: Theme.accent }
                        }
                        HoverHandler { id: mih }
                        TapHandler { onTapped: { mi.modelData.act(); win.menu = null; win.poke(); } }
                    }
                }
            }
        }
    }

    // ---------- клавиши ----------
    function key(e) {
        const shift = e.modifiers & Qt.ShiftModifier;
        switch (e.key) {
        case Qt.Key_Space: case Qt.Key_K: toggle(); break;
        case Qt.Key_Right: seek(shift ? 30000 : 5000); break;
        case Qt.Key_Left: seek(shift ? -30000 : -5000); break;
        case Qt.Key_L: seek(10000); break;
        case Qt.Key_J: seek(-10000); break;
        case Qt.Key_Up: setVolume(audio.volume + 0.05); break;
        case Qt.Key_Down: setVolume(audio.volume - 0.05); break;
        case Qt.Key_F: case Qt.Key_F11: fullscreen(); break;
        case Qt.Key_Escape: if (menu) menu = null; else if (full) fullscreen(); break;
        case Qt.Key_M: audio.muted = !audio.muted; flash(audio.muted ? I18n.tr("Без звука") : Math.round(audio.volume * 100) + "%", audio.muted ? "volume-mute" : "volume"); break;
        case Qt.Key_N: case Qt.Key_PageDown: step(1); break;
        case Qt.Key_P: case Qt.Key_PageUp: step(-1); break;
        case Qt.Key_BracketRight: { const i = rates.indexOf(player.playbackRate); setRate(rates[Math.min(rates.length - 1, (i < 0 ? 2 : i) + 1)]); break; }
        case Qt.Key_BracketLeft: { const i = rates.indexOf(player.playbackRate); setRate(rates[Math.max(0, (i < 0 ? 2 : i) - 1)]); break; }
        case Qt.Key_Home: player.position = 0; break;
        case Qt.Key_O: if (e.modifiers & Qt.ControlModifier) picker.running = true; else return; break;
        default: return;
        }
        e.accepted = true;
    }
}
