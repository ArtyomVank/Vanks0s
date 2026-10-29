pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.common

// Виджеты рабочего стола одного монитора.
//
// Обычно — слой Bottom (под окнами), ввод только над виджетами: остальной
// рабочий стол «прозрачен» для кликов. В редакторе (ShellState.widgetEditing,
// Super+W) окно поднимается на слой Top, забирает весь экран и клавиатуру
// (Esc — готово). Редактор открывается только на мониторе с фокусом,
// на остальных сетка видна как обычно и сразу показывает изменения.
Scope {
    id: root

    required property ShellScreen screen
    property alias grid: grid

    // редактор открыт именно здесь
    property bool editingHere: false
    readonly property bool primary: Quickshell.screens.length > 0 && Quickshell.screens[0] === screen

    function focusedHere() {
        const m = Hyprland.focusedMonitor;
        return Quickshell.screens.length <= 1 || (m ? m.name === screen.name : primary);
    }
    Connections {
        target: ShellState
        function onWidgetEditingChanged() { root.editingHere = ShellState.widgetEditing && root.focusedHere(); }
    }
    Component.onCompleted: editingHere = ShellState.widgetEditing && focusedHere()

    PanelWindow {
        id: win
        screen: root.screen
        WlrLayershell.namespace: "delta-widgets"
        WlrLayershell.layer: root.editingHere ? WlrLayer.Top : WlrLayer.Bottom
        WlrLayershell.keyboardFocus: root.editingHere ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"

        // ввод: весь экран в редакторе, иначе только прямоугольники виджетов
        mask: root.editingHere ? fullRegion : widgetRegion
        Region { id: fullRegion; item: grid }
        Region { id: widgetRegion; regions: boxRegions.instances }
        Variants {
            id: boxRegions
            model: grid.boxes
            delegate: Region {
                required property var modelData
                x: modelData.x; y: modelData.y
                width: modelData.w; height: modelData.h
            }
        }

        WidgetGrid {
            id: grid
            anchors.fill: parent
            place: "desktop"
            editing: root.editingHere
            // под блокировкой виджеты не нужны; при разблокировке проступают
            // вслед за обоями — чуть из глубины, с лёгкой пружиной
            opacity: ShellState.desktopShown ? 1 : 0
            scale: ShellState.desktopShown ? 1 : 0.94
            visible: opacity > 0
            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: ShellState.desktopShown ? 90 : 0 }
                    NumberAnimation { duration: ShellState.desktopShown ? 520 : 260; easing.type: Easing.OutCubic }
                }
            }
            Behavior on scale {
                SequentialAnimation {
                    PauseAnimation { duration: ShellState.desktopShown ? 90 : 0 }
                    NumberAnimation { duration: ShellState.desktopShown ? 760 : 260; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
                }
            }
        }
    }

    // delta-shell ipc call widgets edit|done|toggle — для «Настроек» (отдельный процесс).
    // Обработчик один на оболочку: живёт на первом мониторе.
    IpcHandler {
        target: "widgets"
        enabled: root.primary

        // «Открыть» в настройках: повторное нажатие закрывает редактор, как Esc.
        function edit(): void { ShellState.widgetEditing = !ShellState.widgetEditing; }
        function done(): void { ShellState.widgetEditing = false; }
        function toggle(): void { ShellState.widgetEditing = !ShellState.widgetEditing; }
        // выбрать виджет в редакторе (проверки, «Настройки»): widgets select clock
        function select(id: string): void { if (root.editingHere) grid.select(id); }
    }
}
