pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import qs.common
import qs.common.ui
import qs.docks

// Рабочие столы.
//  • Обзор (Super+Tab, ShellState.overlay === "workspaces"): по центру экрана
//    все столы карточками — подпись, уменьшенный стол со схемой окон и
//    значками программ, список того, что открыто. Щелчок или Enter — перейти;
//    стрелки и Tab — выбрать, цифры — сразу на стол, Esc — закрыть.
//    Последняя карточка «+» — новый стол.
//  • Смена стола (клавиши, жест, док): сами окна листает Hyprland
//    (workspaces style slide), а по центру на миг — пилюля «Рабочий стол N»
//    с точками, отметка переезжает к новому столу. Настройка — workspaces.indicator.
Scope {
    id: root

    readonly property int current: Hyprland.focusedWorkspace?.id ?? 1
    readonly property var real: Hyprland.workspaces.values.filter(w => w.id > 0)
    // столы 1…последний занятый (и текущий): пустые между ними тоже видны
    readonly property var ids: {
        let max = Math.max(1, current);
        for (const w of real) max = Math.max(max, w.id);
        const out = [];
        for (let i = 1; i <= max; i++) out.push(i);
        return out;
    }

    function dispatch(lua, legacy) { Hyprland.dispatch(Hyprland.usingLua ? lua : legacy); }
    function go(id) { dispatch("hl.dsp.focus({ workspace = " + id + " })", "workspace " + id); }
    function goNew() { dispatch('hl.dsp.focus({ workspace = "empty" })', "workspace empty"); }

    function windowsWord(n) {
        if (!n) return I18n.tr("Пусто");
        const m10 = n % 10, m100 = n % 100;
        const w = m10 === 1 && m100 !== 11 ? "окно" : m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) ? "окна" : "окон";
        return n + " " + I18n.tr(w);
    }

    // окна стола: где стоят (координаты Hyprland), чьи, как называются
    property int rev: 0
    function windowsOn(id) {
        const out = [];
        for (const t of Hyprland.toplevels.values) {
            const o = t.lastIpcObject || {};
            if ((t.workspace?.id ?? 0) !== id || !(o.at?.length >= 2) || !(o.size?.length >= 2)) continue;
            out.push({
                cls: o.class || o.initialClass || "",
                title: t.title || o.title || "",
                x: o.at[0], y: o.at[1], w: o.size[0], h: o.size[1],
                floating: o.floating === true,
                active: t === Hyprland.activeToplevel
            });
        }
        // плитка — снизу, плавающие — сверху, активное — выше всех
        out.sort((a, b) => (a.floating - b.floating) || (a.active - b.active));
        return out;
    }
    function entryFor(cls) { return cls ? DesktopEntries.heuristicLookup(cls) : null; }
    function iconFor(cls) {
        // нет значка в теме — запасной, а не «шахматка» Qt
        const e = entryFor(cls);
        return (e?.icon ? Quickshell.iconPath(e.icon, true) : "") || Quickshell.iconPath(cls.toLowerCase(), true)
            || Quickshell.iconPath("application-x-executable", true);
    }
    function appName(w) { return entryFor(w.cls)?.name || w.cls || I18n.tr("Окно"); }

    // ================= обзор =================
    LazyLoader {
        active: ShellState.overlay === "workspaces" && !ShellState.locked

        PanelWindow {
            id: ov
            screen: DockService.focusedScreen()

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "delta-workspaces"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"

            property bool shown: false
            property int sel: Math.max(0, root.ids.indexOf(root.current))
            readonly property int count: root.ids.length + 1     // + «новый стол»

            // стол на этом мониторе: его размер — пропорции карточки и масштаб окон
            readonly property HyprlandMonitor mon: Hyprland.monitorFor(ov.screen)
            readonly property real monW: Math.max(1, (mon?.width ?? 1920) / (mon?.scale || 1))
            readonly property real monH: Math.max(1, (mon?.height ?? 1080) / (mon?.scale || 1))
            readonly property real monX: mon?.x ?? 0
            readonly property real monY: mon?.y ?? 0

            readonly property real gap: 18
            readonly property real cardW: Math.min(280, (width - 180 - gap * (count - 1)) / count)
            readonly property real thumbH: cardW * monH / monW

            function dismiss() {
                if (!shown) return;
                shown = false;
                closeTimer.restart();
            }
            function pick(i) {
                if (i >= root.ids.length) root.goNew();
                else if (root.ids[i] !== root.current) root.go(root.ids[i]);
                dismiss();
            }
            Timer { id: closeTimer; interval: Theme.anim.normal; onTriggered: ShellState.closeOverlay() }
            // окна и столы перечитываем при открытии (ответ Hyprland приходит не сразу)
            Timer { id: refreshed; interval: 90; onTriggered: root.rev++ }
            Component.onCompleted: {
                Hyprland.refreshWorkspaces();
                Hyprland.refreshToplevels();
                refreshed.start();
                shown = true;
                Sounds.play("pop", 120);
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.55)
                opacity: ov.shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.anim.normal; easing.type: Theme.anim.outCurve } }
                MouseArea { anchors.fill: parent; onClicked: ov.dismiss() }
            }

            // подложка: на пёстрых обоях подписи иначе не читаются
            Glass {
                strong: true
                anchors.centerIn: parent
                width: content.width + 56
                height: content.height + 52
                radius: Theme.radius + 10
                opacity: ov.shown ? 1 : 0
                scale: ov.shown ? 1 : 0.96
                Behavior on opacity { NumberAnimation { duration: Theme.anim.normal; easing.type: Theme.anim.outCurve } }
                Behavior on scale { NumberAnimation { duration: Theme.anim.slow; easing.type: Theme.anim.outCurve } }
                MouseArea { anchors.fill: parent }       // щелчок по подложке не закрывает
            }

            Column {
                id: content
                anchors.centerIn: parent
                spacing: 22

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.tr("Рабочие столы")
                    size: "h1"
                    font.weight: Font.Bold
                    font.family: Theme.fontDisplay
                    color: Theme.fg
                    opacity: ov.shown ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.anim.normal } }
                }

                Row {
                    spacing: ov.gap

                    Repeater {
                        model: root.ids.concat([0])
                        delegate: Item {
                            id: card
                            required property int modelData
                            required property int index
                            readonly property bool isNew: modelData === 0
                            readonly property bool here: modelData === root.current
                            readonly property bool chosen: index === ov.sel
                            readonly property var wins: { root.rev; return isNew ? [] : root.windowsOn(modelData); }

                            width: ov.cardW
                            height: ov.thumbH + 96
                            // карточки выезжают снизу одна за другой
                            opacity: ov.shown ? 1 : 0
                            transform: Translate { y: ov.shown ? 0 : 40 + card.index * 8 }
                            Behavior on opacity { NumberAnimation { duration: Theme.anim.normal + card.index * 40; easing.type: Theme.anim.outCurve } }
                            scale: hover.hovered || card.chosen ? 1.035 : 1
                            Behavior on scale { NumberAnimation { duration: Theme.anim.fast; easing.type: Easing.OutCubic } }

                            // уменьшенный стол: обои и схема окон
                            Rectangle {
                                id: thumb
                                width: parent.width
                                height: ov.thumbH
                                radius: 14
                                color: Theme.glass2
                                clip: true
                                border.width: card.here ? 2.5 : card.chosen ? 1.5 : 1
                                border.color: card.here ? Theme.accent : card.chosen ? Qt.rgba(1, 1, 1, 0.7) : Qt.rgba(1, 1, 1, 0.18)

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: parent.border.width
                                    visible: !card.isNew && Theme.wallFile !== ""
                                    source: visible ? "file://" + Theme.wallFile : ""
                                    sourceSize: Qt.size(320, 200)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    opacity: 0.85
                                }

                                Repeater {
                                    model: card.wins
                                    delegate: Rectangle {
                                        id: mini
                                        required property var modelData
                                        readonly property real k: thumb.width / ov.monW
                                        x: (mini.modelData.x - ov.monX) * k
                                        y: (mini.modelData.y - ov.monY) * k
                                        width: Math.max(14, mini.modelData.w * k)
                                        height: Math.max(10, mini.modelData.h * k)
                                        radius: 6
                                        color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.82)
                                        border.width: 1
                                        border.color: mini.modelData.active ? Theme.accent : Qt.rgba(1, 1, 1, 0.28)
                                        IconImage {
                                            anchors.centerIn: parent
                                            implicitSize: Math.min(28, Math.min(parent.width, parent.height) * 0.6)
                                            source: root.iconFor(mini.modelData.cls)
                                        }
                                    }
                                }

                                Sym {
                                    visible: card.isNew
                                    anchors.centerIn: parent
                                    name: "plus"
                                    size: 34
                                    color: Theme.fg2
                                }
                                Rectangle {
                                    visible: !card.isNew && card.wins.length === 0
                                    anchors.centerIn: parent
                                    width: emptyLbl.implicitWidth + 22
                                    height: 26
                                    radius: 13
                                    color: Qt.rgba(0, 0, 0, 0.45)
                                    Label { id: emptyLbl; anchors.centerIn: parent; text: I18n.tr("Пусто"); size: "small"; color: "#FFFFFF" }
                                }
                            }

                            // подпись и что открыто
                            Column {
                                anchors { top: thumb.bottom; topMargin: 10; left: parent.left; right: parent.right }
                                spacing: 4
                                Row {
                                    spacing: 8
                                    Rectangle {
                                        visible: card.here
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 8; height: 8; radius: 4
                                        color: Theme.accent
                                    }
                                    Label {
                                        text: card.isNew ? I18n.tr("Новый стол") : I18n.tr("Рабочий стол ") + card.modelData
                                        font.weight: Font.DemiBold
                                        color: Theme.fg
                                    }
                                    Label {
                                        visible: !card.isNew
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.windowsWord(card.wins.length)
                                        size: "small"
                                        tone: 3
                                    }
                                }
                                Repeater {
                                    model: card.wins.slice().reverse().slice(0, 3)
                                    delegate: Row {
                                        id: line
                                        required property var modelData
                                        spacing: 6
                                        IconImage {
                                            anchors.verticalCenter: parent.verticalCenter
                                            implicitSize: 16
                                            source: root.iconFor(line.modelData.cls)
                                        }
                                        Label {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: ov.cardW - 22
                                            elide: Text.ElideRight
                                            text: root.appName(line.modelData) + (line.modelData.title && line.modelData.title !== root.appName(line.modelData)
                                                  ? " — " + line.modelData.title : "")
                                            size: "small"
                                            tone: 2
                                        }
                                    }
                                }
                            }

                            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: ov.pick(card.index) }
                        }
                    }
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.tr("←  →  выбрать · Enter — перейти · 1–9 — сразу на стол · Esc — закрыть")
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
                    const k = e.key;
                    if (k === Qt.Key_Escape) ov.dismiss();
                    else if (k === Qt.Key_Left || k === Qt.Key_Backtab) ov.sel = (ov.sel + ov.count - 1) % ov.count;
                    else if (k === Qt.Key_Right || k === Qt.Key_Tab) ov.sel = (ov.sel + 1) % ov.count;
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) ov.pick(ov.sel);
                    else if (k >= Qt.Key_1 && k <= Qt.Key_9) { root.go(k - Qt.Key_0); ov.dismiss(); }
                    else return;
                    e.accepted = true;
                }
            }
        }
    }

    // ================= пилюля при смене стола =================
    readonly property bool indicatorOn: Settings.get("workspaces.indicator", true) !== false
    property int shownId: current
    property int fromId: current
    property bool want: false
    property bool alive: false
    onWantChanged: if (want) alive = true
    onCurrentChanged: {
        if (!indicatorOn || ShellState.overlay === "workspaces" || ShellState.locked || !ShellState.desktopShown) { shownId = current; return; }
        fromId = shownId;
        shownId = current;
        want = true;
        hideTimer.restart();
    }
    Timer { id: hideTimer; interval: 950; onTriggered: root.want = false }
    Timer { id: unloadTimer; interval: Theme.anim.normal + 50; running: !root.want && root.alive; onTriggered: root.alive = false }

    LazyLoader {
        active: root.alive

        PanelWindow {
            id: pill
            screen: DockService.focusedScreen()
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "delta-workspace-pill"
            exclusionMode: ExclusionMode.Ignore
            implicitWidth: 360
            implicitHeight: 120
            color: "transparent"
            mask: Region {}                       // не мешает мыши

            readonly property var dots: root.ids
            readonly property real step: 18

            Glass {
                id: box
                strong: true
                anchors.centerIn: parent
                width: Math.max(220, name.implicitWidth + 48, dotRow.width + 48)
                height: 84
                radius: 26
                opacity: root.want ? 1 : 0
                scale: root.want ? 1 : 0.9
                Behavior on opacity { NumberAnimation { duration: Theme.anim.fast; easing.type: Theme.anim.outCurve } }
                Behavior on scale { NumberAnimation { duration: Theme.anim.normal; easing.type: Theme.anim.springCurve } }

                Label {
                    id: name
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 16 }
                    text: I18n.tr("Рабочий стол ") + root.shownId
                    size: "title"
                    font.weight: Font.DemiBold
                }

                // точки столов; отметка текущего уезжает в сторону листания
                Item {
                    id: dotRow
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 18 }
                    width: Math.max(1, pill.dots.length) * pill.step
                    height: 8
                    Repeater {
                        model: pill.dots
                        delegate: Rectangle {
                            required property int index
                            x: index * pill.step + (pill.step - 8) / 2
                            width: 8; height: 8; radius: 4
                            color: Theme.soft2
                        }
                    }
                    Rectangle {
                        // с прежнего стола — на новый: первым кадром стоит на прежнем
                        property int markId: root.fromId
                        Component.onCompleted: Qt.callLater(() => { markId = Qt.binding(() => root.shownId); })
                        readonly property int at: Math.max(0, pill.dots.indexOf(markId))
                        x: at * pill.step + (pill.step - width) / 2
                        width: 20; height: 8; radius: 4
                        color: Theme.accent
                        Behavior on x { SpringAnimation { spring: 4; damping: 0.32 } }
                    }
                }
            }
        }
    }
}
