pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.common
import qs.common.ui

// Настройки оверлея в игре (play.hud.*) — одни и те же в игровой панели
// Super+G и в «Настройках» → Delta Play:
//   play.hud.on      показывать во время игры
//   play.hud.items   что: fps, frametime, cpu, gpu, ram, vram, time, battery
//   play.hud.corner  угол: tl, tr, bl, br
// FPS и время кадра считает MangoHud (слой Vulkan внутри игры): оболочка
// кадров чужой программы не видит. Без MangoHud оверлей рисует сама Delta —
// всё, кроме FPS. GameMode здесь не трогаем: «Настройки» — другой процесс.
ColumnLayout {
    id: root

    signal openSettings(string section)

    readonly property bool on: Settings.get("play.hud.on", false) === true
    readonly property var items: Settings.get("play.hud.items", null) || HudItems.defaults
    readonly property string corner: Settings.get("play.hud.corner", "tl")
    // MangoHud подключается при входе в сессию (delta-session): поставили
    // позже — заработает со следующего входа
    readonly property bool mangoActive: HudItems.mangoActive
    property bool mangoInstalled: mangoActive
    Process {
        running: !root.mangoActive
        command: ["sh", "-c", "ls /usr/share/vulkan/implicit_layer.d/ 2>/dev/null | grep -qi mangohud"]
        onExited: code => root.mangoInstalled = code === 0
    }

    function toggleItem(id) {
        const list = items.slice();
        const i = list.indexOf(id);
        if (i === -1) list.push(id); else list.splice(i, 1);
        // порядок — как в каталоге, а не как нажимали
        Settings.set("play.hud.items", HudItems.catalog.map(x => x.id).filter(x => list.indexOf(x) !== -1));
    }

    spacing: 10

    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        Rectangle {
            implicitWidth: 30; implicitHeight: 30; radius: 10
            color: root.on ? Theme.accent : Theme.soft2
            Sym { anchors.centerIn: parent; name: "gauge"; size: 16; color: root.on ? Theme.onAccent : Theme.fg2 }
        }
        ColumnLayout {
            spacing: 0
            Layout.fillWidth: true
            Label { text: I18n.tr("Оверлей в игре"); font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
            Label {
                text: root.mangoActive ? I18n.tr("FPS и показатели поверх игры (MangoHud)")
                    : I18n.tr("Показатели поверх игры")
                size: "caption"; tone: 3; Layout.fillWidth: true; elide: Text.ElideRight
            }
        }
        Toggle { checked: root.on; onToggled: v => Settings.set("play.hud.on", v) }
    }

    Chips {
        Layout.fillWidth: true
        multi: true
        currents: root.items
        model: HudItems.catalog.map(x => ({ value: x.id, label: I18n.tr(x.label) }))
        onPicked: v => root.toggleItem(v)
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        Label { text: I18n.tr("Угол"); size: "small"; tone: 3 }
        Chips {
            Layout.fillWidth: true
            model: [
                { value: "tl", label: "↖" }, { value: "tr", label: "↗" },
                { value: "bl", label: "↙" }, { value: "br", label: "↘" }
            ]
            current: root.corner
            onPicked: v => Settings.set("play.hud.corner", v)
        }
    }

    // FPS без MangoHud не посчитать — подсказать, как его получить
    RowLayout {
        visible: !root.mangoActive && root.items.some(x => x === "fps" || x === "frametime")
        Layout.fillWidth: true
        spacing: 10
        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            size: "caption"
            tone: 3
            text: root.mangoInstalled ? I18n.tr("MangoHud установлен — FPS появится после нового входа в систему")
                : I18n.tr("FPS считает MangoHud — поставьте его в «Рекомендациях» (Библиотеки)")
        }
        Btn {
            visible: !root.mangoInstalled
            text: I18n.tr("Открыть")
            kind: "soft"
            icon: "arrow-right"
            onClicked: root.openSettings("recommendations")
        }
    }
}
