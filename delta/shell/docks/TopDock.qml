pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.common
import qs.common.ui
import qs.docks.parts

// Верхний (статус-) док одного монитора: сетка модулей или пилюля музыки.
//
// Окно — полоса вдоль края на всю длину экрана, без резервирования места
// (его держит отдельный Reserve), поэтому координаты окна совпадают с
// координатами экрана. Ввод принимает только тело дока и полоска у края.
PanelWindow {
    id: win

    readonly property var cfg: Settings.get("docks.top", ({}))
    readonly property string edge: ["top", "bottom", "left", "right"].indexOf(cfg.edge) !== -1 ? cfg.edge : "top"
    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property string length: ["full", "tiles", "compact"].indexOf(cfg.length) !== -1 ? cfg.length : "full"
    // автоскрытие: true — всегда, "smart" — только когда окно на видимом столе
    // этого монитора заходит на место дока (не задевает — док остаётся)
    readonly property bool smart: cfg.autohide === "smart"
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property bool hasWindows: smart && DockService.covered(screen?.name ?? "", openRect)
    readonly property bool autohide: cfg.autohide === true || (smart && hasWindows)
    readonly property bool pill: DockService.mediaPill && !ShellState.dockEditing
    // «остров»: короткое сообщение вместо модулей — без звука / звук включён
    // (колокольчик) или событие системы (значок, заголовок, подпись)
    readonly property bool noticing: DockService.notice !== null && !ShellState.dockEditing && !menuHere
    readonly property bool muteNotice: noticing && DockService.notice.kind === "mute"

    readonly property real margin: 10
    readonly property real barThick: length === "compact" ? 42 : 48
    readonly property real thick: noticing || pill ? 44 : barThick
    readonly property real along: noticing ? (vertical ? 150 : (muteNotice ? notice.implicitWidth : info.implicitWidth) + 40)
                                : pill ? (vertical ? 200 : 340) : grid.implicitAlong
    // длина края — по самому окну: ShellScreen не всегда успевает за сменой масштаба
    readonly property real screenAlong: vertical ? height : width
    // сколько места от края занимает открытый док
    readonly property real reach: margin + thick
    // место под окна держим, только если док виден всегда и он не «пилюля»
    readonly property int zone: cfg.autohide !== true && !smart && length !== "compact" ? Math.round(margin + barThick) : 0
    readonly property bool shown: island.isOpen && !island.hidden

    readonly property bool menuHere: ShellState.menu !== "" && ShellState.menuScreen === screen
    readonly property bool hovered: island.hovered || hot.containsMouse || hint.containsMouse
    readonly property bool want: Settings.ready && ShellState.desktopShown && !ShellState.widgetEditing && (!autohide || hovered || hold.running || menuHere
                                 || ShellState.docksForced || ShellState.dockEditing || DockService.peek
                                 || DockService.musicPeek || noticing)
    onHoveredChanged: if (!hovered) hold.restart()
    // мышь ушла — ждём, вдруг вернётся (защита от дрожания у края)
    Timer { id: hold; interval: 700 }
    // Свёрнутый док оставляет у края маленькую «ручку»: видно, где он,
    // и не нужно искать щель в 3 px мышью.
    readonly property bool hintVisible: autohide && island.stage === 0 && !ShellState.dockEditing

    WlrLayershell.namespace: "delta-topdock"
    WlrLayershell.layer: WlrLayer.Top
    exclusionMode: ExclusionMode.Ignore
    anchors { top: edge !== "bottom"; bottom: edge !== "top"; left: edge !== "right"; right: edge !== "left" }
    implicitHeight: vertical ? 0 : 96
    implicitWidth: vertical ? 96 : 0
    color: "transparent"
    mask: Region {
        item: island.body
        Region { item: hot }
        Region { item: hint }
    }

    // начало окна в координатах экрана
    readonly property point origin: Qt.point(edge === "right" ? (screen?.width ?? 0) - width : 0,
                                             edge === "bottom" ? (screen?.height ?? 0) - height : 0)
    function screenRect(item) {
        const p = item.mapToItem(null, 0, 0);
        return { x: origin.x + p.x, y: origin.y + p.y, w: item.width, h: item.height };
    }
    // где открывать меню модуля id
    function anchorFor(id) {
        if (pill) return screenRect(pillContent);
        const s = grid.slotFor(id);
        return s && s.visible ? screenRect(s) : screenRect(island.body);
    }

    function activate(id) {
        // V в верхнем доке — это вход в «Настройки» Delta. Окно приложений
        // по-прежнему открывается клавишей Super и кнопкой в доке приложений.
        if (id === "launcher") { ShellState.closeMenu(); ShellState.openSettings("", anchorFor(id)); return; }
        if (ShellState.menu === id && ShellState.menuScreen === screen) {
            // второй щелчок двойного нажатия — меню остаётся открытым
            if (ShellState.menuJustOpened()) return;
            ShellState.noteDismiss("menu:" + id);
            ShellState.closeMenu();
        }
        else ShellState.openMenu(id, screen);
    }

    // открытый прямоугольник дока на экране — для «шариков» уведомлений и меню
    readonly property var openRect: {
        const sw = screen?.width ?? 0, sh = screen?.height ?? 0;
        if (vertical) return { x: edge === "left" ? margin : sw - margin - thick, y: (screenAlong - along) / 2, w: thick, h: along };
        return { x: (screenAlong - along) / 2, y: edge === "top" ? margin : sh - margin - thick, w: along, h: thick };
    }
    function publish() {
        if (!screen) return;
        const r = openRect;
        DockService.publishDock(screen.name, "top", { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.w), h: Math.round(r.h), edge: edge, shown: want });
    }
    onOpenRectChanged: publish()
    onWantChanged: publish()
    Component.onCompleted: publish()

    // полоска у края: подвести мышь — док выпадает.
    // 12 px вместо 3: в свёрнутом виде попасть в док можно, не «ловя» пиксель.
    MouseArea {
        id: hot
        hoverEnabled: true
        readonly property int t: win.autohide ? 12 : 0
        x: win.edge === "right" ? win.width - t : 0
        y: win.edge === "bottom" ? win.height - t : 0
        width: win.vertical ? t : win.width
        height: win.vertical ? win.height : t
    }

    // видимая ручка свёрнутого дока
    Rectangle {
        id: hint
        visible: win.hintVisible
        opacity: visible ? 0.6 : 0
        width: win.vertical ? 4 : 52
        height: win.vertical ? 52 : 4
        radius: 2
        color: Theme.accent
        x: win.vertical ? (win.edge === "left" ? 2 : win.width - width - 2) : (win.width - width) / 2
        y: win.vertical ? (win.height - height) / 2 : (win.edge === "top" ? 2 : win.height - height - 2)
        Behavior on opacity { NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.OutCubic } }
        SequentialAnimation on scale {
            running: hint.visible
            loops: Animation.Infinite
            NumberAnimation { to: 0.72; duration: 1200 * Theme.anim.k; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 1200 * Theme.anim.k; easing.type: Easing.InOutSine }
        }
        MouseArea { id: hintArea; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true }
        readonly property alias containsMouse: hintArea.containsMouse
    }

    Island {
        id: island
        anchors.fill: parent
        edge: win.edge
        along: win.along
        thick: win.thick
        radiusOpen: win.thick / 2
        margin: win.margin
        want: win.want
        tiles: win.length === "tiles" && !win.pill && !win.noticing
        editing: ShellState.dockEditing
        screenName: win.screen?.name ?? ""
        dockId: "top"
        origin: win.origin
        glass: DockService.topGlass

        ModuleGrid {
            id: grid
            anchors.centerIn: parent
            edge: win.edge
            length: win.length
            fullAlong: win.screenAlong - 32
            thick: win.barThick
            editing: ShellState.dockEditing
            screen: win.screen
            readonly property bool on: !win.pill && !win.noticing
            opacity: on ? 1 : 0
            visible: opacity > 0
            enabled: on
            // смена содержимого острова: старое быстро сжимается и тает, новое
            // проявляется с пружиной, когда тело уже перетекло в новую форму
            scale: on ? 1 : 0.84
            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: (grid.on ? 150 : 0) * Theme.anim.k }
                    NumberAnimation { duration: (grid.on ? 260 : 90) * Theme.anim.k; easing.type: Easing.OutCubic }
                }
            }
            Behavior on scale {
                SequentialAnimation {
                    PauseAnimation { duration: (grid.on ? 150 : 0) * Theme.anim.k }
                    NumberAnimation { duration: (grid.on ? 460 : 140) * Theme.anim.k; easing.type: grid.on ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.6 }
                }
            }
            onActivated: id => win.activate(id)
        }

        MusicPill {
            id: pillContent
            anchors.centerIn: parent
            vertical: win.vertical
            readonly property bool on: win.pill && !win.noticing
            opacity: on ? 1 : 0
            visible: opacity > 0
            // смена содержимого острова: старое быстро сжимается и тает, новое
            // проявляется с пружиной, когда тело уже перетекло в новую форму
            scale: on ? 1 : 0.84
            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: (pillContent.on ? 150 : 0) * Theme.anim.k }
                    NumberAnimation { duration: (pillContent.on ? 260 : 90) * Theme.anim.k; easing.type: Easing.OutCubic }
                }
            }
            Behavior on scale {
                SequentialAnimation {
                    PauseAnimation { duration: (pillContent.on ? 150 : 0) * Theme.anim.k }
                    NumberAnimation { duration: (pillContent.on ? 460 : 140) * Theme.anim.k; easing.type: pillContent.on ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.6 }
                }
            }
        }

        // сообщение острова: перечёркнутый колокольчик и подпись
        Row {
            id: notice
            anchors.centerIn: parent
            spacing: 10
            readonly property bool muted: DockService.notice?.muted ?? false
            readonly property bool on: win.muteNotice
            opacity: on ? 1 : 0
            visible: opacity > 0
            // смена содержимого острова: старое быстро сжимается и тает, новое
            // проявляется с пружиной, когда тело уже перетекло в новую форму
            scale: on ? 1 : 0.84
            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: (notice.on ? 150 : 0) * Theme.anim.k }
                    NumberAnimation { duration: (notice.on ? 260 : 90) * Theme.anim.k; easing.type: Easing.OutCubic }
                }
            }
            Behavior on scale {
                SequentialAnimation {
                    PauseAnimation { duration: (notice.on ? 150 : 0) * Theme.anim.k }
                    NumberAnimation { duration: (notice.on ? 460 : 140) * Theme.anim.k; easing.type: notice.on ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.6 }
                }
            }
            MuteBell {
                id: noticeBell
                anchors.verticalCenter: parent.verticalCenter
                size: 20
                color: notice.muted ? "#FF9F0A" : Theme.fg
                cutColor: DockService.topGlass
            }
            // Колокольчик начинает с прежнего состояния и через миг переключается:
            // черта рисуется (или втягивается) уже в раскрывающемся острове.
            Timer { id: noticeFlip; interval: 260; onTriggered: noticeBell.muted = notice.muted }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: !win.vertical
                text: notice.muted ? "Без звука" : "Звук включён"
                font.weight: Font.DemiBold
                color: notice.muted ? "#FF9F0A" : Theme.fg
            }
            Connections {
                target: DockService
                function onNoticeChanged() {
                    if (!DockService.notice || DockService.notice.kind !== "mute") return;
                    noticeBell.snapTo(!DockService.notice.muted);
                    noticeFlip.restart();
                }
            }
        }

        // событие системы: значок (или картинка программы), заголовок и подпись
        Row {
            id: info
            anchors.centerIn: parent
            spacing: 10
            readonly property var n: DockService.notice && DockService.notice.kind !== "mute" ? DockService.notice : null
            // пока остров сжимается, показываем прежнее событие
            property var shown: null
            onNChanged: if (n) shown = n
            readonly property color tint: shown && shown.color ? shown.color : Theme.fg
            readonly property bool on: win.noticing && !win.muteNotice
            opacity: on ? 1 : 0
            visible: opacity > 0
            scale: on ? 1 : 0.84
            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: (info.on ? 150 : 0) * Theme.anim.k }
                    NumberAnimation { duration: (info.on ? 260 : 90) * Theme.anim.k; easing.type: Easing.OutCubic }
                }
            }
            Behavior on scale {
                SequentialAnimation {
                    PauseAnimation { duration: (info.on ? 150 : 0) * Theme.anim.k }
                    NumberAnimation { duration: (info.on ? 460 : 140) * Theme.anim.k; easing.type: info.on ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.6 }
                }
            }
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 22
                IconImage {
                    id: infoImg
                    anchors.fill: parent
                    source: info.shown?.image ?? ""
                    visible: status === Image.Ready
                    asynchronous: true
                }
                Sym {
                    anchors.centerIn: parent
                    visible: !infoImg.visible
                    name: info.shown?.icon || "info"
                    size: 20
                    color: info.tint
                }
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: info.shown?.title ?? ""
                font.weight: Font.DemiBold
                color: info.tint
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 220)
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: !win.vertical && text.length > 0
                text: info.shown?.text ?? ""
                tone: 2
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 260)
            }
        }
    }

    // Фон дока. По пилюле: нажатие сразу открывает плеер, следующее — закрывает,
    // двойное — закрывает плеер и возвращает обычный верхний док (до конца музыки).
    // По полосе во время музыки: двойное нажатие — снова пилюля.
    MouseArea {
        parent: island.body
        anchors.fill: parent
        z: -1
        cursorShape: win.pill ? Qt.PointingHandCursor : Qt.ArrowCursor
        // звук без плеера MPRIS (игра, видео) — управлять нечем, открываем звук
        onClicked: if (win.pill) win.activate(DockService.streamOnly ? "sound" : "media")
        onDoubleClicked: {
            if (ShellState.dockEditing) return;
            if (ShellState.menu === "media") ShellState.closeMenu();
            DockService.toggleMediaView();
        }
    }
}
