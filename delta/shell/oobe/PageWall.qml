pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.common
import qs.common.ui
import qs.walls
import "../wallpaper/media.js" as Media

// Шаг 3: обои. Пока этот шаг открыт, затемнение фона слабее — видно, как
// обои меняются за карточкой.
Page {
    id: root

    icon: "image"
    title: I18n.tr("Обои")
    subtitle: I18n.tr("Картинка или живое видео — сменить можно в любой момент правым щелчком по рабочему столу.")

    onShownChanged: if (shown && WallStore.items.length === 0) WallStore.scan()
    Component.onCompleted: WallStore.scan()

    readonly property string current: Settings.get("wallpaper.path", "")

    GridView {
        id: grid
        anchors.fill: parent
        clip: true
        cellWidth: Math.floor(width / 4)
        cellHeight: Math.round(cellWidth * 0.62)
        model: WallStore.items
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property bool on: root.current === modelData.path
            width: grid.cellWidth
            height: grid.cellHeight

            opacity: 0
            scale: 0.8
            Component.onCompleted: pop.start()
            SequentialAnimation {
                id: pop
                PauseAnimation { duration: Math.min(12, cell.index) * 35 }
                ParallelAnimation {
                    NumberAnimation { target: cell; property: "opacity"; to: 1; duration: 300 }
                    NumberAnimation { target: cell; property: "scale"; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                }
            }

            ClippingRectangle {
                anchors { fill: parent; margins: 6 }
                radius: 16
                color: Theme.soft2
                border.width: cell.on ? 3 : 0
                border.color: Theme.accent
                scale: wTap.pressed ? 0.94 : wTap.containsMouse ? 1.04 : 1
                Behavior on scale { NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }
                Image {
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 384
                    source: WallStore.thumbs[cell.modelData.key] === true ? Media.fileUrl(cell.modelData.thumb) : ""
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.anim.normal } }
                }
                Rectangle {
                    visible: cell.modelData.video
                    anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
                    width: 26; height: 26; radius: 13
                    color: Qt.rgba(0, 0, 0, 0.55)
                    Sym { anchors.centerIn: parent; name: "play"; size: 13; color: "white" }
                }
                Rectangle {
                    anchors { top: parent.top; right: parent.right; margins: 8 }
                    width: 24; height: 24; radius: 12
                    color: Theme.accent
                    scale: cell.on ? 1 : 0
                    Behavior on scale { NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }
                    Sym { anchors.centerIn: parent; name: "check"; size: 14; color: Theme.onAccent }
                }
            }
            MouseArea {
                id: wTap
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { WallStore.apply(cell.modelData); Sounds.play("oobe-select", 60); }
            }
        }

        Label {
            anchors.centerIn: parent
            visible: grid.count === 0
            text: WallStore.scanning ? I18n.tr("Ищем обои…") : I18n.tr("Обоев пока нет — их можно добавить позже")
            tone: 3
        }
    }
}
