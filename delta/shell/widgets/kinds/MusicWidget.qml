pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Mpris
import qs.common
import qs.common.ui
import qs.widgets.parts

// Музыка (MPRIS): обложка, название, исполнитель; в «Длинном» режиме —
// прогресс и кнопки. Кнопки работают вне редактора.
Base {
    id: root

    // играющий плеер важнее остальных
    readonly property var players: Mpris.players.values
    readonly property MprisPlayer player: players.find(p => p.isPlaying) || players[0] || null
    readonly property bool playing: player !== null && player.isPlaying
    readonly property string title: player ? (player.trackTitle || player.identity || "Без названия") : "Ничего не играет"
    readonly property string artist: player ? (player.trackArtist || player.identity || "") : "Включите музыку"
    readonly property string art: player ? (player.trackArtUrl || "") : ""

    // позиция у MPRIS не обновляется сама — просим раз в секунду, пока видно прогресс
    Timer {
        running: root.playing && root.visible && longView.visible && root.player.positionSupported
        interval: 1000
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    // круглая кнопка управления (.pbtn)
    component Ctl: Rectangle {
        id: ctl
        property string icon
        property bool main: false
        signal clicked()
        width: height
        radius: height / 2
        color: main ? root.pal.c1 : root.pal.track
        scale: tap.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: Theme.anim.fast } }
        Sym {
            anchors.centerIn: parent
            name: ctl.icon
            size: Math.round(parent.height * 0.46)
            color: ctl.main ? Theme.inv : root.pal.c1
        }
        TapHandler { id: tap; enabled: !root.editing && root.player !== null; onTapped: ctl.clicked() }
    }

    // ---- «Короткий» ----
    Item {
        anchors.fill: parent
        visible: !root.lock && root.mode !== "long"

        Cover { width: 36 * root.cm; height: width; radius: 9 * root.cm; source: root.art }
        Eq {
            anchors { right: parent.right; top: parent.top }
            height: 11 * root.cm; width: height * 1.1
            playing: root.playing
            visible: root.player !== null
        }
        Column {
            anchors.bottom: parent.bottom
            width: parent.width
            WText { width: parent.width; text: root.title; px: 9.5 * root.cm; font.weight: Font.ExtraBold; color: root.pal.c1 }
            WText { width: parent.width; text: root.artist; px: 7.5 * root.cm; color: root.pal.c3 }
        }
    }

    // ---- «Длинный» ----
    Item {
        id: longView
        anchors.fill: parent
        visible: !root.lock && root.mode === "long"

        Cover {
            id: bigCover
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(86 * root.ch, 40 * root.cw); height: width
            radius: 13 * root.ch
            source: root.art
        }
        Item {
            anchors { left: bigCover.right; leftMargin: 4 * root.cw; right: parent.right; top: parent.top; bottom: parent.bottom }

            Column {
                id: titles
                width: parent.width
                WText { width: parent.width; text: root.title; px: Math.min(11 * root.ch, 5 * root.cw); font.weight: Font.ExtraBold; color: root.pal.c1 }
                WText { width: parent.width; text: root.artist; px: Math.min(8.5 * root.ch, 4 * root.cw); color: root.pal.c3 }
            }
            Eq {
                anchors { left: parent.left; top: titles.bottom; topMargin: 3 * root.ch }
                height: 14 * root.ch; width: height * 1.1
                playing: root.playing
                visible: root.player !== null
            }
            Rectangle {
                id: progress
                anchors { left: parent.left; right: parent.right; bottom: ctls.top; bottomMargin: 5 * root.ch }
                height: Math.max(2, 2.6 * root.ch)
                radius: height / 2
                color: root.pal.track
                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    color: root.pal.c1
                    width: root.player && root.player.lengthSupported && root.player.length > 0
                        ? parent.width * Math.min(1, root.player.position / root.player.length) : 0
                }
            }
            Row {
                id: ctls
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                spacing: 3 * root.cw
                Ctl { height: 21 * root.ch; icon: "prev"; onClicked: root.player.previous() }
                Ctl { height: 21 * root.ch; icon: root.playing ? "pause" : "play"; main: true; onClicked: root.player.togglePlaying() }
                Ctl { height: 21 * root.ch; icon: "next"; onClicked: root.player.next() }
            }
        }
    }

    // ---- экран блокировки ----
    Item {
        anchors.fill: parent
        visible: root.lock

        // «Короткий»: обложка, название, исполнитель, эквалайзер
        Row {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            visible: root.mode !== "wide"
            spacing: 6 * root.cm
            Cover {
                id: lockCover
                anchors.verticalCenter: parent.verticalCenter
                width: 66 * root.ch; height: width; radius: 16 * root.ch
                source: root.art
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - lockCover.width - lockEq.width - parent.spacing * 2
                WText { width: parent.width; text: root.title; px: Math.min(18 * root.ch, 6 * root.cw); font.weight: Font.ExtraBold; color: root.pal.c1 }
                WText { width: parent.width; text: root.artist; px: Math.min(15 * root.ch, 5 * root.cw); color: root.pal.c1; opacity: 0.8 }
            }
            Eq {
                id: lockEq
                anchors.verticalCenter: parent.verticalCenter
                height: 20 * root.ch; width: height * 1.1
                playing: root.playing
                opacity: root.player !== null ? 1 : 0
            }
        }

        // «Широкий»: крупная обложка, прогресс и кнопки управления
        Item {
            anchors.fill: parent
            visible: root.mode === "wide"

            Cover {
                id: wideCover
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(70 * root.ch, 34 * root.cw); height: width
                radius: 14 * root.ch
                source: root.art
            }
            Item {
                anchors { left: wideCover.right; leftMargin: 5 * root.cw; right: parent.right; top: parent.top; bottom: parent.bottom }

                Column {
                    id: wideTitles
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    WText { width: parent.width; text: root.title; px: Math.min(16 * root.ch, 6.5 * root.cw); font.weight: Font.ExtraBold; color: root.pal.c1 }
                    WText { width: parent.width; text: root.artist; px: Math.min(13 * root.ch, 5.2 * root.cw); color: root.pal.c1; opacity: 0.8 }
                }
                Rectangle {
                    id: wideProgress
                    anchors { left: parent.left; right: parent.right; bottom: wideCtls.top; bottomMargin: 4 * root.ch }
                    height: Math.max(2, 2.6 * root.ch)
                    radius: height / 2
                    color: root.pal.track
                    Rectangle {
                        height: parent.height
                        radius: parent.radius
                        color: root.pal.c1
                        width: root.player && root.player.lengthSupported && root.player.length > 0
                            ? parent.width * Math.min(1, root.player.position / root.player.length) : 0
                    }
                }
                Row {
                    id: wideCtls
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                    spacing: 3 * root.cw
                    Ctl { height: Math.min(20 * root.ch, 9 * root.cw); icon: "prev"; onClicked: root.player.previous() }
                    Ctl { height: Math.min(20 * root.ch, 9 * root.cw); icon: root.playing ? "pause" : "play"; main: true; onClicked: root.player.togglePlaying() }
                    Ctl { height: Math.min(20 * root.ch, 9 * root.cw); icon: "next"; onClicked: root.player.next() }
                }
            }
        }
    }
}
