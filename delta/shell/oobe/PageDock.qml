pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui

// Шаг 4: вид верхнего дока — полный, плитки или компактный — и поведение нижнего.
Page {
    id: root

    icon: "dock"
    title: I18n.tr("Доки")
    subtitle: I18n.tr("Сверху — часы, меню и состояние, снизу — приложения. Выберите, как будет выглядеть верхний.")

    readonly property string length: Settings.get("docks.top.length", "full")

    ColumnLayout {
        anchors.fill: parent
        spacing: 18

        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            Repeater {
                model: [{ id: "full", name: "Полный" }, { id: "tiles", name: "Плитки" }, { id: "compact", name: "Компактный" }]
                delegate: Choice {
                    id: style
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 168
                    selected: root.length === style.modelData.id
                    onPicked: Settings.set("docks.top.length", style.modelData.id)

                    // экран с доком выбранного вида
                    Rectangle {
                        id: screenBox
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                        height: 100
                        radius: 12
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55) }
                            GradientStop { position: 1; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12) }
                        }
                        readonly property color bar: Theme.glass2
                        // полный: одна полоса во всю ширину
                        Rectangle {
                            visible: style.modelData.id === "full"
                            x: 6; y: 6; width: parent.width - 12; height: 14; radius: 7; color: screenBox.bar
                        }
                        // плитки: отдельные капсулы
                        Row {
                            visible: style.modelData.id === "tiles"
                            x: 6; y: 6; spacing: 4
                            Repeater {
                                model: [0.12, 0.26, 0.14, 0.1, 0.18]
                                delegate: Rectangle {
                                    id: tileBar
                                    required property real modelData
                                    required property int index
                                    width: (screenBox.width - 28) * modelData; height: 14; radius: 7; color: screenBox.bar
                                    // плитки покачиваются, пока плитка выбрана
                                    SequentialAnimation on y {
                                        running: style.selected
                                        loops: Animation.Infinite
                                        PauseAnimation { duration: 80 * tileBar.index }
                                        NumberAnimation { to: -2; duration: 420; easing.type: Easing.InOutSine }
                                        NumberAnimation { to: 0; duration: 420; easing.type: Easing.InOutSine }
                                        PauseAnimation { duration: 900 }
                                    }
                                }
                            }
                        }
                        // компактный: капсула посередине
                        Rectangle {
                            visible: style.modelData.id === "compact"
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 6; width: parent.width * 0.5; height: 14; radius: 7; color: screenBox.bar
                        }
                        Rectangle {
                            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 6 }
                            width: parent.width * 0.38; height: 14; radius: 7; color: screenBox.bar
                        }
                    }
                    Label {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
                        text: I18n.tr(style.modelData.name)
                        size: "title"
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: rows.implicitHeight + 8
            radius: 18
            color: Theme.soft
            border.width: 1
            border.color: Theme.line
            ColumnLayout {
                id: rows
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 0
                SettingRow {
                    icon: "apps"
                    title: I18n.tr("Прятать нижний док")
                    subtitle: I18n.tr("Появляется, когда курсор у нижнего края экрана")
                    Toggle { checked: Settings.get("docks.apps.autohide", true) === true; onToggled: v => { Settings.set("docks.apps.autohide", v); Sounds.play("pop", 60); } }
                }
                SettingRow {
                    icon: "maximize"
                    title: I18n.tr("Увеличение значков")
                    subtitle: I18n.tr("Значки под курсором вырастают, как волна")
                    Toggle { checked: Settings.get("docks.apps.magnify", true) !== false; onToggled: v => { Settings.set("docks.apps.magnify", v); Sounds.play("pop", 60); } }
                }
            }
        }
        Item { Layout.fillHeight: true }
    }
}
