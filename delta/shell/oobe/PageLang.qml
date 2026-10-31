pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui

// Шаг 1: язык системы и раскладки. Над выбором сменяются приветствия.
Page {
    id: root

    icon: "globe"
    title: I18n.tr("Добро пожаловать в Vanks OS")
    subtitle: I18n.tr("Несколько шагов — и система будет вашей. Для начала выберите язык.")

    readonly property var hellos: ["Привет", "Hello", "Bonjour", "Hola", "Hallo", "Ciao", "Olá", "Merhaba", "Cześć", "こんにちは", "你好", "안녕하세요"]
    property int hello: 0
    Timer { interval: 1700; running: root.shown; repeat: true; onTriggered: root.hello = (root.hello + 1) % root.hellos.length }

    readonly property var layouts: [
        { id: "us", name: "English (US)" }, { id: "ru", name: "Русская" }, { id: "ua", name: "Українська" },
        { id: "by", name: "Беларуская" }, { id: "kz", name: "Қазақша" }, { id: "de", name: "Deutsch" },
        { id: "fr", name: "Français" }, { id: "es", name: "Español" }
    ]
    readonly property var current: Settings.get("input.layouts", ["us", "ru"]) || []
    function toggleLayout(id) {
        let list = current.slice();
        if (list.indexOf(id) >= 0) { if (list.length > 1) list = list.filter(l => l !== id); }
        else list.push(id);
        Settings.set("input.layouts", list);
        Sounds.play("oobe-select", 60);
    }
    function pickLang(lang) {
        Settings.set("language.ui", lang);
        // с русским языком нужна и русская раскладка
        const l = current.slice();
        if (lang === "ru" && l.indexOf("ru") < 0) l.push("ru");
        Settings.set("input.layouts", l);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 22

        // приветствия
        Item {
            Layout.fillWidth: true
            implicitHeight: 64
            Repeater {
                model: root.hellos
                delegate: Label {
                    required property int index
                    required property string modelData
                    readonly property bool on: index === root.hello
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData
                    size: "display"
                    font.pixelSize: 48
                    color: Theme.accent
                    opacity: on ? 1 : 0
                    scale: on ? 1 : 0.86
                    transform: Translate { y: on ? 0 : 18 }
                    Behavior on opacity { NumberAnimation { duration: 520 * Theme.anim.k; easing.type: Easing.InOutCubic } }
                    Behavior on scale { NumberAnimation { duration: 700 * Theme.anim.k; easing.type: Easing.OutBack } }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            Repeater {
                model: [{ id: "ru", name: "Русский", hint: "Интерфейс на русском" }, { id: "en", name: "English", hint: "Interface in English" }]
                delegate: Choice {
                    id: lc
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 96
                    selected: I18n.lang === modelData.id
                    onPicked: root.pickLang(modelData.id)
                    Column {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 24 }
                        spacing: 4
                        Label { text: lc.modelData.name; size: "title"; font.pixelSize: 22 }
                        Label { text: lc.modelData.hint; tone: 3; size: "small" }
                    }
                }
            }
        }

        Label { text: I18n.tr("Раскладки клавиатуры"); font.weight: Font.DemiBold; Layout.topMargin: 4 }
        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: root.layouts
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool on: root.current.indexOf(modelData.id) >= 0
                    implicitWidth: chipRow.implicitWidth + 28
                    implicitHeight: 36
                    radius: 18
                    color: on ? Theme.accent : chipTap.containsMouse ? Theme.soft2 : Theme.soft
                    border.width: on ? 0 : 1
                    border.color: Theme.line
                    scale: chipTap.pressed ? 0.92 : 1
                    Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
                    Behavior on scale { NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.OutBack; easing.overshoot: 3 } }
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 8
                        Label { text: chip.modelData.id.toUpperCase(); font.family: Theme.fontMono; size: "small"; color: chip.on ? Theme.onAccent : Theme.fg3; anchors.verticalCenter: parent.verticalCenter }
                        Label { text: chip.modelData.name; color: chip.on ? Theme.onAccent : Theme.fg; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea { id: chipTap; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleLayout(chip.modelData.id) }
                }
            }
        }
        Item { Layout.fillHeight: true }
    }
}
