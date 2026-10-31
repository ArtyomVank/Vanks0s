import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.common
import qs.docks

// Мелкие звуки и эффекты оболочки (только в процессе delta-shell — в
// «Настройках» и помощнике Sounds тоже есть, но эти события им не нужны):
// смена рабочего стола, открытие меню доков, музыка на острове, вспышка
// снимка экрана.
//     delta-shell ipc call fx flash
Scope {
    id: root

    // рабочий стол сменился — стеклянный тик
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() { Sounds.play("workspace", 180); }
    }
    // меню из дока — «бульк»
    Connections {
        target: ShellState
        function onMenuChanged() { if (ShellState.menu !== "") Sounds.play("pop", 120); }
    }
    // заиграла музыка — остров распускается
    Connections {
        target: DockService
        function onMediaPillChanged() { if (DockService.mediaPill) Sounds.play("island", 4000); }
    }

    function flash() {
        flashWin.visible = true;
        flashAnim.restart();
    }

    IpcHandler {
        target: "fx"
        function flash(): void {
            root.flash();
            ShellState.island({ kind: "shot", icon: "screenshot", title: I18n.tr("Снимок экрана"), text: I18n.tr("Скопирован") });
        }
    }

    // вспышка снимка: белая пелена гаснет за треть секунды, ввод не ловит
    PanelWindow {
        id: flashWin
        visible: false
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) || Quickshell.screens[0] || null
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "delta-flash"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        mask: Region {}

        Rectangle {
            id: veil
            anchors.fill: parent
            color: "white"
            opacity: 0
        }
        SequentialAnimation {
            id: flashAnim
            NumberAnimation { target: veil; property: "opacity"; from: 0; to: 0.75; duration: 50 }
            NumberAnimation { target: veil; property: "opacity"; to: 0; duration: 380; easing.type: Easing.OutCubic }
            ScriptAction { script: flashWin.visible = false }
        }
    }
}
