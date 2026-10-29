pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import qs.common
import "media.js" as Media

// Обои на фоновом слое одного монитора. Без выбранного файла — градиент из
// темы и акцента. Смена картинки — плавное перетекание.
//
// Видеообои играет QtMultimedia (бэкенд FFmpeg сам берёт аппаратное
// декодирование, если оно есть): по кругу, без звука. Пауза, когда на этом
// мониторе окно на весь экран, экран заблокирован, слой скрыт или (по
// настройке) компьютер работает от батареи. Под видео всегда лежит кадр-
// заставка, поэтому до первого кадра и при выключенных видеообоях не пусто.
PanelWindow {
    id: root

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "delta-wallpaper"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.base

    readonly property string file: Settings.get("wallpaper.path", "")
    readonly property string fill: Settings.get("wallpaper.fill", "cover")
    readonly property bool isVideo: file.length > 0 && videoFile(file)
    readonly property bool allowVideo: Settings.get("wallpaper.allowVideo", true) !== false
    readonly property bool pauseOnBattery: Settings.get("wallpaper.pauseOnBattery", true) !== false

    // --- когда видео не нужно крутить ---
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property bool covered: monitor?.activeWorkspace?.hasFullscreen ?? false
    readonly property bool playing: isVideo && allowVideo && visible && !covered
        && !ShellState.locked && !(pauseOnBattery && UPower.onBattery)

    // Hyprland не всегда присылает событие о полноэкранном режиме вместе с
    // обновлением стола — перечитываем столы сами.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "fullscreen") Hyprland.refreshWorkspaces();
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0; color: Qt.darker(Theme.accent, 1.6) }
            GradientStop { position: 0.55; color: Theme.base }
            GradientStop { position: 1; color: Qt.darker(Theme.base, 1.4) }
        }
    }

    // два слоя для перетекания: новая картинка проявляется поверх старой
    property bool frontIsA: true

    Image {
        id: imgA
        anchors.fill: parent
        asynchronous: true
        cache: false
        fillMode: root.fill === "contain" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
        sourceSize: Qt.size(root.width * root.devicePixelRatio, root.height * root.devicePixelRatio)
        opacity: root.frontIsA && status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.anim.slow; easing.type: Theme.anim.outCurve } }
    }
    Image {
        id: imgB
        anchors.fill: parent
        asynchronous: true
        cache: false
        fillMode: imgA.fillMode
        sourceSize: imgA.sourceSize
        opacity: !root.frontIsA && status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.anim.slow; easing.type: Theme.anim.outCurve } }
    }

    property string shownUrl: ""
    function showImage(url) {
        if (url === shownUrl) return;
        shownUrl = url;
        if (frontIsA) { imgB.source = url; frontIsA = false; }
        else          { imgA.source = url; frontIsA = true; }
    }

    // --- кадр-заставка для видео (кэшируется, ffmpeg) ---
    readonly property string posterDir: Quickshell.cachePath("wallpaper")
    Process {
        id: poster
        property string forFile
        property string out
        stdout: StdioCollector {
            onStreamFinished: {
                if (poster.forFile !== root.file || text.trim() !== "ok") return;
                root.showImage(Media.fileUrl(poster.out));
                // кадр видеообоев нужен и экрану блокировки, и экрану входа
                if (Settings.get("wallpaper.poster", "") !== poster.out) Settings.set("wallpaper.poster", poster.out);
            }
        }
    }
    function makePoster(f) {
        poster.running = false;
        poster.forFile = f;
        poster.out = posterDir + "/poster-" + Qt.md5(f) + ".jpg";
        // новее файла — берём из кэша; иначе кадр с 1-й секунды (или первый, если видео короче)
        poster.command = ["sh", "-c",
            "mkdir -p \"$1\"; out=$2; f=$3; " +
            "if [ ! -s \"$out\" ] || [ \"$f\" -nt \"$out\" ]; then " +
            "  command -v ffmpeg >/dev/null || exit 0; " +
            "  ffmpeg -v error -nostdin -y -ss 1 -i \"$f\" -frames:v 1 -vf 'scale=1920:-2' -q:v 3 \"$out.tmp.jpg\" </dev/null; " +
            "  [ -s \"$out.tmp.jpg\" ] || ffmpeg -v error -nostdin -y -i \"$f\" -frames:v 1 -vf 'scale=1920:-2' -q:v 3 \"$out.tmp.jpg\" </dev/null; " +
            "  [ -s \"$out.tmp.jpg\" ] && mv -f \"$out.tmp.jpg\" \"$out\"; " +
            "fi; [ -s \"$out\" ] && echo ok",
            "sh", posterDir, poster.out, f];
        poster.running = true;
    }

    // isVideo здесь не читаем: в обработчике onFileChanged привязка может быть ещё старой
    function videoFile(f) { return Media.isVideo(f) || Settings.get("wallpaper.video", false) === true; }
    function apply() {
        if (!file) { showImage(""); return; }
        if (videoFile(file)) makePoster(file);
        else showImage(Media.fileUrl(file));
    }
    onFileChanged: apply()
    onIsVideoChanged: Qt.callLater(apply)
    Component.onCompleted: apply()

    // --- видео ---
    Loader {
        id: video
        anchors.fill: parent
        active: root.isVideo && root.allowVideo
        // показываем, только когда пошли кадры, — иначе мигнёт чёрным
        opacity: item && item.hasFrame ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.anim.slow; easing.type: Theme.anim.outCurve } }

        sourceComponent: Item {
            id: vbox
            property bool hasFrame: false

            MediaPlayer {
                id: player
                source: Media.fileUrl(root.file)
                loops: MediaPlayer.Infinite
                videoOutput: out
                // audioOutput не задан — звука нет вовсе
                onPlaybackStateChanged: if (playbackState === MediaPlayer.PlayingState) frameDelay.restart()
                onSourceChanged: vbox.hasFrame = false
                onErrorOccurred: (error, message) => console.warn("[delta] видеообои: " + message)
            }
            Timer { id: frameDelay; interval: 120; onTriggered: vbox.hasFrame = true }

            VideoOutput {
                id: out
                anchors.fill: parent
                fillMode: root.fill === "contain" ? VideoOutput.PreserveAspectFit : VideoOutput.PreserveAspectCrop
            }

            function sync() {
                if (root.playing) player.play();
                else if (player.playbackState === MediaPlayer.PlayingState) player.pause();
            }
            Connections {
                target: root
                function onPlayingChanged() { vbox.sync(); }
            }
            Component.onCompleted: sync()
        }
    }

    // Правый щелчок по свободному месту рабочего стола — меню «виджеты, обои,
    // настройки» (wallpaper/DesktopMenu.qml). Виджеты лежат слоем выше и свои
    // щелчки забирают сами, сюда доходят только щелчки мимо окон и виджетов.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: m => {
            if (m.button === Qt.RightButton) ShellState.openDesktopMenu(root.screen, m.x, m.y);
            else ShellState.closeDesktopMenu();
        }
    }
}
