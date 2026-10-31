import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.common
import qs.common.ui
import qs.docks
import qs.docks.parts

// Звук: значок по громкости; когда играет музыка — маленький эквалайзер.
// Колесо мыши меняет громкость выхода по умолчанию.
Item {
    id: root

    property bool vertical: false
    property bool full: true
    property ShellScreen screen
    property bool hidden: false

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false

    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    // Без звука ли — по PipeWire; во вложенной сессии звук по-настоящему не
    // выключается, и значок показывает, каким он стал бы (DockService.previewMuted).
    readonly property bool shownMuted: DockService.previewMuted !== null ? DockService.previewMuted : muted
    // колокольчик виден без звука и ещё немного после включения
    readonly property bool bell: shownMuted || unmuting.running
    Timer { id: unmuting; interval: 1100 }
    onShownMutedChanged: if (!shownMuted) unmuting.restart()

    function wheel(dy) {
        if (!sink?.audio) return;
        if (sink.audio.muted) sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1, Math.round((volume + (dy > 0 ? 0.05 : -0.05)) * 100) / 100));
    }

    implicitWidth: row.implicitWidth
    implicitHeight: 18

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        // без звука — перечёркнутый колокольчик; включили — черта уходит,
        // колокольчик звенит и через мгновение снова становится динамиком
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 18
            Sym {
                anchors.fill: parent
                size: 18
                name: !root.sink || root.volume <= 0.001 ? "volume-mute" : root.volume < 0.4 ? "volume-low" : "volume"
                color: root.sink ? Theme.fg2 : Theme.fg3
                opacity: root.bell ? 0 : 1
                scale: root.bell ? 0.6 : 1
                Behavior on opacity { NumberAnimation { duration: 180 * Theme.anim.k } }
                Behavior on scale { NumberAnimation { duration: 260 * Theme.anim.k; easing.type: Easing.OutBack } }
            }
            MuteBell {
                anchors.fill: parent
                size: 18
                muted: root.shownMuted
                color: Theme.fg2
                cutColor: Theme.glass2
                opacity: root.bell ? 1 : 0
                scale: root.bell ? 1 : 0.6
                Behavior on opacity { NumberAnimation { duration: 180 * Theme.anim.k } }
                Behavior on scale { NumberAnimation { duration: 260 * Theme.anim.k; easing.type: Easing.OutBack } }
            }
        }
        Eq {
            anchors.verticalCenter: parent.verticalCenter
            visible: DockService.playing && !root.vertical && !DockService.mediaPill
            barHeight: 12
            playing: DockService.playing
        }
    }
}
