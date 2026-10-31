pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.lock.parts

// Вход с экрана входа (greeter передаёт DELTA_LOGIN=greeter): пока оболочка
// грузит обои, доки и виджеты, поверх всего — «Добро пожаловать, подождите»
// в цвет фона Hyprland, потом заставка тает и звучит вход. Заставка не
// возвращается при перезагрузке оболочки (PersistentProperties).
Scope {
    id: root

    readonly property bool fromGreeter: Quickshell.env("DELTA_LOGIN") === "greeter"

    PersistentProperties {
        id: persist
        reloadableId: "delta-welcome"
        property bool done: false
    }

    property bool shown: fromGreeter && !persist.done
    property bool leaving: false

    // рабочий стол успел нарисоваться: настройки прочитаны и ещё чуть-чуть
    // на обои и доки; дольше 8 с не держим ни в каком случае
    Timer {
        id: settle
        interval: 1400
        running: root.shown && Settings.ready
        onTriggered: root.leave()
    }
    Timer { interval: 8000; running: root.shown; onTriggered: root.leave() }
    function leave() {
        if (leaving || !shown) return;
        leaving = true;
        Account.refresh();
        Sounds.play("service-login");
        gone.restart();
    }
    Timer { id: gone; interval: 700; onTriggered: { persist.done = true; root.shown = false; } }

    Variants {
        model: root.shown ? Quickshell.screens : []

        delegate: PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "delta-welcome"
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"

            WelcomeCard {
                anchors.fill: parent
                name: Account.name
                opacity: root.leaving ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
            }
        }
    }
}
