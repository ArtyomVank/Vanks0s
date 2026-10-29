pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pam
import qs.common

// Блокировка экрана Delta — один экземпляр на оболочку.
//
//   lock()            заблокировать (Super+L, меню питания, простой, перед сном)
//   ShellState.locked / ShellState.unlocking — для остальных модулей
//
// Экран блокировки (LockSurface.qml) грузится только в момент блокировки.
// Пароль проверяет PAM (конфиг «login», как у входа в систему).
//
// Плавный переход к рабочему столу: на время анимации включаем в Hyprland
// misc.session_lock_xray — композитор рисует рабочий стол под прозрачными
// местами экрана блокировки. Включаем только на время перехода: пока экран
// заблокирован, он непрозрачный, и xray выключен.
Scope {
    id: root

    readonly property bool locked: persist.locked
    readonly property bool secure: sessionLock.secure
    property bool unlocking: false

    // в Hyprland можно показывать рабочий стол сквозь блокировку во время переходов
    readonly property bool canXray: Settings.get("lock.smoothTransitions", true)
        && (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "").length > 0
    property bool fromDesktop: false
    readonly property bool dryRun: PowerActions.dryRun

    // сигналы для поверхностей на всех мониторах
    signal exitRequested()

    function lock(quick) {
        if (persist.locked) return;
        console.info("[delta] блокировка");
        Account.refresh();
        Keyboard.refresh();
        ShellState.closeMenu();
        ShellState.closeOverlay();
        ShellState.lockEditing = false;
        auth.reset();
        // перед сном — сразу, без перехода: важно успеть закрыть экран
        fromDesktop = canXray && quick !== true;
        if (fromDesktop) { setXray(true); xrayOff.restart(); }
        // поверхности создаются здесь же — fromDesktop уже должен быть известен
        persist.locked = true;
        ShellState.desktopShown = false;
        lockedHint(true);
        Sounds.play("service-logout");
    }

    function startUnlock() {
        if (!persist.locked || unlocking) return;
        unlocking = true;
        ShellState.unlocking = true;
        if (canXray) setXray(true);
        exitRequested();
        finishTimer.restart();
        revealTimer.restart();
    }

    function finishUnlock() {
        persist.locked = false;
        unlocking = false;
        Sounds.play("unlock");
        ShellState.unlocking = false;
        ShellState.desktopShown = true;
        lockedHint(false);
        if (canXray) xrayOff.restart();
        console.info("[delta] разблокировано");
    }

    // ---------- только для отладки во вложенной сессии (dev-lock.qml) ----------
    // Ввод в окно вложенной сессии не подать, поэтому состояния включаются отсюда.
    // В настоящей сессии эти функции ничего не делают.
    signal devConfirmRequested(string action)
    function devAllowed() {
        if (!dryRun) console.warn("[delta] отладочные функции блокировки работают только во вложенной сессии");
        return dryRun;
    }
    function devUnlock() { if (devAllowed()) startUnlock(); }
    function devSubmit(text) { if (devAllowed()) auth.submit(text); }
    function devError(text) {
        if (!devAllowed()) return;
        auth.message = text; auth.isError = true; auth.failed();
    }
    function devConfirm(action) {
        if (!devAllowed()) return;
        devConfirmRequested(action);
        if (overlayLoader.item) overlayLoader.item.confirm = action;
    }

    // концепт: 820 мс, кольцо доигрывает чуть дольше уже на рабочем столе
    Timer { id: finishTimer; interval: 840; onTriggered: root.finishUnlock() }
    // фон блокировки начинает таять на 420 мс — рабочий стол проступает чуть раньше
    Timer { id: revealTimer; interval: 360; onTriggered: if (root.unlocking) ShellState.desktopShown = true }
    Timer { id: xrayOff; interval: 900; onTriggered: if (!root.unlocking) root.setXray(false) }

    function setXray(on) {
        Quickshell.execDetached(["hyprctl", "eval", "hl.config({ misc = { session_lock_xray = " + (on ? "true" : "false") + " } })"]);
    }

    // logind LockedHint: по нему другие программы (и мы после падения) знают, что сессия заблокирована
    function lockedHint(on) {
        if (dryRun) return;
        Quickshell.execDetached(["gdbus", "call", "--system", "--dest", "org.freedesktop.login1",
            "--object-path", "/org/freedesktop/login1/session/auto",
            "--method", "org.freedesktop.login1.Session.SetLockedHint", on ? "true" : "false"]);
    }

    // ---------- проверка пароля ----------
    QtObject {
        id: auth
        property bool busy: false
        property string message: ""
        property bool isError: false
        property string prompt: ""         // второй вопрос PAM (код, токен)
        property bool echo: false
        property string pending: ""
        property string pamError: ""
        signal failed()

        function reset() {
            if (pam.active) pam.abort();
            busy = false; message = ""; isError = false; prompt = ""; echo = false; pending = ""; pamError = "";
        }

        function submit(text) {
            if (root.unlocking || !persist.locked) return;
            busy = true;
            message = "";
            isError = false;
            // PAM ждёт ответ на второй вопрос
            if (pam.active && pam.responseRequired) { pam.respond(text); return; }
            pending = text;
            pamError = "";
            if (!pam.start()) {
                busy = false;
                message = "Не удалось начать проверку пароля";
                isError = true;
                failed();
            }
        }
    }

    PamContext {
        id: pam
        onPamMessage: {
            if (responseRequired) {
                if (auth.pending.length) {
                    respond(auth.pending);
                    auth.pending = "";
                } else {
                    // модуль спрашивает что-то ещё — показываем его вопрос вместо «Пароль»
                    auth.busy = false;
                    auth.prompt = message.replace(/:\s*$/, "");
                    auth.echo = responseVisible;
                }
            } else if (message.length) {
                // например, faillock: «учётная запись заблокирована на N минут»
                auth.message = message;
                auth.isError = messageIsError;
                if (messageIsError) auth.pamError = message;
            }
        }
        onCompleted: result => {
            auth.busy = false;
            auth.pending = "";
            auth.prompt = "";
            auth.echo = false;
            if (result === PamResult.Success) {
                auth.message = "";
                root.startUnlock();
                return;
            }
            auth.isError = true;
            auth.message = result === PamResult.MaxTries ? "Слишком много попыток — подождите немного"
                : auth.pamError.length ? auth.pamError
                : result === PamResult.Error ? "Ошибка проверки пароля" : "Неверный пароль";
            auth.failed();
        }
        onError: e => console.warn("[delta] PAM: " + PamError.toString(e))
    }

    // ---------- сама блокировка ----------
    readonly property string focusedName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""

    // Состояние блокировки переживает перезагрузку оболочки (qs перечитывает QML при
    // обновлении файлов): иначе новый экземпляр начал бы с locked: false и снял бы блокировку.
    PersistentProperties {
        id: persist
        reloadableId: "delta-lock-state"
        property bool locked: false
    }
    Binding { target: ShellState; property: "locked"; value: persist.locked }

    WlSessionLock {
        id: sessionLock
        reloadableId: "delta-session-lock"
        locked: persist.locked

        onSecureChanged: if (secure) sleepWatch.release()

        WlSessionLockSurface {
            id: surf
            // Под LockSurface — сплошной чёрный, кроме переходов: с xray композитор
            // рисует рабочий стол под прозрачными местами, и чёрная подложка
            // превратила бы наслаивание в «затемнение и рывок».
            color: root.canXray && (root.unlocking || root.fromDesktop) ? "transparent" : "black"

            Loader {
                id: content
                anchors.fill: parent
                asynchronous: false
                Component.onCompleted: setSource(Qt.resolvedUrl("LockSurface.qml"), {
                    mode: "lock",
                    auth: auth,
                    fromDesktop: root.fromDesktop
                })
                onLoaded: {
                    const it = item;
                    it.screen = Qt.binding(() => surf.screen);
                    it.showLogin = Qt.binding(() => {
                        const list = Quickshell.screens;
                        const name = root.focusedName;
                        const target = list.some(s => s.name === name) ? name : (list[0] ? list[0].name : "");
                        return !surf.screen || surf.screen.name === target;
                    });
                    it.userName = Qt.binding(() => Account.name);
                    it.avatar = Qt.binding(() => Account.avatar);
                    it.avatarRevision = Qt.binding(() => Account.revision);
                    it.toDesktop = Qt.binding(() => root.canXray);
                    it.power.connect(a => PowerActions.run(a));
                    root.exitRequested.connect(it.playExit);
                    root.devConfirmRequested.connect(a => it.confirm = a);
                }
            }
        }
    }

    // ---------- когда блокировать ----------
    Connections {
        target: PowerActions
        function onLockRequested() { root.lock(); }
    }

    Idle {
        locked: root.locked
        onLockRequested: root.lock()
    }

    SleepWatch {
        id: sleepWatch
        enabled: Settings.get("power.lockBeforeSleep", true)
        dryRun: root.dryRun
        onSleeping: {
            if (root.locked && root.secure) { release(); return; }
            root.lock(true);
            // композитор не подтвердил за 2 с — всё равно отпускаем сон
            releaseTimer.restart();
        }
        onResumed: PowerActions.dpms(true)
        onLockSignal: root.lock()
    }
    Timer { id: releaseTimer; interval: 2000; onTriggered: sleepWatch.release() }

    // «Входить без пароля»: автовход и сразу экран блокировки. Метка в XDG_RUNTIME_DIR
    // живёт до выхода из сессии, поэтому перезапуск оболочки не блокирует экран ещё раз.
    // Там же — восстановление после падения оболочки: logind помнит LockedHint.
    Process {
        id: startCheck
        command: ["sh", "-c",
            "m=\"${XDG_RUNTIME_DIR:-/tmp}/delta-lock-started\"; first=0; [ -e \"$m\" ] || { : > \"$m\"; first=1; }; " +
            "echo $first; busctl --system get-property org.freedesktop.login1 /org/freedesktop/login1/session/auto " +
            "org.freedesktop.login1.Session LockedHint 2>/dev/null || echo none"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                const first = l[0] === "1";
                const wasLocked = !root.dryRun && (l[1] || "").trim() === "b true";
                if (wasLocked) { console.info("[delta] сессия была заблокирована — восстанавливаем блокировку"); root.lock(true); }
                else if (first && Settings.get("lock.onStart", false)) root.lock(true);
            }
        }
    }
    Connections {
        target: Settings
        function onReadyChanged() { if (Settings.ready && !startCheck.running) startCheck.running = true; }
    }
    Component.onCompleted: if (Settings.ready) startCheck.running = true

    // ---------- обои и тема для экрана входа ----------
    // Изменились оформление, обои или часы — через 5 с копируем их для greeter'а.
    readonly property string greeterLook: JSON.stringify([Settings.get("appearance", {}), Settings.get("wallpaper", {}),
        Settings.get("clock", {}), Settings.get("lock", {}), Settings.get("greeter", {}),
        Settings.get("widgets.lock", []), Account.avatar, Account.revision])
    onGreeterLookChanged: if (Settings.ready) syncTimer.restart()
    Timer {
        id: syncTimer
        interval: 5000
        onTriggered: Quickshell.execDetached(["sh", "-c",
            "command -v delta-greeter-sync >/dev/null && exec delta-greeter-sync " + (Settings.get("greeter.sync", true) ? "-q" : "--remove -q")])
    }

    // ---------- редактор виджетов экрана блокировки ----------
    readonly property var focusedScreen: {
        const list = Quickshell.screens;
        return list.find(s => s.name === root.focusedName) || list[0] || null;
    }

    LazyLoader {
        active: ShellState.lockEditing && !root.locked
        PanelWindow {
            screen: root.focusedScreen
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "delta-lock-edit"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "black"
            Loader {
                anchors.fill: parent
                Component.onCompleted: setSource(Qt.resolvedUrl("LockSurface.qml"), { mode: "edit" })
                onLoaded: {
                    item.screen = Qt.binding(() => root.focusedScreen);
                    item.userName = Qt.binding(() => Account.name);
                    item.editDone.connect(() => ShellState.lockEditing = false);
                }
            }
        }
    }

    // ---------- меню питания по центру (Super+Escape) ----------
    LazyLoader {
        id: overlayLoader
        active: ShellState.overlay === "power" && !root.locked
        PowerOverlay {
            screen: root.focusedScreen
            onDismissed: ShellState.closeOverlay()
        }
    }

    // ---------- IPC: delta-shell ipc call lock <функция> ----------
    IpcHandler {
        target: "lock"
        function lock(): void { root.lock(); }
        function isLocked(): bool { return root.locked; }
        // только во вложенной сессии (пробный режим): ввод пароля туда не подать
        function unlock(): void { root.devUnlock(); }
        // раздел «Экран блокировки» в «Настройках» — отдельный процесс, поэтому через IPC
        function edit(): void {
            ShellState.widgetEditing = false;
            ShellState.lockEditing = !ShellState.lockEditing;
        }
        function power(): void { ShellState.toggleOverlay("power"); }
    }
}
