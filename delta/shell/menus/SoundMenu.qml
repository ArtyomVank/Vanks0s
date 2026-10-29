pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import qs.common
import qs.common.ui
import qs.launcher.parts

// Меню звука: плеер с визуализатором, громкость и выход, микрофон,
// громкость отдельных приложений.
Item {
    id: root

    implicitWidth: 360
    implicitHeight: col.implicitHeight
    signal close()

    // подставной уровень визуализатора для проверки (dev-launcher), -1 — настоящий
    property real vizDemo: -1

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property var nodes: Pipewire.nodes.values
    readonly property var sinks: nodes.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: nodes.filter(n => n.audio && !n.isSink && !n.isStream)
    readonly property var streams: nodes.filter(n => n.audio && n.isSink && n.isStream)

    // громкость и свойства доступны только у привязанных узлов
    PwObjectTracker { objects: [root.sink, root.source].concat(root.streams) }

    function devName(n) { return n?.nickname || n?.description || n?.name || "—"; }
    function shortName(n) {
        // длинные названия устройств не помещаются в чип
        const d = devName(n);
        return d.length > 26 ? d.slice(0, 25) + "…" : d;
    }
    function volIcon(a) {
        if (!a || a.muted || a.volume <= 0.001) return "volume-mute";
        return a.volume < 0.4 ? "volume-low" : "volume";
    }
    function streamName(n) {
        const p = n.properties || {};
        return p["application.name"] || p["media.name"] || n.description || n.name;
    }

    // строка «кнопка без звука · ползунок · проценты»
    component VolumeRow: RowLayout {
        id: vr
        property PwNode node
        property string offIcon: "volume-mute"
        property string onIcon: root.volIcon(node?.audio)
        spacing: 8
        Layout.fillWidth: true
        Btn {
            icon: vr.node?.audio?.muted ? vr.offIcon : vr.onIcon
            iconSize: 17
            implicitHeight: 32
            kind: "ghost"
            border.width: 0
            active: false
            enabled: vr.node?.audio !== undefined && vr.node?.audio !== null
            onClicked: vr.node.audio.muted = !vr.node.audio.muted
        }
        Slider {
            Layout.fillWidth: true
            from: 0; to: 1
            value: vr.node?.audio?.volume ?? 0
            enabled: vr.node?.audio !== undefined && vr.node?.audio !== null
            opacity: vr.node?.audio?.muted ? 0.5 : 1
            onMoved: v => vr.node.audio.volume = v
        }
        Label {
            text: Math.round((vr.node?.audio?.volume ?? 0) * 100)
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 32
        }
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 10

        MenuTitle { text: "Звук и музыка" }

        Player {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            vizDemo: root.vizDemo
        }

        Label { text: "Выход"; size: "caption"; tone: 3; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6 }
        VolumeRow { node: root.sink }
        Chips {
            Layout.fillWidth: true
            visible: root.sinks.length > 1
            current: root.sink?.id ?? -1
            model: root.sinks.map(n => ({ value: n.id, label: root.shortName(n) }))
            onPicked: v => Pipewire.preferredDefaultAudioSink = root.sinks.find(n => n.id === v)
        }

        Label {
            visible: root.source !== null || root.sources.length > 0
            text: "Микрофон"; size: "caption"; tone: 3; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6
            Layout.topMargin: 4
        }
        VolumeRow { visible: root.source !== null || root.sources.length > 0; node: root.source; offIcon: "mic-off"; onIcon: "mic" }
        Chips {
            Layout.fillWidth: true
            visible: root.sources.length > 1 || (root.source === null && root.sources.length > 0)
            current: root.source?.id ?? -1
            model: root.sources.map(n => ({ value: n.id, label: root.shortName(n) }))
            onPicked: v => Pipewire.preferredDefaultAudioSource = root.sources.find(n => n.id === v)
        }

        Label {
            visible: root.streams.length > 0
            text: "Приложения"; size: "caption"; tone: 3; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6
            Layout.topMargin: 4
        }
        Repeater {
            model: root.streams
            delegate: RowLayout {
                id: st
                required property PwNode modelData
                Layout.fillWidth: true
                spacing: 8
                IconImage {
                    implicitSize: 22
                    asynchronous: true
                    source: Quickshell.iconPath(st.modelData.properties["application.icon-name"] || "", "audio-x-generic")
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    Label { text: root.streamName(st.modelData); size: "caption"; tone: 2; Layout.fillWidth: true }
                    Slider {
                        Layout.fillWidth: true
                        implicitHeight: 22
                        from: 0; to: 1
                        value: st.modelData.audio?.volume ?? 0
                        onMoved: v => st.modelData.audio.volume = v
                    }
                }
            }
        }

        Btn {
            Layout.alignment: Qt.AlignLeft
            kind: "ghost"
            icon: "settings"
            text: "Настройки звука…"
            implicitHeight: 32
            onClicked: { ShellState.openSettings("sound", null); root.close(); }
        }
    }
}
