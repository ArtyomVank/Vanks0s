pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.common
import qs.lock
import qs.lock.parts
import qs.greeter

// Экран входа Delta — greeter для greetd. Выглядит как экран блокировки
// (тот же LockSurface): обои и тема последнего пользователя, часы, аватар.
// После включения сначала «Добро пожаловать» (WelcomeCard), потом экран входа;
// после выхода из сессии — сразу экран входа.
// После пароля доигрывает анимацию разблокировки и только потом просит greetd
// запустить сессию — greetd ждёт, что greeter сразу завершится.
//
//   qs -p /usr/share/delta/shell/greeter.qml          (так запускает session/greetd/hyprland.lua)
//   DELTA_GREETER_MOCK=1 — без greetd, для вложенной сессии:
//   DELTA_GREETER_MOCK=1 DELTA_DEV_NAME=lock DELTA_DEV_HIDDEN=1 \
//       DELTA_SHELL_ENTRY=delta/shell/greeter.qml tools/delta-dev.sh nested 300
ShellRoot {
    id: shell

    Backend { id: be }

    signal exitRequested()
    signal resetRequested()
    property bool leaving: false
    // «Добро пожаловать» — только при первом запуске после включения
    // компьютера (метка в /run/delta-greeter, tmpfs, и включён меньше 2 минут).
    // После выхода из сессии
    // экран входа появляется сразу
    property bool starting: true
    property int welcome: -1             // -1 — ещё не знаем, 1 — показать, 0 — без заставки
    readonly property string bootMark: (Quickshell.env("DELTA_GREETER_RUN") || "/run/delta-greeter") + "/started"
    Process {
        running: true
        // при автовходе greeter после включения не запускался — метки нет, но
        // компьютер включён давно: это выход из сессии
        command: ["sh", "-c", 'test -e "$1" && exit 1; touch "$1" 2>/dev/null; awk "{ exit !(\\$1 < 120) }" /proc/uptime', "sh", shell.bootMark]
        onExited: code => {
            shell.welcome = code === 0 ? 1 : 0;
            if (code === 0) welcomeTimer.start(); else shell.starting = false;
        }
    }
    Timer { id: welcomeTimer; interval: 1600; onTriggered: shell.starting = false }

    Connections {
        target: be
        function onReady() {
            if (shell.leaving) return;
            shell.leaving = true;
            shell.exitRequested();
            launchTimer.restart();
        }
    }
    Timer {
        id: launchTimer
        interval: 840
        onTriggered: {
            be.launch();
            // в режиме проверки сессия не запускается — возвращаемся к экрану входа
            if (be.mock) mockBack.restart();
        }
    }
    Timer {
        id: mockBack
        interval: 2500
        onTriggered: { shell.leaving = false; be.auth.reset(); shell.resetRequested(); }
    }

    readonly property string focusedName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData
            readonly property bool main: {
                const list = Quickshell.screens;
                const target = list.some(s => s.name === shell.focusedName) ? shell.focusedName : (list[0] ? list[0].name : "");
                return modelData.name === target;
            }

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "delta-greeter"
            WlrLayershell.keyboardFocus: main ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "black"

            LockSurface {
                id: surface
                anchors.fill: parent
                mode: "greeter"
                screen: win.modelData
                auth: be.auth
                showLogin: win.main
                userName: be.displayName
                avatar: be.user.avatar
                canSwitchUser: be.users.length > 1
                onPrevUser: be.nextUser(-1)
                onNextUser: be.nextUser(1)
                onPower: action => PowerActions.run(action)
                loginExtra: Component {
                    GlassBtn {
                        visible: be.sessions.length > 0
                        icon: "monitor"
                        text: be.session ? be.session.name : ""
                        // несколько сессий — перебираем по кругу
                        onClicked: be.nextSession()
                    }
                }
                Connections {
                    target: shell
                    function onExitRequested() { surface.playExit(); }
                    function onResetRequested() { surface.reset(); surface.playEnter(); }
                }
            }

            // заставка запуска: гаснет, и экран входа въезжает своей анимацией
            WelcomeCard {
                anchors.fill: parent
                done: shell.welcome === 1 && !shell.starting
                onReveal: surface.playEnter()
                // после выхода — без заставки: экран входа въезжает сразу
                readonly property bool skip: shell.welcome === 0
                function skipNow() { opacity = 0; surface.playEnter(); }
                onSkipChanged: if (skip) skipNow()
                Component.onCompleted: if (skip) skipNow()
            }
        }
    }

    // DELTA_SHELL_ENTRY=… tools/delta-dev.sh ipc call greeter <функция>
    IpcHandler {
        target: "greeter"
        function submit(text: string): void { if (be.mock) be.auth.submit(text); }
        function user(d: int): void { be.nextUser(d); }
        function session(): void { be.nextSession(); }
        function error(text: string): void { if (be.mock) be.auth.fail(text); }
        function state(): string {
            return JSON.stringify({ mock: be.mock, greetd: be.greetdOk, user: be.user, session: be.session,
                users: be.users.map(u => u.name), sessions: be.sessions.map(s => s.id), config: be.configFile });
        }
    }
}
