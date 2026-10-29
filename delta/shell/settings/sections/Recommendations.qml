pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common
import qs.common.ui
import qs.settings
import qs.settings.parts

// Рекомендации: вход в помощник «Добро пожаловать» (delta-welcome), если его
// закрыли при первом запуске. Нажатие закрывает «Настройки» и открывает
// помощник на нужном разделе. Помощник ничего не ставит без подтверждения,
// поэтому открывается и в пробном режиме (он сам видит DELTA_DRY_RUN).
ColumnLayout {
    id: root

    property string title: I18n.tr("Рекомендации")
    property string icon: "gamepad"
    property string keywords: "добро пожаловать помощник драйверы видеокарта nvidia amd intel vulkan steam chromium игры библиотеки магазин приложения exe windows wine proton cachyos лаунчер"
    spacing: 18

    // .exe: запомненные «всегда обычно» и «всегда через лаунчер»
    readonly property var excluded: Settings.get("exe.excluded", []) || []
    readonly property var always: Settings.get("exe.always", {}) || {}
    readonly property var alwaysKeys: Object.keys(always).sort()
    function runnerName(r) {
        if (r === "auto") return I18n.tr("Авто");
        if (r === "wine") return "Wine";
        return String(r).replace(/^proton:/, "").split("/").pop();
    }
    function addExcluded(name) {
        const n = name.trim().toLowerCase();
        if (!n.length) return;
        const full = /\.(exe|msi)$/.test(n) ? n : n + ".exe";
        Settings.set("exe.excluded", excluded.filter(x => x.toLowerCase() !== full).concat([full]));
        // одна программа — один выбор
        if (always[full] !== undefined) forget(full);
    }
    function removeExcluded(name) { Settings.set("exe.excluded", excluded.filter(x => x !== name)); }
    function forget(name) {
        const m = Object.assign({}, always);
        delete m[name];
        Settings.set("exe.always", m);
    }

    function openWelcome(section) {
        Quickshell.execDetached(["delta-welcome"].concat(section ? [section] : []));
        Nav.closeRequested();
    }

    // --- шапка ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 136
        radius: Theme.radius - 2
        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.4)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.26) }
            GradientStop { position: 1; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.05) }
        }
        RowLayout {
            anchors { fill: parent; margins: 22 }
            spacing: 20
            Rectangle {
                implicitWidth: 72; implicitHeight: 72; radius: 22
                color: Theme.accent
                Sym { anchors.centerIn: parent; name: "gamepad"; size: 36; color: Theme.onAccent }
            }
            ColumnLayout {
                spacing: 4
                Layout.fillWidth: true
                Label { text: I18n.tr("Подготовить систему"); size: "h1"; Layout.fillWidth: true }
                Label {
                    text: I18n.tr("Библиотеки для игр, драйвер под вашу видеокарту и полезные приложения — в одном окне")
                    tone: 2; wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }
            Btn { text: I18n.tr("Открыть"); kind: "accent"; icon: "arrow-right"; onClicked: root.openWelcome("") }
        }
    }

    Card {
        title: I18n.tr("Разделы")
        Rows {
            SettingRow {
                icon: "layers"
                title: I18n.tr("Библиотеки")
                subtitle: I18n.tr("Vulkan, 32-битные библиотеки, GameMode, кодеки, Wine")
                Btn { text: I18n.tr("Открыть"); onClicked: root.openWelcome("libs") }
            }
            SettingRow {
                icon: "gpu"
                title: I18n.tr("Драйверы")
                subtitle: I18n.tr("Подберём драйвер под видеокарту этого компьютера и игровое ядро")
                Btn { text: I18n.tr("Открыть"); onClicked: root.openWelcome("drivers") }
            }
            SettingRow {
                icon: "apps"
                title: I18n.tr("Приложения")
                subtitle: I18n.tr("Steam, Chromium, Discord и магазин приложений")
                Btn { text: I18n.tr("Открыть"); onClicked: root.openWelcome("apps") }
            }
        }
    }

    Card {
        title: I18n.tr("При входе")
        SettingRow {
            icon: "rocket"
            title: I18n.tr("Показывать помощник при входе")
            subtitle: I18n.tr("Пока вы его не закроете, он будет встречать вас после включения")
            Toggle { checked: Settings.get("welcome.done", false) !== true; onToggled: v => Settings.set("welcome.done", !v) }
        }
    }

    Card {
        title: I18n.tr("Программы Windows")
        Rows {
            SettingRow {
                icon: "rocket"
                title: I18n.tr("Спрашивать, как открыть .exe")
                subtitle: I18n.tr("Обычно через Wine или через лаунчер с Proton CachyOS. «Авто» — самый свежий Proton CachyOS")
                Toggle { checked: Settings.get("exe.enabled", true) !== false; onToggled: v => Settings.set("exe.enabled", v) }
            }
            SettingRow {
                icon: "file"
                title: I18n.tr("Всегда открывать обычно")
                subtitle: root.excluded.length ? I18n.tr("Эти программы открываются без вопроса, через Wine системы") : I18n.tr("Пока пусто — добавьте имя файла, например setup.exe")
                wide: true
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: root.excluded
                        delegate: RowLayout {
                            id: exRow
                            required property string modelData
                            Layout.fillWidth: true
                            spacing: 8
                            Label { text: exRow.modelData; font.family: Theme.fontMono; Layout.fillWidth: true }
                            Btn { icon: "close"; iconSize: 14; kind: "ghost"; onClicked: root.removeExcluded(exRow.modelData) }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Field { id: exField; Layout.fillWidth: true; icon: "file"; placeholder: I18n.tr("Имя программы, например setup.exe"); maxLength: 120; onAccepted: { root.addExcluded(text); text = ""; } }
                        Btn { text: I18n.tr("Добавить"); icon: "plus"; enabled: exField.text.trim().length > 0; onClicked: { root.addExcluded(exField.text); exField.text = ""; } }
                    }
                }
            }
            SettingRow {
                visible: root.alwaysKeys.length > 0
                icon: "gamepad"
                title: I18n.tr("Всегда через лаунчер")
                subtitle: I18n.tr("Запомнено галочкой «Всегда так» в окне запуска")
                wide: true
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: root.alwaysKeys
                        delegate: RowLayout {
                            id: alRow
                            required property string modelData
                            Layout.fillWidth: true
                            spacing: 8
                            Label { text: alRow.modelData; font.family: Theme.fontMono; Layout.fillWidth: true }
                            Label { text: root.runnerName(root.always[alRow.modelData]); tone: 3; size: "small" }
                            Btn { icon: "close"; iconSize: 14; kind: "ghost"; onClicked: root.forget(alRow.modelData) }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: Nav
        function onAction(name, arg) {
            if (name === "recommendations.open") root.openWelcome(arg);
        }
    }
}
