pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.common.ui

// «Оставить эти параметры?» — поверх всего на каждом экране. Без ответа через
// Displays.timeout секунд параметры возвращаются (Displays.revert()).
// Enter — оставить, Esc — вернуть.
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData

            WlrLayershell.namespace: "delta-display-confirm"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"

            // затемнение: ясно, что ждём ответа
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.38)
                opacity: card.shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.anim.normal } }
            }

            Glass {
                id: card
                property bool shown: false
                Component.onCompleted: shown = true

                strong: true
                // почти непрозрачная: под окном — что угодно, вплоть до сломанной картинки
                color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.96)
                anchors.centerIn: parent
                width: 440
                height: box.implicitHeight + 44
                scale: shown ? 1 : 0.92
                opacity: shown ? 1 : 0
                Behavior on scale { NumberAnimation { duration: Theme.anim.normal; easing.type: Theme.anim.springCurve } }
                Behavior on opacity { NumberAnimation { duration: Theme.anim.fast } }

                focus: true
                Keys.onReturnPressed: Displays.keep()
                Keys.onEnterPressed: Displays.keep()
                Keys.onEscapePressed: Displays.revert()

                ColumnLayout {
                    id: box
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 }
                    spacing: 12

                    RowLayout {
                        spacing: 12
                        Rectangle {
                            implicitWidth: 40; implicitHeight: 40; radius: 20
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                            Sym { anchors.centerIn: parent; name: "monitor"; size: 22; color: Theme.accent }
                        }
                        ColumnLayout {
                            spacing: 2
                            Layout.fillWidth: true
                            Label { text: "Оставить эти параметры?"; size: "title"; Layout.fillWidth: true }
                            Label {
                                text: "Прежние вернутся через " + Displays.countdown + " с"
                                tone: 2
                                Layout.fillWidth: true
                            }
                        }
                    }

                    Label {
                        text: "Если изображение пропало или выглядит неправильно, просто подождите — ничего нажимать не нужно."
                        size: "small"
                        tone: 3
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    // полоска оставшегося времени
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 4
                        radius: 2
                        color: Theme.soft2
                        Rectangle {
                            height: parent.height
                            radius: 2
                            color: Theme.accent
                            width: parent.width * Math.max(0, Displays.countdown) / Displays.timeout
                            Behavior on width { NumberAnimation { duration: 1000 * Theme.anim.k; easing.type: Easing.Linear } }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 8
                        Item { Layout.fillWidth: true }
                        Btn { text: "Вернуть"; onClicked: Displays.revert() }
                        Btn { text: "Оставить"; kind: "accent"; onClicked: Displays.keep() }
                    }
                }
            }
        }
    }
}
