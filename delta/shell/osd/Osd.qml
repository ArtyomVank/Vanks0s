pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import qs.common
import qs.common.ui
import qs.display
import qs.docks
import qs.docks.parts

// Индикатор громкости, яркости и раскладки: шарик выскакивает из дока
// приложений и раскрывается в пилюлю со значком и полоской уровня.
// Громкость и яркость меняет сам (PipeWire, display/Brightness):
//     Shortcuts { onVolume: a => osd.volume(a); onBrightness: a => osd.brightness(a) }
Scope {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [root.sink, root.source].filter(x => x !== null) }

    readonly property real step: 0.05

    // Вложенная сессия делит PipeWire с основной: там громкость не меняем,
    // только показываем, какой она стала бы (как Brightness).
    readonly property bool dryRun: (Quickshell.env("DELTA_NESTED") || "") !== ""
                                   || Quickshell.env("DELTA_DRY_RUN") === "1"

    // up | down | mute | mic
    function volume(action) {
        if (action === "mic") {
            if (!source?.audio) return;
            const m = !source.audio.muted;
            if (dryRun) console.info("[delta] микрофон (проверка): " + (m ? "выкл" : "вкл"));
            else source.audio.muted = m;
            show("mic", source.audio.volume, m);
            return;
        }
        if (!sink?.audio) return;
        const a = sink.audio;
        let muted = dryRun && DockService.previewMuted !== null ? DockService.previewMuted : a.muted, vol = a.volume;
        if (action === "mute") muted = !muted;
        else {
            muted = false;
            vol = Math.max(0, Math.min(1, Math.round((vol + (action === "up" ? step : -step)) * 100) / 100));
        }
        if (dryRun && action !== "mute") DockService.previewMuted = muted;
        if (dryRun) console.info("[delta] громкость (проверка): " + Math.round(vol * 100) + (muted ? ", без звука" : ""));
        else { a.muted = muted; a.volume = vol; }
        // Включение и выключение звука показывает остров верхнего дока
        // (DockService сам замечает смену; во вложенной сессии — подсказываем).
        if (action === "mute") {
            if (dryRun) { DockService.previewMuted = muted; DockService.showNotice("mute", muted); }
            return;
        }
        show("volume", vol, muted);
        // щелчок громкости — уже новой громкостью (колесом и клавишами не трещит)
        Sounds.play("audio-volume-change", 90);
    }
    // up | down
    function brightness(action) {
        if (!Brightness.available) return;
        show("brightness", Brightness.step(action === "up" ? step : -step), false);
    }

    // kind: volume | mic | brightness | lang
    property string kind: "volume"
    property real value: 0
    property bool muted: false
    property bool want: false
    function show(k, v, m) {
        if (Settings.get("osd.enabled", true) === false && k !== "lang") return;
        kind = k;
        value = Math.max(0, Math.min(1, v));
        muted = m === true;
        if (!want) target = DockService.focusedScreen();
        want = true;
        hideTimer.restart();
    }
    Timer { id: hideTimer; interval: root.kind === "lang" ? 1100 : 1500; onTriggered: root.want = false }

    Connections {
        target: KbLayout
        function onSwitched() { if (Settings.get("osd.layout", true) !== false) root.show("lang", 0, false); }
    }

    property ShellScreen target: null
    property bool alive: false
    onWantChanged: if (want) alive = true

    LazyLoader {
        active: root.alive && root.target !== null

        PanelWindow {
            id: win
            screen: root.target

            readonly property var geo: ShellState.dockGeometry[screen?.name ?? ""] ?? ({})
            readonly property var apps: geo.apps ?? ({ edge: "bottom", x: 0, y: 0, w: 0, h: 0, shown: false })
            readonly property string edge: apps.edge || "bottom"
            readonly property bool vertical: edge === "left" || edge === "right"
            readonly property real sw: screen?.width ?? 0
            readonly property real sh: screen?.height ?? 0
            // от края — над доком приложений, если он виден, иначе прямо у края
            readonly property real reach: !apps.shown ? 14
                : edge === "bottom" ? sh - apps.y : edge === "top" ? apps.y + apps.h
                : edge === "left" ? apps.x + apps.w : sw - apps.x

            WlrLayershell.namespace: "delta-osd"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            anchors { top: edge === "top"; bottom: edge === "bottom"; left: edge === "left"; right: edge === "right" }
            margins { top: edge === "top" ? reach + 12 : 0; bottom: edge === "bottom" ? reach + 12 : 0; left: edge === "left" ? reach + 12 : 0; right: edge === "right" ? reach + 12 : 0 }
            implicitWidth: 380
            implicitHeight: 100
            color: "transparent"
            // индикатор не мешает нажатиям
            mask: Region {}

            readonly property bool lang: root.kind === "lang"
            readonly property string icon: root.kind === "brightness" ? "sun"
                : root.kind === "mic" ? (root.muted ? "mic-off" : "mic")
                : root.kind === "lang" ? "keyboard"
                : root.muted || root.value <= 0.001 ? "volume-mute" : root.value < 0.4 ? "volume-low" : "volume"
            readonly property int percent: Math.round(root.value * 100)

            Blob {
                id: blob
                width: win.lang ? Math.max(150, langRow.implicitWidth + 40) : 320
                height: 56
                radiusOpen: 28
                x: win.vertical ? (win.edge === "left" ? 10 : parent.width - width - 10) : (parent.width - width) / 2
                y: win.vertical ? (parent.height - height) / 2 : (win.edge === "top" ? 10 : parent.height - height - 10)
                open: root.want
                dirX: win.edge === "left" ? -1 : win.edge === "right" ? 1 : 0
                dirY: win.edge === "top" ? -1 : win.edge === "bottom" ? 1 : 0
                // капля выходит из края дока приложений (он сам вздувается)
                srcX: win.edge === "left" ? -12 - x : win.edge === "right" ? win.width + 12 - x : win.width / 2 - x
                srcY: win.edge === "top" ? -12 - y : win.edge === "bottom" ? win.height + 12 - y : win.height / 2 - y
                pullKey: (win.screen?.name ?? "") + "/@osd"
                screenOffset: Qt.point(win.edge === "left" ? win.reach + 12 : win.edge === "right" ? win.sw - win.reach - 12 - win.width : (win.sw - win.width) / 2,
                                       win.edge === "top" ? win.reach + 12 : win.edge === "bottom" ? win.sh - win.reach - 12 - win.height : (win.sh - win.height) / 2)
                onClosed: if (!root.want) root.alive = false

                Row {
                    visible: !win.lang
                    anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                    spacing: 14
                    Sym { anchors.verticalCenter: parent.verticalCenter; name: win.icon; size: 22; color: Theme.fg }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 22 - 34 - 28
                        height: 8
                        radius: 4
                        color: Theme.soft2
                        Rectangle {
                            width: Math.max(root.value > 0 ? height : 0, parent.width * root.value)
                            height: parent.height
                            radius: 4
                            color: root.muted ? Theme.fg3 : Theme.accent
                            Behavior on width { NumberAnimation { duration: 250 * Theme.anim.k; easing.type: Easing.OutCubic } }
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        horizontalAlignment: Text.AlignRight
                        text: root.muted ? "—" : win.percent
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                    }
                }

                Row {
                    id: langRow
                    visible: win.lang
                    anchors.centerIn: parent
                    spacing: 10
                    Sym { anchors.verticalCenter: parent.verticalCenter; name: "keyboard"; size: 22; color: Theme.fg }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: KbLayout.short; font.weight: Font.ExtraBold; size: "title" }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: KbLayout.title; tone: 2 }
                }
            }
        }
    }
}
