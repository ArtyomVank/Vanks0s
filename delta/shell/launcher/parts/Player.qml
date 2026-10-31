pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.common
import qs.common.ui

// Плеер MPRIS: обложка, название, исполнитель, прогресс, кнопки и
// визуализатор. Один компонент для меню звука (wide: false) и меню
// музыки из верхнего дока (wide: true).
Item {
    id: root

    property bool wide: false
    property bool showViz: true
    // подставной уровень для визуализатора (проверка без звука), -1 — настоящий
    property real vizDemo: -1

    readonly property var players: Mpris.players.values
    property int pick: -1
    readonly property MprisPlayer player: {
        const list = players;
        if (pick >= 0 && pick < list.length) return list[pick];
        return list.find(p => p.isPlaying) ?? list[0] ?? null;
    }
    readonly property bool hasPlayer: player !== null
    readonly property bool playing: player?.isPlaying ?? false

    implicitWidth: wide ? 440 : 328
    implicitHeight: hasPlayer ? (wide ? wideBox.implicitHeight : compactBox.implicitHeight) : empty.implicitHeight

    // --- поток плеера в PipeWire для визуализатора ---
    // ищем поток по имени приложения; не нашли — слушаем выход по умолчанию
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream && n.isSink && n.audio)
    PwObjectTracker { objects: root.streams.concat([Pipewire.defaultAudioSink]) }
    readonly property PwNode vizNode: {
        const p = player;
        if (!p) return null;
        const keys = [p.identity, p.desktopEntry, (p.dbusName || "").replace("org.mpris.MediaPlayer2.", "").split(".")[0]]
            .filter(k => k && k.length > 1).map(k => k.toLowerCase());
        for (const n of streams) {
            const props = n.properties || {};
            const names = [props["application.name"], props["application.process.binary"], props["application.id"], n.name]
                .filter(x => x).map(x => String(x).toLowerCase());
            if (names.some(a => keys.some(k => a.indexOf(k) !== -1 || k.indexOf(a) !== -1))) return n;
        }
        return Pipewire.defaultAudioSink;
    }

    // позиция в MPRIS сама не обновляется — опрашиваем раз в секунду
    Timer {
        interval: 1000
        repeat: true
        running: root.playing && root.visible
        onTriggered: root.player?.positionChanged()
    }

    function fmt(sec) {
        if (!isFinite(sec) || sec < 0) return "0:00";
        const s = Math.floor(sec);
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
    readonly property real progress: player && player.length > 0 ? Math.max(0, Math.min(1, player.position / player.length)) : 0

    // --- части ---
    component Art: ClippingRectangle {
        id: art
        property int size: 74
        width: size
        height: size
        radius: size * 0.24
        color: Theme.accent
        // своя «обложка» при отсутствии картинки — как .art в концепте
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Theme.accents[1] }
                GradientStop { position: 0.55; color: Theme.accent }
                GradientStop { position: 1; color: Qt.darker(Theme.accent, 2) }
            }
        }
        Sym {
            anchors.centerIn: parent
            visible: cover.status !== Image.Ready
            name: "music"
            size: art.size * 0.36
            color: Theme.onAccent
            opacity: 0.85
        }
        Image {
            id: cover
            anchors.fill: parent
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(art.size * 2, art.size * 2)
            source: root.player?.trackArtUrl ?? ""
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.anim.normal } }
        }
    }

    component Progress: Column {
        spacing: 4
        Rectangle {
            width: parent.width
            height: 5
            radius: 3
            color: Theme.soft2
            Rectangle {
                width: parent.width * root.progress
                height: parent.height
                radius: parent.radius
                color: Theme.fg
                Behavior on width { NumberAnimation { duration: 900 * Theme.anim.k; easing.type: Easing.Linear } }
            }
            MouseArea {
                anchors { fill: parent; topMargin: -6; bottomMargin: -6 }
                enabled: root.player?.canSeek ?? false
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: m => root.player.position = root.player.length * Math.max(0, Math.min(1, m.x / width))
            }
        }
        Item {
            width: parent.width
            height: 14
            visible: (root.player?.lengthSupported ?? false) && root.player.length > 0
            Label { text: root.fmt(root.player?.position ?? 0); size: "caption"; tone: 3 }
            Label { anchors.right: parent.right; text: root.fmt(root.player?.length ?? 0); size: "caption"; tone: 3 }
        }
    }

    component Controls: Row {
        id: ctl
        property int big: 44
        spacing: 12
        Btn {
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: ctl.big - 10
            icon: "prev"; iconSize: 16
            enabled: root.player?.canGoPrevious ?? false
            onClicked: root.player.previous()
        }
        Rectangle {
            width: ctl.big; height: ctl.big; radius: ctl.big / 2
            color: Theme.fg
            opacity: (root.player?.canTogglePlaying ?? false) ? 1 : 0.45
            scale: playTap.pressed ? 0.94 : 1
            Behavior on scale { NumberAnimation { duration: Theme.anim.fast } }
            Sym { anchors.centerIn: parent; name: root.playing ? "pause" : "play"; size: 20; color: Theme.inv }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { id: playTap; onTapped: if (root.player?.canTogglePlaying) root.player.togglePlaying() }
        }
        Btn {
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: ctl.big - 10
            icon: "next"; iconSize: 16
            enabled: root.player?.canGoNext ?? false
            onClicked: root.player.next()
        }
    }

    // несколько плееров — переключатель
    component Switcher: Chips {
        visible: root.players.length > 1
        current: root.players.indexOf(root.player)
        model: root.players.map((p, i) => ({ value: i, label: p.identity || ("Плеер " + (i + 1)) }))
        onPicked: v => root.pick = v
    }

    // --- компактный вид (меню звука) ---
    ColumnLayout {
        id: compactBox
        visible: root.hasPlayer && !root.wide
        width: parent.width
        spacing: 0

        RowLayout {
            spacing: 14
            Art { size: 74 }
            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true
                Label {
                    text: "Сейчас играет"
                    size: "caption"; tone: 3
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.6
                }
                Label { text: root.player?.trackTitle || root.player?.identity || ""; size: "title"; font.weight: Font.Bold; Layout.fillWidth: true }
                Label { text: root.player?.trackArtist ?? ""; size: "small"; tone: 2; visible: text.length > 0; Layout.fillWidth: true }
            }
        }
        Viz {
            visible: root.showViz
            Layout.fillWidth: true
            Layout.topMargin: 14
            Layout.bottomMargin: 10
            implicitHeight: 34
            node: root.vizNode
            playing: root.playing
            demo: root.vizDemo
        }
        Progress { Layout.fillWidth: true; Layout.topMargin: root.showViz ? 0 : 12 }
        Controls { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 6; big: 44 }
        Switcher { Layout.fillWidth: true; Layout.topMargin: 10 }
    }

    // --- широкий вид (меню музыки) ---
    ColumnLayout {
        id: wideBox
        visible: root.hasPlayer && root.wide
        width: parent.width
        spacing: 12

        RowLayout {
            spacing: 20
            Art { size: 128; Layout.alignment: Qt.AlignTop }
            ColumnLayout {
                spacing: 4
                Layout.fillWidth: true
                Label { text: "Сейчас играет · " + (root.player?.identity ?? ""); size: "caption"; tone: 3; font.weight: Font.DemiBold; Layout.fillWidth: true }
                Label { text: root.player?.trackTitle || root.player?.identity || ""; font.pixelSize: 19; font.weight: Font.Bold; Layout.fillWidth: true }
                Label {
                    text: [root.player?.trackArtist ?? "", root.player?.trackAlbum ?? ""].filter(s => s.length).join(" — ")
                    tone: 2; visible: text.length > 0; Layout.fillWidth: true
                }
                Progress { Layout.fillWidth: true; Layout.topMargin: 8 }
                Controls { Layout.alignment: Qt.AlignHCenter; big: 44 }
            }
        }
        Viz {
            visible: root.showViz
            Layout.fillWidth: true
            implicitHeight: 36
            bars: 40
            node: root.vizNode
            playing: root.playing
            demo: root.vizDemo
        }
        Switcher { Layout.fillWidth: true }
    }

    // --- ничего не играет ---
    Rectangle {
        id: empty
        visible: !root.hasPlayer
        width: parent.width
        implicitHeight: 56
        radius: 12
        color: Theme.soft
        RowLayout {
            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
            spacing: 10
            Sym { name: "music"; size: 20; color: Theme.fg3 }
            Label { text: "Ничего не играет"; tone: 3; Layout.fillWidth: true }
        }
    }
}
