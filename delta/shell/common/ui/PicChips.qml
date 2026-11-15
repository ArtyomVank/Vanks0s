pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.common

// Выбор варианта картинками, как плитки тем: у каждого варианта маленькая
// сцена (текущие обои, док) и окно, которое показывает этот вариант
// в движении — по кругу, с паузой.
//   kind "open"  — анимация открытия окна (windows.openAnim);
//   kind "close" — закрытия: то же движение наоборот;
//   kind "panel" — меню, виджеты и «Настройки»: панель выходит из дока.
//     PicChips { kind: "open"; model: [{ value: "popin", label: "Масштаб" }, …]
//                current: …; onPicked: v => … }
// value "same" (закрытие «как открытие») рисуется как sameAs; "auto" у
// панелей — как у текущего стиля.
Flow {
    id: root

    property string kind: "open"
    property var model: []
    property var current
    property string sameAs: "popin"
    signal picked(var value)

    spacing: 10

    Repeater {
        model: root.model
        delegate: Rectangle {
            id: card
            required property var modelData
            readonly property bool sel: modelData.value === root.current
            readonly property string how: {
                const v = modelData.value;
                if (v === "same") return root.sameAs;
                if (v === "auto") return Theme.material ? "spring" : "drop";
                return v;
            }

            implicitWidth: 138
            implicitHeight: 120
            radius: 14
            color: hov.hovered ? Theme.soft2 : Theme.soft
            border.width: 2
            border.color: sel ? Theme.accent : Theme.line
            Behavior on border.color { ColorAnimation { duration: Theme.anim.fast } }
            scale: tap.pressed ? 0.97 : 1
            Behavior on scale { NumberAnimation { duration: 140 * Theme.anim.k; easing.type: Easing.OutBack } }

            // ход: 0 — окна нет, 1 — окно на месте (у закрытия — наоборот)
            property real t: 0
            readonly property real e: root.kind === "close" ? 1 - t : t
            SequentialAnimation on t {
                loops: Animation.Infinite
                running: card.visible
                NumberAnimation {
                    from: 0; to: 1
                    duration: (card.how === "assemble" || card.how === "inside" ? 900 : 700) * Theme.anim.k
                    easing.type: card.how === "spring" ? Easing.OutBack : card.how === "fade" ? Easing.InOutQuad : Easing.OutCubic
                    easing.overshoot: 2.2
                }
                PauseAnimation { duration: 1000 }
                NumberAnimation { to: 0; duration: 0 }
                PauseAnimation { duration: 350 }
            }

            ClippingRectangle {
                id: scene
                x: 8; y: 8
                width: parent.width - 16
                height: 80
                radius: 10
                color: "transparent"

                // сцена — текущие обои; пока их нет — градиент в цвет оформления
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.3) }
                        GradientStop { position: 1; color: Qt.darker(Theme.accent, 2.1) }
                    }
                }
                Image {
                    anchors.fill: parent
                    visible: Theme.wallFile !== "" && status === Image.Ready
                    source: Theme.wallFile !== "" ? "file://" + Theme.wallFile : ""
                    sourceSize: Qt.size(240, 140)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }

                Rectangle {
                    id: dock
                    width: 56; height: 9; radius: 4.5
                    x: (scene.width - width) / 2
                    y: scene.height - height - 5
                    color: Qt.rgba(1, 1, 1, 0.38)
                }

                // окно (кроме «сборки»): одно тело, меняются размер, место, масштаб
                Item {
                    id: win
                    visible: card.how !== "assemble"
                    readonly property real fullW: 74
                    readonly property real fullH: 48
                    readonly property real e: Math.max(0, card.e)
                    readonly property bool grows: card.how === "inside" || card.how === "drop"
                    // «изнутри» — капля в середине, «капля» — из дока
                    width: grows ? 10 + (fullW - 10) * Math.min(1, e * (card.how === "drop" ? 1.25 : 1)) : fullW
                    height: grows ? 10 + (fullH - 10) * Math.min(1, Math.max(0, card.how === "drop" ? e * 1.25 - 0.2 : e)) : fullH
                    x: (scene.width - width) / 2
                    y: card.how === "drop" ? dock.y - 4 - height
                       : card.how === "inside" ? 10 + (fullH - height) / 2
                       : 10 + (card.how === "slide" ? (1 - e) * 34 : 0)
                    opacity: card.how === "fade" ? e : card.how === "slide" ? Math.min(1, e * 1.4)
                             : grows ? Math.min(1, e * 4) : Math.min(1, e * 1.8)
                    scale: card.how === "popin" ? 0.55 + 0.45 * e : card.how === "spring" ? Math.max(0, card.e) : 1
                    transformOrigin: card.how === "spring" ? Item.Bottom : Item.Center

                    Rectangle {
                        anchors.fill: parent
                        radius: win.grows ? Math.min(6, Math.min(parent.width, parent.height) / 2) : 6
                        color: Theme.glass2
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.25)
                        Column {
                            visible: win.height > 30
                            x: 7; y: 7
                            spacing: 5
                            Rectangle { width: win.width * 0.45; height: 4; radius: 2; color: Theme.fg2; opacity: 0.8 }
                            Rectangle { width: win.width * 0.7; height: 3; radius: 1.5; color: Theme.fg3; opacity: 0.6 }
                            Rectangle { width: win.width * 0.55; height: 3; radius: 1.5; color: Theme.fg3; opacity: 0.6 }
                        }
                    }
                }

                // «сборка»: окно слетается из четырёх осколков
                Repeater {
                    model: card.how === "assemble" ? 4 : 0
                    delegate: Rectangle {
                        required property int index
                        readonly property int cx: index % 2
                        readonly property int cy: Math.floor(index / 2)
                        readonly property real e: Math.max(0, card.e)
                        width: 37; height: 24
                        radius: 4
                        color: Theme.glass2
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.25)
                        x: (scene.width - 74) / 2 + cx * 37 + (1 - e) * (cx ? 22 : -22)
                        y: 10 + cy * 24 + (1 - e) * (cy ? 16 : -16)
                        rotation: (1 - e) * (index % 3 === 0 ? 24 : -18)
                        opacity: Math.min(1, e * 1.6)
                    }
                }
            }

            Label {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 8 }
                width: parent.width - 12
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: card.modelData.label
                size: "small"
                font.weight: card.sel ? Font.DemiBold : Font.Normal
                color: card.sel ? Theme.accent : Theme.fg
            }

            HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
            TapHandler { id: tap; onTapped: root.picked(card.modelData.value) }
        }
    }
}
