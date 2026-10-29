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

    property string title: "Рекомендации"
    property string icon: "gamepad"
    property string keywords: "добро пожаловать помощник драйверы видеокарта nvidia amd intel vulkan steam chromium игры библиотеки магазин приложения"
    spacing: 18

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
                Label { text: "Подготовить систему"; size: "h1"; Layout.fillWidth: true }
                Label {
                    text: "Библиотеки для игр, драйвер под вашу видеокарту и полезные приложения — в одном окне"
                    tone: 2; wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }
            Btn { text: "Открыть"; kind: "accent"; icon: "arrow-right"; onClicked: root.openWelcome("") }
        }
    }

    Card {
        title: "Разделы"
        Rows {
            SettingRow {
                icon: "layers"
                title: "Библиотеки"
                subtitle: "Vulkan, 32-битные библиотеки, GameMode, кодеки, Wine"
                Btn { text: "Открыть"; onClicked: root.openWelcome("libs") }
            }
            SettingRow {
                icon: "gpu"
                title: "Драйверы"
                subtitle: "Подберём драйвер под видеокарту этого компьютера и игровое ядро"
                Btn { text: "Открыть"; onClicked: root.openWelcome("drivers") }
            }
            SettingRow {
                icon: "apps"
                title: "Приложения"
                subtitle: "Steam, Chromium, Discord и магазин приложений"
                Btn { text: "Открыть"; onClicked: root.openWelcome("apps") }
            }
        }
    }

    Card {
        title: "При входе"
        SettingRow {
            icon: "rocket"
            title: "Показывать помощник при входе"
            subtitle: "Пока вы его не закроете, он будет встречать вас после включения"
            Toggle { checked: Settings.get("welcome.done", false) !== true; onToggled: v => Settings.set("welcome.done", !v) }
        }
    }

    Connections {
        target: Nav
        function onAction(name, arg) {
            if (name === "recommendations.open") root.openWelcome(arg);
        }
    }
}
