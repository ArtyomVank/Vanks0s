pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.lock.parts

// «Добро пожаловать» с первого кадра оболочки при запуске сессии. Раньше,
// пока оболочка грузилась, а блокировка решала, показываться ли, были видны
// собирающийся рабочий стол и окна автозапуска. Теперь заставка закрывает
// всё (слой overlay — над окнами), пока:
//   - не встала блокировка при запуске (у неё своя такая же заставка) —
//     тогда эта просто исчезает под ней;
//   - или не готов стол — тогда надпись гаснет, и стол открывается целиком.
// Начало сессии отмечает delta-shell: DELTA_SESSION_START=1 получает только
// первая копия оболочки, после перезапуска (падения) заставки нет.
// Автозапуск XDG (dex -a) — тоже отсюда, когда заставка ушла: раньше его
// запускал Hyprland вместе с оболочкой, и программы появлялись раньше неё.
Scope {
    id: root

    required property var lock

    readonly property bool sessionStart: Quickshell.env("DELTA_SESSION_START") === "1"
    property bool covering: sessionStart
    // заставка уходит: надпись гаснет, потом сама заставка (WelcomeCard)
    property bool leaving: false

    // не меньше — чтобы не мигнула; после входа паролем она уже была на экране входа
    property bool minShown: false
    Timer {
        running: root.sessionStart
        interval: Quickshell.env("DELTA_LOGIN") === "greeter" ? 900 : 1600
        onTriggered: root.minShown = true
    }

    readonly property bool ready: lock.startChecked && Settings.ready && minShown
    onReadyChanged: if (ready && covering) {
        // блокировка закрыла экран — уходим под ней, когда её поверхность уже есть
        if (lock.locked) dropTimer.start();
        else leaving = true;
    }
    Timer { id: dropTimer; interval: 800; onTriggered: root.finish() }
    // что-то не ответило — стол всё равно открываем
    Timer { running: root.covering; interval: 10000; onTriggered: root.leaving = true }

    function finish() {
        if (!covering) return;
        covering = false;
        // Автозапуск ждёт ввода пароля. При автовходе связку ключей открывает
        // пароль на экране блокировки, а браузер, запущенный раньше, успевал
        // показать своё окно «разблокируйте связку» — поверх уже открытой.
        if (lock.locked) autostartAfterUnlock = true;
        else autostart();
    }
    property bool autostartAfterUnlock: false
    Connections {
        target: root.lock
        function onLockedChanged() {
            if (root.lock.locked || !root.autostartAfterUnlock) return;
            root.autostartAfterUnlock = false;
            root.autostart();
        }
    }

    // один раз за сессию: метка в XDG_RUNTIME_DIR своя у каждого запуска Hyprland.
    // Вложенная сессия разработчика не запускает вторые копии программ.
    function autostart() {
        if ((Quickshell.env("DELTA_NESTED") || "") !== "") return;
        Quickshell.execDetached(["sh", "-c",
            "m=\"${XDG_RUNTIME_DIR:-/tmp}/delta-autostart-${HYPRLAND_INSTANCE_SIGNATURE:-0}\"; " +
            "[ -e \"$m\" ] && exit 0; : > \"$m\"; command -v dex >/dev/null && exec dex -a"]);
    }
    Component.onCompleted: if (!sessionStart) autostart()

    Variants {
        model: root.covering ? Quickshell.screens : []
        delegate: PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "delta-start"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"

            WelcomeCard {
                anchors.fill: parent
                done: root.leaving
                onOpacityChanged: if (root.leaving && opacity === 0) root.finish()
            }
        }
    }
}
