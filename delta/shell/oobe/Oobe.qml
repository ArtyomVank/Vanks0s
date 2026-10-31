pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Effects
import qs.common
import qs.common.ui
import "../wallpaper/media.js" as Media

// Первая настройка (OOBE). На весь экран и непрозрачная: при первом входе на
// чёрном фоне капли стекаются с краёв к центру и разливаются на весь экран,
// в нём — шаги: язык, оформление, обои, доки, звуки и движение. Систему не
// видно до конца: доки и виджеты спрятаны (ShellState.desktopShown). В конце
// кнопку «Начать» нужно зажать; настройка исчезает от центра к краям, открывая
// обои, затем проступают виджеты и доки, и открывается помощник.
//
// Показывается сама, если в settings.json ещё нет oobe.done и пользователь
// ничего не настраивал (у тех, кто обновился, тихо ставится oobe.done).
// В живой сессии ISO и во вложенной (delta-dev) — только с DELTA_OOBE=1.
// Повторно: «Настройки» → «О системе» → «Начальная настройка», или
//     delta-shell ipc call oobe start
Scope {
    id: root

    property bool active: false
    property int page: 0
    property real gather: 0       // 0 — капли у краёв, 1 — карточка собрана
    property real hole: 0         // 0 — на месте, 1 — растворилась к краям
    property bool leaving: false
    property real time: 0

    readonly property int pages: 7
    // подписи шагов — у индикатора внизу
    readonly property var stepNames: ["Язык", "Оформление", "Стиль", "Обои", "Доки", "Звуки и движение", "Готово"]

    function start() {
        page = 0;
        hole = 0;
        gather = 0;
        leaving = false;
        startPage.button.reset();
        ShellState.desktopShown = false;
        active = true;
        gatherAnim.restart();
        Sounds.play("oobe-hello", 0);
    }

    function go(to) {
        to = Math.max(0, Math.min(pages - 1, to));
        if (to === page || leaving) return;
        Sounds.play(to > page ? "oobe-step" + Math.min(6, to) : "oobe-back", 60);
        page = to;
    }

    function finish(at) {
        if (leaving) return;
        leaving = true;
        Sounds.play("oobe-done", 0);
        confetti.burst(at.x, at.y);
        Settings.set("oobe.done", true);
        Settings.flush();
        localeProc.running = true;
        exitAnim.restart();
    }

    // --- показывать ли при запуске ---
    property bool checked: false
    function check() {
        if (checked || !Settings.ready) return;
        checked = true;
        if (Settings.get("oobe.done", false) === true) return;
        // кто уже что-то настраивал — обновился с прошлой версии
        const touched = Object.keys(Settings.user || {}).filter(k => ["version", "monitors", "display", "oobe"].indexOf(k) < 0);
        gate.forced = Quickshell.env("DELTA_OOBE") === "1";
        if (touched.length > 0 && !gate.forced) {
            Settings.set("oobe.done", true);
            return;
        }
        // скорее всего покажем: прячем доки и виджеты сразу, пока идёт проверка
        ShellState.desktopShown = false;
        gate.running = true;
    }
    Component.onCompleted: check()
    Connections {
        target: Settings
        function onReadyChanged() { root.check(); }
    }
    Process {
        id: gate
        property bool forced: false
        // 0 — живая сессия ISO или вложенная, без DELTA_OOBE=1 не показываем
        command: ["sh", "-c", "{ [ -d /run/archiso ] || [ -n \"${DELTA_NESTED:-}\" ]; } && [ \"${DELTA_OOBE:-}\" != 1 ]"]
        onExited: code => { if (code !== 0) root.begin(); else ShellState.desktopShown = true; }
    }

    // Если при входе сначала экран блокировки (lock.onStart, DELTA_LOCK_ON_START),
    // помощник ждёт, пока его снимут, — иначе отыграл бы под ним. Блокировка
    // так и не пришла за 5 с (оболочку перезапустили) — начинаем без неё.
    property bool afterUnlock: false
    property bool lockSeen: false
    readonly property bool lockExpected: Quickshell.env("DELTA_LOCK_ON_START") === "1" || Settings.get("lock.onStart", false) === true
    function begin() {
        if (ShellState.locked || (lockExpected && !lockSeen)) {
            afterUnlock = true;
            lockWait.restart();
            return;
        }
        start();
    }
    Connections {
        target: ShellState
        function onLockedChanged() {
            if (ShellState.locked) { root.lockSeen = true; lockWait.stop(); return; }
            if (root.afterUnlock) { root.afterUnlock = false; root.start(); }
        }
    }
    Timer {
        id: lockWait
        interval: 5000
        onTriggered: if (root.afterUnlock && !ShellState.locked) { root.afterUnlock = false; root.start(); }
    }

    // язык для программ (LANG): со следующего входа, если такая локаль есть
    Process {
        id: localeProc
        command: ["sh", "-c",
            "l=$1; c=${XDG_CONFIG_HOME:-$HOME/.config}; " +
            "locale -a 2>/dev/null | grep -qix \"$l.utf8\" || exit 0; " +
            "mkdir -p \"$c\" && printf 'LANG=%s.UTF-8\\n' \"$l\" > \"$c/locale.conf\"",
            "sh", I18n.locale]
    }

    IpcHandler {
        target: "oobe"
        function start(): void { root.start(); }
        // для записи демо и проверок: шаг вперёд / к шагу n / как будто «Начать» дожали
        function next(): void { root.go(root.page + 1); }
        function page(n: int): void { root.go(n); }
        function finish(): void { if (root.active) root.finish(Qt.point(win.width / 2, win.height * 0.62)); }
        // зажать и отпустить «Начать», как пробелом (последний шаг)
        function press(): void { if (root.active && root.page === root.pages - 1) startPage.button.keyDown(); }
        function release(): void { if (root.active) startPage.button.keyUp(); }
    }

    NumberAnimation { id: gatherAnim; target: root; property: "gather"; from: 0; to: 1; duration: 2300; easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: exitAnim
        PauseAnimation { duration: 650 * Theme.anim.k }
        NumberAnimation { target: root; property: "hole"; from: 0; to: 1; duration: 1500; easing.type: Easing.InOutCubic }
        ScriptAction {
            script: {
                root.active = false;
                root.leaving = false;
                // открылись обои — следом проступают виджеты и доки
                ShellState.desktopShown = true;
                Quickshell.execDetached(["sh", "-c", "sleep 1.2; exec delta-welcome --first-run"]);
            }
        }
    }
    FrameAnimation {
        running: root.active
        onTriggered: root.time += frameTime
    }

    PanelWindow {
        id: win

        visible: root.active
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) || Quickshell.screens[0] || null
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "delta-oobe"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"

        // содержимое — по центру, а стекло разливается на весь экран
        readonly property real cw: Math.min(960, width - 96)
        readonly property real ch: Math.min(720, height - 80)
        readonly property real cx: (width - cw) / 2
        readonly property real cy: (height - ch) / 2

        Item {
            id: stage
            anchors.fill: parent
            focus: true

            layer.enabled: root.hole > 0
            layer.effect: ShaderEffect {
                property variant source
                property real hole: root.hole
                property vector2d res: Qt.vector2d(stage.width, stage.height)
                property color ring: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.9)
                fragmentShader: Qt.resolvedUrl("shaders/dissolve.frag.qsb")
            }


            ShaderEffect {
                anchors.fill: parent
                property real progress: root.gather
                property real time: root.time
                // к концу сборки углы распрямляются — стекло во весь экран
                property real radius: 64 * (1 - root.gather)
                property real dimAmount: 1
                property vector2d res: Qt.vector2d(width, height)
                property vector4d card: Qt.vector4d(0, 0, width, height)
                property color glass: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 1)
                property color accent: Theme.accent
                property color dim: Qt.rgba(0.01, 0.01, 0.02, 1)
                fragmentShader: Qt.resolvedUrl("shaders/gather.frag.qsb")
            }

            // --- выбранные обои за стеклом: размыты и притушены, меняются на лету ---
            Item {
                id: backdrop
                anchors.fill: parent
                readonly property string path: Settings.get("wallpaper.path", "")
                readonly property string still: Media.isVideo(path) ? Settings.get("wallpaper.poster", "") : path
                opacity: Math.max(0, (root.gather - 0.6) / 0.4)
                visible: still.length > 0
                Image {
                    id: wallImg
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 960
                    source: backdrop.still.length ? Media.fileUrl(backdrop.still) : ""
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: wallImg
                    blurEnabled: true
                    blur: 1
                    blurMax: 64
                    saturation: 0.15
                    opacity: wallImg.status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 600 } }
                }
                Rectangle {
                    anchors.fill: parent
                    color: Theme.base
                    opacity: Theme.light ? 0.62 : 0.7
                    Behavior on color { ColorAnimation { duration: 400 } }
                }
            }

            // --- карточка ---
            Item {
                id: card
                x: win.cx; y: win.cy
                width: win.cw; height: win.ch
                opacity: Math.max(0, Math.min(1, (root.gather - 0.78) / 0.2))
                scale: 0.96 + 0.04 * opacity
                enabled: opacity > 0.9 && !root.leaving

                // «пропустить» — сразу к последнему шагу
                Btn {
                    anchors { top: parent.top; right: parent.right; margins: 20 }
                    kind: "ghost"
                    text: I18n.tr("Пропустить")
                    visible: root.page < root.pages - 1
                    onClicked: root.go(root.pages - 1)
                }

                Item {
                    id: deck
                    anchors { left: parent.left; right: parent.right; top: parent.top; bottom: nav.top }
                    clip: true

                    Slot { index: 0; current: root.page; PageLang { id: langPage; anchors.fill: parent; shown: root.active && root.page === 0 && root.gather > 0.7 } }
                    Slot { index: 1; current: root.page; PageLook { anchors.fill: parent; shown: root.page === 1 } }
                    Slot { index: 2; current: root.page; PageStyle { anchors.fill: parent; shown: root.page === 2 } }
                    Slot { index: 3; current: root.page; PageWall { anchors.fill: parent; shown: root.page === 3 } }
                    Slot { index: 4; current: root.page; PageDock { anchors.fill: parent; shown: root.page === 4 } }
                    Slot { index: 5; current: root.page; PageFeel { anchors.fill: parent; shown: root.page === 5 } }
                    Slot { index: 6; current: root.page; PageStart { id: startPage; anchors.fill: parent; shown: root.page === 6; onStarted: at => root.finish(at) } }
                }

                // --- навигация: круглая «назад», полоски шагов, «Далее» ---
                Item {
                    id: nav
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 28 }
                    height: 48

                    Btn {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        icon: "chevron-left"
                        kind: "ghost"
                        implicitHeight: 44
                        opacity: root.page > 0 ? 1 : 0
                        enabled: root.page > 0
                        Behavior on opacity { NumberAnimation { duration: Theme.anim.fast } }
                        onClicked: root.go(root.page - 1)
                    }

                    // полоска на каждый шаг; пройденные и текущий — цветом, щелчок — к шагу
                    Column {
                        anchors.centerIn: parent
                        spacing: 9
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 6
                            Repeater {
                                model: root.pages
                                delegate: Item {
                                    id: seg
                                    required property int index
                                    readonly property bool on: index === root.page
                                    width: on ? 44 : 26
                                    height: 14
                                    Behavior on width { NumberAnimation { duration: 460 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 1.8 } }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width
                                        height: segTap.containsMouse ? 6 : 4
                                        radius: height / 2
                                        color: seg.index <= root.page ? Theme.accent : Theme.soft2
                                        opacity: seg.index < root.page ? 0.55 : 1
                                        Behavior on color { ColorAnimation { duration: Theme.anim.normal } }
                                        Behavior on height { NumberAnimation { duration: Theme.anim.fast } }
                                    }
                                    MouseArea {
                                        id: segTap
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.go(seg.index)
                                    }
                                }
                            }
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: I18n.tr(root.stepNames[root.page]) + "  ·  " + (root.page + 1) + " / " + root.pages
                            size: "caption"
                            tone: 3
                        }
                    }

                    Btn {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        text: I18n.tr("Далее")
                        icon: "arrow-right"
                        kind: "accent"
                        implicitHeight: 44
                        opacity: root.page < root.pages - 1 ? 1 : 0
                        enabled: root.page < root.pages - 1
                        Behavior on opacity { NumberAnimation { duration: Theme.anim.fast } }
                        onClicked: root.go(root.page + 1)
                    }
                }
            }

            Confetti { id: confetti; anchors.fill: parent }

            Keys.onPressed: event => {
                if (event.isAutoRepeat) { event.accepted = true; return; }
                if (root.page === root.pages - 1 && (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) startPage.button.keyDown();
                else if (event.key === Qt.Key_Right || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.go(root.page + 1);
                else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backspace) root.go(root.page - 1);
                else if (event.key >= Qt.Key_1 && event.key < Qt.Key_1 + root.pages) root.go(event.key - Qt.Key_1);
                event.accepted = true;
            }
            Keys.onReleased: event => {
                if (event.isAutoRepeat) return;
                if (root.page === root.pages - 1 && (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) startPage.button.keyUp();
            }
        }
    }

    // на остальных мониторах — просто темнота, тает вместе с настройкой
    Variants {
        model: root.active ? Quickshell.screens.filter(sc => sc !== win.screen) : []
        delegate: PanelWindow {
            required property ShellScreen modelData
            screen: modelData
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "delta-oobe-dim"
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: Qt.rgba(0.01, 0.01, 0.02, 1 - root.hole)
        }
    }

    // место шага в колоде: соседние отъезжают и тают, текущий въезжает с пружиной
    // (у встроенного компонента своя область видимости — текущий шаг передаём)
    component Slot: Item {
        property int index
        property int current
        readonly property real off: index - current
        width: parent ? parent.width : 0
        height: parent ? parent.height : 0
        x: off * width * 0.42
        opacity: Math.max(0, 1 - Math.abs(off) * 1.6)
        scale: 1 - Math.min(1, Math.abs(off)) * 0.08
        visible: opacity > 0.01
        Behavior on x { NumberAnimation { duration: 640 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
        Behavior on opacity { NumberAnimation { duration: 380 * Theme.anim.k; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 520 * Theme.anim.k; easing.type: Easing.OutCubic } }
    }
}
