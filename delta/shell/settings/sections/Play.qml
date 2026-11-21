pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common
import qs.common.ui
import qs.settings
import qs.settings.parts
import qs.play

// Delta Play: игровой режим (services/GameMode в оболочке), игровая панель
// Super+G, библиотека игр (delta-play) и свои игры — классы окон, которые
// тоже считаются игрой (play.games, регулярные выражения без учёта регистра).
// Состояние режима спрашиваем у оболочки (delta-play status): «Настройки» —
// отдельный процесс, и свой GameMode здесь включил бы режим второй раз.
ColumnLayout {
    id: root

    property string title: "Delta Play"
    property string icon: "gamepad"
    property string keywords: "игры игровой режим steam epic proton не беспокоить производительность панель super+g библиотека окно класс"
    spacing: 18

    property var status: null            // { active, manual, game }
    readonly property var games: Settings.get("play.games", []) || []
    readonly property var hidden: Settings.get("play.hidden", []) || []

    function refresh() {
        Exec.read(["delta-play", "status"], (code, out) => {
            let s = null;
            try { s = code === 0 ? JSON.parse(out.trim().replace(/^"|"$/g, "").replace(/\\"/g, '"')) : null; } catch (e) {}
            root.status = s;
        });
    }
    function addGame(text) {
        const p = text.trim();
        if (!p || games.indexOf(p) !== -1) return;
        try { new RegExp(p, "i"); } catch (e) { return; }
        Settings.set("play.games", games.concat([p]));
    }
    Component.onCompleted: refresh()
    Timer { interval: 3000; running: root.visible; repeat: true; onTriggered: root.refresh() }

    Card {
        title: I18n.tr("Игровой режим")
        SettingRow {
            icon: "gamepad"
            title: root.status?.active ? I18n.tr("Сейчас включён") : I18n.tr("Сейчас выключен")
            subtitle: root.status?.game ? (root.status.game.title || root.status.game.class)
                : root.status?.manual ? I18n.tr("включён вручную") : I18n.tr("Игра не запущена")
            Toggle {
                enabled: root.status !== null
                checked: root.status?.manual === true
                onToggled: v => { Exec.read(["delta-play", v ? "on" : "off"], () => root.refresh()); }
            }
        }
        SettingRow {
            icon: "rocket"
            title: I18n.tr("Включать сам")
            subtitle: I18n.tr("Пока открыто окно игры: Steam, Proton и Wine, gamescope, Minecraft и ваши игры ниже")
            Toggle { checked: Settings.get("play.auto", true) !== false; onToggled: v => Settings.set("play.auto", v) }
        }
        SettingRow {
            icon: "bell-off"
            title: I18n.tr("Не беспокоить во время игры")
            subtitle: I18n.tr("Уведомления не всплывают поверх игры, после неё — как было")
            Toggle { checked: Settings.get("play.dnd", true) !== false; onToggled: v => Settings.set("play.dnd", v) }
        }
        SettingRow {
            icon: "gauge"
            title: I18n.tr("Максимальная производительность")
            subtitle: I18n.tr("Профиль питания «Производительность» на время игры, пароль не нужен")
            Toggle { checked: Settings.get("play.performance", true) !== false; onToggled: v => Settings.set("play.performance", v) }
        }
        SettingRow {
            icon: "monitor"
            title: I18n.tr("Больше кадров в играх")
            subtitle: I18n.tr("Игра на весь экран показывает кадр сразу, не дожидаясь монитора: больше FPS и меньше задержка. В движении иногда заметны разрывы кадра")
            Toggle { checked: Settings.get("games.tearing", true) !== false; onToggled: v => Settings.set("games.tearing", v) }
        }
    }

    Card {
        title: I18n.tr("Оверлей в игре")
        HudOptions {
            Layout.fillWidth: true
            onOpenSettings: section => Nav.open(section)
        }
    }

    Card {
        title: I18n.tr("Игровая панель и библиотека")
        SettingRow {
            icon: "keyboard"
            title: I18n.tr("Игровая панель")
            subtitle: I18n.tr("Super+G поверх игры: загрузка и температуры, профиль, звук, музыка, снимок экрана")
            KeyCaps { keys: ["Super", "G"] }
        }
        SettingRow {
            icon: "grid"
            title: I18n.tr("Библиотека Delta Play")
            subtitle: root.hidden.length > 0 ? I18n.tr("Скрыто игр: ") + root.hidden.length : I18n.tr("Игры Steam, Epic, Windows и Linux в одном окне")
            RowLayout {
                spacing: 8
                Btn {
                    visible: root.hidden.length > 0
                    text: I18n.tr("Вернуть скрытые"); kind: "ghost"; icon: "eye"
                    onClicked: Settings.set("play.hidden", [])
                }
                Btn { text: I18n.tr("Открыть"); kind: "soft"; icon: "arrow-right"; onClicked: Quickshell.execDetached(["delta-play"]) }
            }
        }
    }

    Card {
        title: I18n.tr("Свои игры")
        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            tone: 3
            size: "small"
            text: I18n.tr("Если игровой режим не узнаёт игру, добавьте класс её окна (можно часть или шаблон, например «^factorio$»)")
        }
        Repeater {
            model: root.games
            delegate: SettingRow {
                required property string modelData
                icon: "gamepad"
                title: modelData
                Btn { icon: "trash"; kind: "ghost"; onClicked: Settings.set("play.games", root.games.filter(x => x !== modelData)) }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Field {
                id: gameField
                Layout.fillWidth: true
                icon: "gamepad"
                placeholder: I18n.tr("Класс окна игры")
                clearable: true
                onAccepted: { root.addGame(text); text = ""; }
            }
            Btn {
                text: I18n.tr("Добавить")
                kind: "accent"
                enabled: gameField.text.trim().length > 0
                onClicked: { root.addGame(gameField.text); gameField.text = ""; }
            }
        }
    }
}
