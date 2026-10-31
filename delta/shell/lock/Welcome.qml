pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.lock.parts

// Запуск сессии без блокировки (вошли паролем на экране входа или автовход
// без «Блокировать при запуске»): пока оболочка грузит обои, доки и виджеты,
// поверх всего — «Добро пожаловать, подождите» в цвет фона Hyprland, потом
// заставка тает и звучит вход.
//
// Заставка — с первого кадра оболочки, чтобы не мелькнул пустой стол; что
// дальше, решает Lock.qml: release() — тает в рабочий стол, dismiss() — сразу
// убрать (блокировка при запуске: та же заставка уже лежит на экране
// блокировки, Lock.qml welcome; или это не первый запуск оболочки в сессии).
// Перезагрузка оболочки заставку не возвращает (PersistentProperties).
Scope {
    id: root

    PersistentProperties {
        id: persist
        reloadableId: "delta-welcome"
        property bool done: false
    }

    property bool shown: false
    property bool leaving: false
    property bool go: false
    Component.onCompleted: if (!persist.done) shown = true
    function release() { if (shown) go = true; }
    // под блокировкой заставку убираем не сразу: экран блокировки появляется
    // через кадр-другой, и между ними мелькнул бы стол
    function dismiss() { persist.done = true; later.restart(); }
    Timer { id: later; interval: 500; onTriggered: root.shown = false }

    // рабочий стол успел нарисоваться: настройки прочитаны и ещё чуть-чуть
    // на обои и доки; дольше 8 с не держим ни в каком случае
    Timer {
        interval: 1400
        running: root.shown && root.go && !root.leaving && Settings.ready
        onTriggered: root.leave()
    }
    Timer { interval: 8000; running: root.shown && !root.leaving; onTriggered: root.leave() }
    function leave() {
        if (leaving || !shown) return;
        leaving = true;
        persist.done = true;
        Sounds.play("service-login");
        gone.restart();
    }
    Timer { id: gone; interval: 700; onTriggered: root.shown = false }

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
