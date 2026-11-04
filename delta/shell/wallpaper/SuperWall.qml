pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import qs.common
import "media.js" as Media

// Сцена супер обоев. near: false — вид издалека (экран блокировки), true — вблизи
// (рабочий стол). Экран блокировки и стол рисуют одно и то же, поэтому при
// разблокировке блокировка тает над такой же картинкой, а та начинает лететь.
Item {
    id: root

    required property var spec
    property bool near: false
    // false — экран блокировки: видео не играет, только его первый кадр
    property bool live: false

    property real progress: near ? 1 : 0
    Behavior on progress {
        NumberAnimation {
            duration: (root.near ? 1700 : 650) * Theme.anim.k
            easing.type: root.near ? Easing.OutCubic : Easing.InOutCubic
        }
    }

    readonly property string kind: spec ? spec.kind : ""

    Loader {
        anchors.fill: parent
        sourceComponent: root.kind === "shader" ? (root.spec.frag === "moon" ? moonC : holeC)
            : root.kind === "flow" ? flowC : root.kind === "photos" ? photosC : root.kind === "video" ? videoC : root.kind === "live" ? liveC : null
    }

    Component {
        id: holeC
        ShaderEffect {
            property vector2d res: Qt.vector2d(width, height)
            property real zoom: root.progress
            property real time: SuperWalls.time
            fragmentShader: "super/blackhole.frag.qsb"
        }
    }
    Component {
        id: moonC
        ShaderEffect {
            property vector2d res: Qt.vector2d(width, height)
            property real zoom: root.progress
            property real time: SuperWalls.time
            property var moonMap: mapImage
            fragmentShader: "super/moon.frag.qsb"
            // своя копия у каждой поверхности: текстура живёт в её окне
            Image {
                id: mapImage
                source: "super/moon-map.jpg"
                visible: false
                mipmap: true
                cache: false
            }
        }
    }
    Component {
        id: flowC
        ShaderEffect {
            property vector2d res: Qt.vector2d(width, height)
            property real intro: SuperWalls.intro
            property real zoom: root.progress
            property real time: SuperWalls.time
            property color colorA: root.spec.a
            property color colorB: root.spec.b
            property color colorC: root.spec.c
            fragmentShader: "super/circles.frag.qsb"
        }
    }

    // два своих фото: дальнее уходит за спину, ближнее проступает и подъезжает
    Component {
        id: photosC
        Item {
            Image {
                anchors.fill: parent
                source: Media.fileUrl(root.spec.far)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                scale: 1 + root.progress * 0.5
                opacity: 1 - Math.min(1, Math.max(0, (root.progress - 0.25) / 0.5))
            }
            Image {
                anchors.fill: parent
                source: Media.fileUrl(root.spec.near)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                scale: 1 + root.progress * 0.08
                opacity: Math.min(1, Math.max(0, (root.progress - 0.2) / 0.5))
            }
        }
    }

    // анимированные: ролик крутится и на блокировке, и на столе; камера подъезжает ближе
    Component {
        id: liveC
        Item {
            id: lbox
            scale: 1 + root.progress * 0.22
            readonly property bool wanted: visible && !SuperWalls.covered
                && (root.live ? ShellState.desktopShown : !ShellState.desktopShown)
            onWantedChanged: sync()
            Component.onCompleted: sync()
            function sync() {
                if (wanted) livePlayer.play();
                else livePlayer.pause();
            }
            Image {
                anchors.fill: parent
                source: Media.fileUrl(root.spec.far)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            MediaPlayer {
                id: livePlayer
                source: Media.fileUrl(root.spec.clip)
                videoOutput: liveOut
                loops: MediaPlayer.Infinite
            }
            VideoOutput {
                id: liveOut
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
            }
        }
    }

    // своё видео: на блокировке первый кадр, при входе играет раз и замирает на последнем
    Component {
        id: videoC
        Item {
            id: vbox
            Image {
                anchors.fill: parent
                source: Media.fileUrl(root.near && root.live ? root.spec.near : root.spec.far)
                fillMode: Image.PreserveAspectCrop
                cache: true
            }
            MediaPlayer {
                id: player
                source: root.live ? Media.fileUrl(root.spec.clip) : ""
                videoOutput: out
                onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) out.visible = false
            }
            VideoOutput {
                id: out
                anchors.fill: parent
                visible: false
                fillMode: VideoOutput.PreserveAspectCrop
            }
            Timer { id: reveal; interval: 80; onTriggered: out.visible = true }
            function sync() {
                if (!root.live) return;
                if (root.near) { player.position = 0; player.play(); reveal.restart(); }
                else { reveal.stop(); player.stop(); out.visible = false; }
            }
            Connections {
                target: root
                function onNearChanged() { vbox.sync(); }
            }
        }
    }
}
