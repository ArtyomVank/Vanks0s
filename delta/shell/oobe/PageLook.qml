pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui

// Шаг 2: тёмное или светлое оформление, цвет акцента и готовые сочетания.
// Всё применяется сразу — карточка настройки перекрашивается вместе с системой.
Page {
    id: root

    icon: "palette"
    title: I18n.tr("Оформление")
    subtitle: I18n.tr("Тёмное или светлое, и цвет, который будет встречаться повсюду.")

    readonly property string theme: Settings.get("appearance.theme", "graphite")
    readonly property var presets: ["aurora", "sunset", "neon", "cosmos", "amber", "mint", "sakura", "sky"]
    function setTheme(id) {
        Settings.set("appearance.theme", id);
        const t = Theme.themes.find(x => x.id === id);
        if (t && t.accent) Settings.set("appearance.accent", t.accent);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 18

        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            Repeater {
                model: [{ id: "graphite", name: "Тёмное", rgb: [24, 25, 30], light: false }, { id: "white", name: "Светлое", rgb: [247, 246, 251], light: true }]
                delegate: Choice {
                    id: mode
                    required property var modelData
                    readonly property color bg: Qt.rgba(modelData.rgb[0] / 255, modelData.rgb[1] / 255, modelData.rgb[2] / 255, 1)
                    Layout.fillWidth: true
                    implicitHeight: 150
                    selected: Theme.light === mode.modelData.light
                    onPicked: root.setTheme(mode.modelData.id)
                    // маленький рабочий стол: док сверху, окно, док снизу
                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 14 }
                        width: height * 1.5
                        radius: 14
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.2) }
                            GradientStop { position: 1; color: Qt.darker(Theme.accent, 1.8) }
                        }
                        Rectangle { x: 8; y: 7; width: parent.width - 16; height: 10; radius: 5; color: mode.bg; opacity: 0.92 }
                        Rectangle { x: parent.width * 0.18; y: 26; width: parent.width * 0.64; height: parent.height - 52; radius: 8; color: mode.bg; opacity: 0.95
                            Rectangle { x: 8; y: 8; width: parent.width * 0.5; height: 6; radius: 3; color: mode.modelData.light ? "#17131F" : "#ECE9F7"; opacity: 0.6 }
                            Rectangle { x: 8; y: 20; width: parent.width * 0.7; height: 6; radius: 3; color: mode.modelData.light ? "#17131F" : "#ECE9F7"; opacity: 0.3 }
                            Rectangle { x: 8; y: 32; width: 24; height: 10; radius: 5; color: Theme.accent }
                        }
                        Rectangle { anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 7 } width: parent.width * 0.42; height: 12; radius: 6; color: mode.bg; opacity: 0.92 }
                    }
                    Column {
                        anchors { right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
                        spacing: 6
                        Sym { name: mode.modelData.light ? "sun" : "moon"; size: 26; color: Theme.accent; anchors.right: parent.right }
                        Label { text: I18n.tr(mode.modelData.name); size: "title"; anchors.right: parent.right }
                    }
                }
            }
        }

        Label { text: I18n.tr("Акцент"); font.weight: Font.DemiBold }
        Row {
            spacing: 12
            Repeater {
                model: Theme.accents
                delegate: Rectangle {
                    id: dot
                    required property string modelData
                    readonly property bool on: Theme.accent.toString().toUpperCase() === modelData.toUpperCase()
                    width: 38; height: 38; radius: 19
                    color: modelData
                    border.width: on ? 3 : 0
                    border.color: Theme.fg
                    scale: dotTap.pressed ? 0.85 : on ? 1.14 : dotTap.containsMouse ? 1.08 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.OutBack; easing.overshoot: 3 } }
                    Sym { anchors.centerIn: parent; name: "check"; size: 16; color: "white"; visible: dot.on }
                    MouseArea {
                        id: dotTap
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { Settings.set("appearance.accent", dot.modelData); Sounds.play("oobe-select", 60); }
                    }
                }
            }
        }

        Label { text: I18n.tr("Готовые сочетания"); font.weight: Font.DemiBold; Layout.topMargin: 2 }
        Flow {
            Layout.fillWidth: true
            spacing: 10
            Repeater {
                model: root.presets
                delegate: Rectangle {
                    id: pre
                    required property string modelData
                    readonly property var t: Theme.themes.find(x => x.id === modelData) || ({ rgb: [0, 0, 0], name: modelData })
                    readonly property bool on: root.theme === modelData
                    implicitWidth: preRow.implicitWidth + 26
                    implicitHeight: 40
                    radius: 20
                    color: Qt.rgba(t.rgb[0] / 255, t.rgb[1] / 255, t.rgb[2] / 255, 1)
                    border.width: on ? 2 : 1
                    border.color: on ? (t.accent || Theme.accent) : Theme.line
                    scale: preTap.pressed ? 0.92 : preTap.containsMouse ? 1.05 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.OutBack; easing.overshoot: 3 } }
                    Row {
                        id: preRow
                        anchors.centerIn: parent
                        spacing: 8
                        Rectangle { width: 14; height: 14; radius: 7; color: pre.t.accent || Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                        Label { text: I18n.tr(pre.t.name); color: pre.t.light ? "#17131F" : "#ECE9F7"; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea {
                        id: preTap
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { root.setTheme(pre.modelData); Sounds.play("oobe-select", 60); }
                    }
                }
            }
        }
        Item { Layout.fillHeight: true }
    }
}
