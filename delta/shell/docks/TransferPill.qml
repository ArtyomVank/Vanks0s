import QtQuick
import qs.common
import qs.common.ui
import qs.services

// Верхний док во время загрузки. Свёрнут: значок и проценты. Раскрыт (нажатие):
// название, полоса, сколько скачано из скольких и скорость.
Item {
    id: root

    property bool vertical: false
    readonly property bool open: Transfers.expanded && !vertical
    readonly property bool known: Transfers.percent >= 0
    readonly property string percentText: known ? Transfers.percent + " %" : Transfers.bytes(Transfers.done)

    width: vertical ? 44 : open ? 400 : short.implicitWidth + 32
    height: vertical ? short.implicitHeight + 28 : open ? 88 : 44

    // свёрнут
    Grid {
        id: short
        anchors.centerIn: parent
        visible: !root.open
        columns: root.vertical ? 1 : 2
        columnSpacing: 8
        rowSpacing: 4
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter
        Sym { name: "download"; size: 18; color: Theme.accent }
        Label {
            text: root.vertical && root.known ? String(Transfers.percent) : root.percentText
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
            size: root.vertical ? "small" : "body"
        }
    }

    // раскрыт
    Column {
        visible: root.open
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 22; rightMargin: 22 }
        spacing: 7

        Row {
            width: parent.width
            spacing: 8
            Sym { anchors.verticalCenter: parent.verticalCenter; name: "download"; size: 16; color: Theme.accent }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 16 - percentLabel.implicitWidth - 16
                text: Transfers.name || Transfers.source
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
            }
            Label {
                id: percentLabel
                anchors.verticalCenter: parent.verticalCenter
                visible: root.known
                text: Transfers.percent + " %"
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
        }

        Rectangle {
            id: track
            width: parent.width
            height: 6
            radius: 3
            color: Theme.soft
            clip: true
            Rectangle {
                height: parent.height
                radius: 3
                color: Theme.accent
                width: root.known ? parent.width * Transfers.percent / 100 : parent.width * 0.3
                Behavior on width { enabled: root.known; NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                // размер неизвестен: полоса ходит туда-сюда
                SequentialAnimation on x {
                    running: !root.known && root.open
                    loops: Animation.Infinite
                    NumberAnimation { from: 0; to: track.width * 0.7; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { from: track.width * 0.7; to: 0; duration: 900; easing.type: Easing.InOutSine }
                }
                x: 0
            }
        }

        Item {
            width: parent.width
            height: sizes.implicitHeight
            Label {
                id: sizes
                text: root.known ? Transfers.bytes(Transfers.done) + " " + I18n.tr("из") + " " + Transfers.bytes(Transfers.total)
                                 : Transfers.bytes(Transfers.done) + " · " + I18n.tr("размер неизвестен")
                size: "small"
                tone: 2
                font.features: { "tnum": 1 }
            }
            Label {
                anchors.right: parent.right
                text: Transfers.speed > 0 ? Transfers.bytes(Transfers.speed) + I18n.tr("/с") : ""
                size: "small"
                tone: 2
                font.features: { "tnum": 1 }
            }
        }
    }
}
