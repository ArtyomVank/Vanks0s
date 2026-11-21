pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.common
import qs.common.ui
import qs.docks
import qs.services
import qs.widgets.parts

// Delta Play — игровая панель (Super+G, ShellState.overlay === "play").
// Поверх игры, не сворачивая её: сверху игра и время в ней, ниже четыре
// карточки — показатели (процессор и видеокарта: загрузка, температура,
// память), режим (профиль питания power-profiles-daemon, игровой режим,
// «Не беспокоить»), звук и музыка, снимок экрана. Esc, Super+G или щелчок
// мимо карточек — закрыть.
// Во вложенной сессии и в пробном режиме (GameMode.dryRun) профиль питания
// не меняется — только показывается.
Scope {
    id: root

    function pct(v) { return v >= 0 ? Math.round(v) + "%" : "—"; }
    function deg(v) { return v >= 0 ? Math.round(v) + "°" : ""; }
    function clock(ms) {
        const s = Math.max(0, Math.floor(ms / 1000));
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = s % 60;
        const two = n => (n < 10 ? "0" : "") + n;
        return (h ? h + ":" + two(m) : m) + ":" + two(sec);
    }

    // delta-shell ipc call play <функция> (их зовёт delta-play)
    IpcHandler {
        target: "play"
        function bar(): void { ShellState.toggleOverlay("play"); }
        function manual(on: bool): void { GameMode.setManual(on); }
        function status(): string {
            return JSON.stringify({ active: GameMode.active, manual: GameMode.manual, game: GameMode.game });
        }
    }

    LazyLoader {
        active: ShellState.overlay === "play" && !ShellState.locked

        PanelWindow {
            id: ov
            screen: DockService.focusedScreen()

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "delta-play"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"

            property bool shown: false
            property real now: Date.now()

            function dismiss() {
                if (!shown) return;
                shown = false;
                closeTimer.restart();
            }
            Timer { id: closeTimer; interval: Theme.anim.normal; onTriggered: ShellState.closeOverlay() }
            Timer { interval: 1000; running: ov.shown; repeat: true; onTriggered: ov.now = Date.now() }
            Component.onCompleted: {
                shown = true;
                Sounds.play("pop", 120);
            }

            StatsUser { active: ov.shown; gpu: true }

            // power-profiles-daemon может отсутствовать — тогда без выбора профиля
            property bool profilesAvailable: false
            Process {
                running: true
                command: ["sh", "-c", "busctl --system --no-pager status net.hadess.PowerProfiles >/dev/null 2>&1 || busctl --system --no-pager status org.freedesktop.UPower.PowerProfiles >/dev/null 2>&1"]
                onExited: code => ov.profilesAvailable = code === 0
            }
            function setProfile(p) {
                if (GameMode.dryRun) { console.log("[delta] play: профиль " + p + " (пробный режим)"); return; }
                PowerProfiles.profile = p;
            }

            readonly property PwNode sink: Pipewire.defaultAudioSink
            PwObjectTracker { objects: [ov.sink] }
            readonly property var players: Mpris.players.values
            readonly property MprisPlayer player: players.find(p => p.isPlaying) || players[0] || null

            readonly property bool dnd: Settings.get("notifications.dnd", ShellState.dnd) === true
            function setDnd(on) { Settings.set("notifications.dnd", on); ShellState.dnd = on; }

            // снимок всего экрана игры: панель сначала уходит, чтобы не попасть в кадр
            function shoot() {
                shotTimer.output = ov.screen?.name ?? "";
                dismiss();
                shotTimer.start();
            }
            Timer {
                id: shotTimer
                property string output
                interval: Theme.anim.normal + 120
                onTriggered: Quickshell.execDetached(["sh", "-c",
                    'd="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Screenshots"; mkdir -p "$d"; '
                    + 'f="$d/Delta Play $(date +%Y-%m-%d_%H-%M-%S).png"; '
                    + 'grim ${1:+-o "$1"} "$f" && wl-copy -t image/png < "$f" && delta-shell ipc call fx flash' + Sounds.shell("camera-shutter"),
                    "sh", output])
            }

            // игра чуть темнеет — карточки читаются на любой картинке
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.38)
                opacity: ov.shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.anim.normal; easing.type: Theme.anim.outCurve } }
                MouseArea { anchors.fill: parent; onClicked: ov.dismiss() }
            }

            // карточка панели
            component Panel: Glass {
                id: pn
                property string title
                property string icon
                default property alias body: inner.data
                property int order: 0
                strong: true
                radius: Theme.radius + 6
                implicitWidth: 280
                implicitHeight: inner.implicitHeight + 64
                opacity: ov.shown ? 1 : 0
                // карточки выезжают сверху одна за другой
                transform: Translate { y: ov.shown ? 0 : -18 - pn.order * 6 }
                Behavior on opacity { NumberAnimation { duration: Theme.anim.normal + pn.order * 40 } }
                MouseArea { anchors.fill: parent }       // щелчок по карточке не закрывает
                RowLayout {
                    id: head
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
                    spacing: 8
                    Sym { name: pn.icon; size: 16; color: Theme.accent }
                    Label { text: pn.title; size: "small"; font.weight: Font.Bold; tone: 2; Layout.fillWidth: true }
                }
                ColumnLayout {
                    id: inner
                    anchors { left: parent.left; right: parent.right; top: head.bottom; margins: 18; topMargin: 12 }
                    spacing: 12
                }
            }

            // показатель: подпись, значение, температура, полоса
            component Stat: ColumnLayout {
                id: st
                property string title
                property real value: -1
                property string extra
                property string details
                property var hist: null
                Layout.fillWidth: true
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: st.title; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                    Label { visible: st.extra.length > 0; text: st.extra; size: "small"; color: Theme.accents[4] }
                    Label { text: root.pct(st.value); size: "title"; num: true; font.family: Theme.fontDisplay }
                }
                Label { visible: st.details.length > 0; text: st.details; size: "caption"; tone: 3; Layout.fillWidth: true; elide: Text.ElideRight }
                Wave {
                    visible: st.hist !== null
                    Layout.fillWidth: true
                    implicitHeight: 28
                    values: st.hist || []
                    step: 8
                    lineWidth: 1.8
                }
            }

            // строка-переключатель
            component Switch: RowLayout {
                id: sw
                property string icon
                property string title
                property string text
                property bool checked
                signal toggled(bool v)
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    implicitWidth: 30; implicitHeight: 30; radius: 10
                    color: sw.checked ? Theme.accent : Theme.soft2
                    Sym { anchors.centerIn: parent; name: sw.icon; size: 16; color: sw.checked ? Theme.onAccent : Theme.fg2 }
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    Label { text: sw.title; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                    Label { visible: sw.text.length > 0; text: sw.text; size: "caption"; tone: 3; Layout.fillWidth: true; elide: Text.ElideRight }
                }
                Toggle { checked: sw.checked; onToggled: v => sw.toggled(v) }
            }

            ColumnLayout {
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: Math.max(48, parent.height * 0.08) }
                spacing: 18

                // ---------- шапка: игра и время в ней ----------
                Glass {
                    strong: true
                    Layout.alignment: Qt.AlignHCenter
                    radius: height / 2
                    implicitHeight: 56
                    implicitWidth: headRow.implicitWidth + 36
                    opacity: ov.shown ? 1 : 0
                    scale: ov.shown ? 1 : 0.94
                    Behavior on opacity { NumberAnimation { duration: Theme.anim.normal } }
                    Behavior on scale { NumberAnimation { duration: Theme.anim.slow; easing.type: Theme.anim.outCurve } }
                    MouseArea { anchors.fill: parent }
                    RowLayout {
                        id: headRow
                        anchors.centerIn: parent
                        spacing: 12
                        Rectangle {
                            implicitWidth: 36; implicitHeight: 36; radius: 18
                            color: GameMode.active ? Theme.accent : Theme.soft2
                            Sym { anchors.centerIn: parent; name: "gamepad"; size: 20; color: GameMode.active ? Theme.onAccent : Theme.fg }
                        }
                        ColumnLayout {
                            spacing: 0
                            Label {
                                text: GameMode.game ? (GameMode.game.title || GameMode.game.class) : I18n.tr("Delta Play")
                                font.weight: Font.Bold
                                Layout.maximumWidth: 420
                                elide: Text.ElideRight
                            }
                            Label {
                                text: GameMode.active && GameMode.since > 0
                                    ? I18n.tr("Игровой режим") + " · " + root.clock(ov.now - GameMode.since)
                                    : I18n.tr("Игра не запущена")
                                size: "caption"; tone: 3
                            }
                        }
                        Item { implicitWidth: 18 }
                        Label { text: Qt.formatTime(new Date(ov.now), "hh:mm"); size: "title"; num: true; font.family: Theme.fontDisplay }
                    }
                }

                // ---------- карточки ----------
                RowLayout {
                    id: cards
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 14

                    Panel {
                        order: 0
                        title: I18n.tr("Показатели")
                        icon: "cpu"
                        Layout.alignment: Qt.AlignTop
                        Stat {
                            title: I18n.tr("Процессор")
                            value: SystemStats.cpu
                            extra: root.deg(SystemStats.cpuTemp)
                            hist: SystemStats.cpuHist
                        }
                        Stat {
                            title: I18n.tr("Видеокарта")
                            value: SystemStats.gpu
                            extra: root.deg(SystemStats.gpuTemp)
                            details: SystemStats.vramTotal > 0 ? I18n.tr("память ") + SystemStats.pair(SystemStats.vramUsed, SystemStats.vramTotal) : SystemStats.gpuName
                            hist: SystemStats.hasGpuLoad ? SystemStats.gpuHist : null
                        }
                        Stat {
                            title: I18n.tr("Память")
                            value: SystemStats.ram
                            details: SystemStats.ramTotal > 0 ? SystemStats.pair(SystemStats.ramUsed, SystemStats.ramTotal) : ""
                        }
                    }

                    Panel {
                        order: 1
                        title: I18n.tr("Режим")
                        icon: "rocket"
                        implicitWidth: 310
                        Layout.alignment: Qt.AlignTop
                        Label { visible: ov.profilesAvailable; text: I18n.tr("Профиль питания"); size: "caption"; tone: 3 }
                        Chips {
                            visible: ov.profilesAvailable
                            Layout.fillWidth: true
                            model: [
                                { value: PowerProfile.PowerSaver, label: I18n.tr("Эконом") },
                                { value: PowerProfile.Balanced, label: I18n.tr("Баланс") },
                                { value: PowerProfile.Performance, label: I18n.tr("Максимум") }
                            ].filter(x => x.value !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile)
                            current: PowerProfiles.profile
                            onPicked: v => ov.setProfile(v)
                        }
                        Switch {
                            icon: "gamepad"
                            title: I18n.tr("Игровой режим")
                            text: GameMode.manual ? I18n.tr("включён вручную")
                                : GameMode.auto ? I18n.tr("сам, по окну игры") : I18n.tr("выключен")
                            checked: GameMode.active
                            onToggled: v => GameMode.setManual(v)
                        }
                        Switch {
                            icon: "bell-off"
                            title: I18n.tr("Не беспокоить")
                            text: I18n.tr("уведомления молчат")
                            checked: ov.dnd
                            onToggled: v => ov.setDnd(v)
                        }
                    }

                    Panel {
                        order: 2
                        title: I18n.tr("Звук и музыка")
                        icon: "headphones"
                        Layout.alignment: Qt.AlignTop
                        Slider {
                            Layout.fillWidth: true
                            icon: ov.sink?.audio?.muted ? "volume-mute" : "volume"
                            value: ov.sink?.audio?.volume ?? 0
                            enabled: ov.sink?.audio !== undefined && ov.sink?.audio !== null
                            onMoved: v => { if (ov.sink?.audio) ov.sink.audio.volume = v; }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            ClippingRectangle {
                                implicitWidth: 44; implicitHeight: 44; radius: 12
                                color: Theme.soft2
                                Image {
                                    anchors.fill: parent
                                    source: ov.player?.trackArtUrl ?? ""
                                    fillMode: Image.PreserveAspectCrop
                                    sourceSize: Qt.size(88, 88)
                                    visible: status === Image.Ready
                                }
                                Sym { anchors.centerIn: parent; visible: !(ov.player?.trackArtUrl); name: "music"; size: 18; color: Theme.fg2 }
                            }
                            ColumnLayout {
                                spacing: 0
                                Layout.fillWidth: true
                                Label { Layout.fillWidth: true; elide: Text.ElideRight; font.weight: Font.Bold; size: "small"
                                        text: ov.player ? (ov.player.trackTitle || ov.player.identity || I18n.tr("Без названия")) : I18n.tr("Ничего не играет") }
                                Label { Layout.fillWidth: true; elide: Text.ElideRight; size: "caption"; tone: 3
                                        text: ov.player ? (ov.player.trackArtist || ov.player.identity || "") : I18n.tr("Включите музыку") }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Repeater {
                                model: ["prev", "play", "next"]
                                delegate: Item {
                                    id: mc
                                    required property string modelData
                                    readonly property bool main: modelData === "play"
                                    Layout.fillWidth: true
                                    implicitHeight: 40
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: mc.main ? 40 : 32; height: width; radius: width / 2
                                        color: mc.main ? Theme.accent : mcHov.hovered ? Theme.soft2 : "transparent"
                                        opacity: ov.player ? 1 : 0.4
                                        scale: mcTap.pressed ? 0.9 : 1
                                        Behavior on scale { NumberAnimation { duration: Theme.anim.fast } }
                                        Sym {
                                            anchors.centerIn: parent
                                            name: mc.main ? (ov.player?.isPlaying ? "pause" : "play") : mc.modelData
                                            size: mc.main ? 18 : 16
                                            color: mc.main ? Theme.onAccent : Theme.fg
                                        }
                                        HoverHandler { id: mcHov; cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            id: mcTap
                                            enabled: ov.player !== null
                                            onTapped: mc.main ? ov.player.togglePlaying() : mc.modelData === "prev" ? ov.player.previous() : ov.player.next()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Panel {
                        order: 3
                        title: I18n.tr("Снимок")
                        icon: "screenshot"
                        implicitWidth: 200
                        Layout.alignment: Qt.AlignTop
                        Label {
                            Layout.fillWidth: true
                            text: I18n.tr("Весь экран игры — в «Изображения → Screenshots» и в буфер обмена")
                            size: "caption"; tone: 3
                            wrapMode: Text.WordWrap
                        }
                        Btn {
                            Layout.fillWidth: true
                            kind: "accent"
                            icon: "screenshot"
                            text: I18n.tr("Снять экран")
                            onClicked: ov.shoot()
                        }
                        Btn {
                            Layout.fillWidth: true
                            icon: "settings"
                            text: I18n.tr("Настройки игр")
                            onClicked: { ov.dismiss(); ShellState.openSettings("play", null); }
                        }
                    }
                }

                // ---------- оверлей в игре: FPS и показатели (play/PlayHud) ----------
                Panel {
                    order: 4
                    title: I18n.tr("Поверх игры")
                    icon: "gauge"
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: cards.implicitWidth
                    HudOptions {
                        Layout.fillWidth: true
                        onOpenSettings: section => { ov.dismiss(); ShellState.openSettings(section, null); }
                    }
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: I18n.tr("Super+G или Esc — вернуться в игру")
                    size: "small"
                    tone: 3
                    opacity: ov.shown ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.anim.slow } }
                }
            }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: e => {
                    if (e.key === Qt.Key_Escape) { ov.dismiss(); e.accepted = true; }
                }
            }
        }
    }
}
