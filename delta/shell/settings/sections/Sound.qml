pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import qs.common
import qs.common.ui

// Раздел «Звук»: выходы и входы, громкость, громкость приложений.
ColumnLayout {
    id: root

    property string title: I18n.tr("Звук")
    property string icon: "volume"
    property string keywords: "громкость динамики наушники микрофон выход вход приложения"
    spacing: 18

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property var nodes: Pipewire.nodes.values
    readonly property var sinks: nodes.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: nodes.filter(n => n.audio && !n.isSink && !n.isStream)
    readonly property var playback: nodes.filter(n => n.audio && n.isSink && n.isStream)
    readonly property var recording: nodes.filter(n => n.audio && !n.isSink && n.isStream)

    PwObjectTracker { objects: [root.sink, root.source].concat(root.playback, root.recording) }

    function devName(n) { return n?.nickname || n?.description || n?.name || "—"; }
    function appName(n) {
        const p = n.properties || {};
        return p["application.name"] || n.description || n.name;
    }

    component DeviceChoice: Chips {
        property var list: []
        property PwNode cur
        current: cur?.id ?? -1
        model: list.map(n => ({ value: n.id, label: root.devName(n) }))
    }

    component Volume: RowLayout {
        id: v
        property PwNode node
        property string onIcon: "volume"
        property string offIcon: "volume-mute"
        spacing: 10
        Btn {
            icon: v.node?.audio?.muted ? v.offIcon : v.onIcon
            iconSize: 17
            enabled: v.node?.audio !== undefined && v.node?.audio !== null
            active: v.node?.audio?.muted ?? false
            onClicked: v.node.audio.muted = !v.node.audio.muted
        }
        Slider {
            Layout.fillWidth: true
            from: 0; to: 1.5; step: 0.01
            value: v.node?.audio?.volume ?? 0
            enabled: v.node?.audio !== undefined && v.node?.audio !== null
            onMoved: x => v.node.audio.volume = x
        }
        Label {
            text: Math.round((v.node?.audio?.volume ?? 0) * 100) + "%"
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 44
        }
    }

    Card {
        title: I18n.tr("Выход")
        SettingRow {
            icon: "speaker"
            title: root.devName(root.sink)
            subtitle: root.sink ? "Устройство вывода по умолчанию" : "Нет устройств вывода"
            wide: true
            Volume { node: root.sink }
        }
        SettingRow {
            visible: root.sinks.length > 1
            title: I18n.tr("Устройство")
            wide: true
            DeviceChoice {
                list: root.sinks
                cur: root.sink
                onPicked: id => Pipewire.preferredDefaultAudioSink = root.sinks.find(n => n.id === id)
            }
        }
    }

    Card {
        title: I18n.tr("Вход")
        SettingRow {
            icon: "mic"
            title: root.source ? root.devName(root.source) : "Микрофон не выбран"
            subtitle: root.sources.length ? "Устройство записи по умолчанию" : "Нет устройств записи"
            wide: true
            Volume { node: root.source; onIcon: "mic"; offIcon: "mic-off" }
        }
        SettingRow {
            visible: root.sources.length > 1 || (root.source === null && root.sources.length > 0)
            title: I18n.tr("Устройство")
            wide: true
            DeviceChoice {
                list: root.sources
                cur: root.source
                onPicked: id => Pipewire.preferredDefaultAudioSource = root.sources.find(n => n.id === id)
            }
        }
    }

    Card {
        title: I18n.tr("Звуки системы")
        SettingRow {
            icon: "bell"; title: I18n.tr("Звуки оболочки"); subtitle: I18n.tr("Тихие звуки на уведомления, громкость и блокировку")
            Toggle { checked: Settings.get("sounds.enabled", true) !== false; onToggled: v => Settings.set("sounds.enabled", v) }
        }
        SettingRow {
            visible: Settings.get("sounds.enabled", true) !== false
            icon: "volume"; title: I18n.tr("Громкость звуков"); wide: true
            RowLayout {
                spacing: 10
                Slider {
                    Layout.fillWidth: true
                    from: 0; to: 1; step: 0.05
                    value: Number(Settings.get("sounds.volume", 0.6))
                    onMoved: x => Settings.set("sounds.volume", x)
                }
                Btn { icon: "play"; iconSize: 15; onClicked: Sounds.play("message-new-instant", 0) }
            }
        }
    }

    Card {
        title: I18n.tr("Приложения")
        SettingRow {
            visible: root.playback.length === 0 && root.recording.length === 0
            icon: "music"
            title: I18n.tr("Сейчас звук не воспроизводит ни одно приложение")
        }
        Repeater {
            model: root.playback.concat(root.recording)
            delegate: SettingRow {
                id: app
                required property PwNode modelData
                icon: modelData.properties["application.icon-name"] || (modelData.isSink ? "music" : "mic")
                title: root.appName(modelData)
                subtitle: (modelData.isSink ? "Воспроизведение" : "Запись") + (modelData.properties["media.name"] ? " · " + modelData.properties["media.name"] : "")
                wide: true
                Volume { node: app.modelData; onIcon: app.modelData.isSink ? "volume" : "mic"; offIcon: app.modelData.isSink ? "volume-mute" : "mic-off" }
            }
        }
    }
}
