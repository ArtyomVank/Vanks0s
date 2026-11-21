pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.common.ui
import qs.docks
import qs.services

// Оверлей в игре (play.hud.*, выбирается в HudOptions): строка показателей
// в углу экрана, пока включён игровой режим.
//   • сессия с MangoHud (HudItems.mangoActive) — рисует он, внутри игры: FPS,
//     время кадра и остальное. Здесь только пишем его файл настроек — при
//     каждой смене выбора и режима; MangoHud перечитывает его сам;
//   • без MangoHud — своя стеклянная полоска на слое поверх всего (кроме FPS:
//     кадры чужой игры оболочке не видны). Нажатия проходят сквозь неё.
Scope {
    id: root

    readonly property bool on: Settings.get("play.hud.on", false) === true
    readonly property var items: Settings.get("play.hud.items", null) || HudItems.defaults
    readonly property string corner: Settings.get("play.hud.corner", "tl")
    readonly property bool inGame: GameMode.active
    function has(id) { return items.indexOf(id) !== -1; }
    // своя полоска показывает всё, кроме FPS и времени кадра
    readonly property bool ownItems: items.some(x => x !== "fps" && x !== "frametime")

    // --- MangoHud: файл настроек ---
    readonly property string mangoText: HudItems.mangoActive ? HudItems.mangoConf(on && inGame, items, corner) : ""
    onMangoTextChanged: writeMango()
    Component.onCompleted: writeMango()
    function writeMango() {
        if (!HudItems.mangoActive) return;
        // на месте, без mv: MangoHud следит за самим файлом
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" > "$2"', "sh", mangoText, HudItems.mangoFile]);
    }

    // --- своя полоска ---
    LazyLoader {
        active: root.on && root.inGame && !HudItems.mangoActive && !ShellState.locked && root.ownItems

        PanelWindow {
            id: hud
            screen: DockService.focusedScreen()
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "delta-hud"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors {
                top: root.corner[0] === "t"; bottom: root.corner[0] === "b"
                left: root.corner[1] === "l"; right: root.corner[1] === "r"
            }
            margins { top: 14; bottom: 14; left: 14; right: 14 }
            implicitWidth: bar.implicitWidth
            implicitHeight: bar.implicitHeight
            color: "transparent"
            // сквозь полоску щелчки идут в игру
            mask: Region {}

            StatsUser { active: true; gpu: root.has("gpu") || root.has("vram") }
            property real now: Date.now()
            Timer { interval: 1000; running: root.has("time"); repeat: true; onTriggered: hud.now = Date.now() }

            function pct(v) { return v >= 0 ? Math.round(v) + "%" : "—"; }
            function deg(v) { return v >= 0 ? " " + Math.round(v) + "°" : ""; }

            Rectangle {
                id: bar
                implicitWidth: row.implicitWidth + 24
                implicitHeight: 34
                radius: height / 2
                color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.62)
                border.width: 1
                border.color: Theme.line

                Row {
                    id: row
                    anchors.centerIn: parent
                    spacing: 14

                    component Cell: Row {
                        property string name
                        property string value
                        spacing: 5
                        Label { anchors.verticalCenter: parent.verticalCenter; text: parent.name; size: "caption"; font.weight: Font.Bold; color: Theme.accent }
                        Label { anchors.verticalCenter: parent.verticalCenter; text: parent.value; size: "small"; num: true; color: "white" }
                    }

                    Cell { visible: root.has("cpu"); name: "CPU"; value: hud.pct(SystemStats.cpu) + hud.deg(SystemStats.cpuTemp) }
                    Cell { visible: root.has("gpu"); name: "GPU"; value: hud.pct(SystemStats.gpu) + hud.deg(SystemStats.gpuTemp) }
                    Cell { visible: root.has("ram"); name: "RAM"; value: SystemStats.ramUsed > 0 ? SystemStats.bytes(SystemStats.ramUsed) : "—" }
                    Cell { visible: root.has("vram") && SystemStats.vramTotal > 0; name: "VRAM"; value: SystemStats.bytes(SystemStats.vramUsed) }
                    Cell { visible: root.has("battery") && DockService.hasBattery; name: I18n.tr("БАТ"); value: DockService.batteryPercent + "%" }
                    Cell { visible: root.has("time"); name: ""; value: Qt.formatTime(new Date(hud.now), "hh:mm") }
                }
            }
        }
    }
}
