pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import qs.common
import qs.common.ui
import qs.launcher.parts
// с квалификатором: в docks/parts есть свой Field, он перекрыл бы поле поиска
import qs.docks.parts as DockParts
import "fuzzy.js" as Fuzzy

// Окно приложений (Super). Панель по центру экрана вырастает каплей из кнопки
// «Приложения» нижнего дока и стекает обратно в неё при закрытии. Окно слоя —
// на весь экран (капле нужно пространство до дока), но ввод и размытие — только
// у самой панели (mask, ignore_alpha), поэтому прозрачная часть ничего не стоит.
// Открывается через ShellState.overlay === "launcher" (сочетание ловит shell.qml).
Scope {
    id: root

    readonly property bool open: ShellState.overlay === "launcher"
    property string query: ""

    // для IPC и других модулей: открыть с готовым запросом
    function show(q) {
        query = q || "";
        ShellState.overlay = "launcher";
    }
    function hide() { if (open) ShellState.closeOverlay(); }

    // --- частота запусков: часто используемые выше ---
    property var usage: ({})
    FileView {
        id: usageFile
        path: Quickshell.statePath("launcher-usage.json")
        printErrors: false
        onLoaded: {
            try { root.usage = JSON.parse(text()) || {}; } catch (e) { root.usage = {}; }
        }
    }
    Timer {
        id: usageSave
        interval: 500
        onTriggered: usageFile.setText(JSON.stringify(root.usage))
    }

    // --- список приложений ---
    readonly property var catNames: ({
        AudioVideo: "Мультимедиа", Audio: "Музыка", Video: "Видео", Development: "Разработка",
        Education: "Образование", Game: "Игры", Graphics: "Графика", Network: "Интернет",
        Office: "Офис", Science: "Наука", Settings: "Настройки", System: "Система", Utility: "Стандартные"
    })
    function subtitle(e) {
        if (e.genericName && e.genericName !== e.name) return e.genericName;
        for (const c of e.categories || [])
            if (catNames[c]) return catNames[c];
        return e.comment || "";
    }

    readonly property var apps: {
        const seen = {};
        const out = [];
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay || seen[e.id]) continue;
            seen[e.id] = true;
            out.push(e);
        }
        return out;
    }

    readonly property var results: {
        const q = query.trim();
        const u = usage;
        const scored = [];
        for (const e of apps) {
            const s = q.length === 0 ? 1 : Fuzzy.score(q, [
                [e.name, 1.0], [e.genericName, 0.8], [e.keywords, 0.7],
                [e.categories, 0.45], [e.id, 0.5], [e.command && e.command.length ? e.command[0].split("/").pop() : "", 0.5]
            ]);
            if (s <= 0) continue;
            // частота запусков слегка поднимает приложение, но не перебивает точное совпадение
            const n = u[e.id] || 0;
            scored.push({ e, s: q.length === 0 ? n : s + Math.min(12, Math.log2(1 + n) * 3) });
        }
        scored.sort((a, b) => b.s - a.s || a.e.name.localeCompare(b.e.name));
        return scored.map(x => x.e);
    }

    readonly property var pinned: Settings.get("docks.apps.pinned", [])
    function togglePin(id) {
        const p = Array.isArray(pinned) ? pinned.slice() : [];
        const i = p.indexOf(id);
        if (i === -1) p.push(id); else p.splice(i, 1);
        Settings.set("docks.apps.pinned", p);
    }

    function launch(e) {
        if (!e) return;
        const u = Object.assign({}, usage);
        u[e.id] = (u[e.id] || 0) + 1;
        usage = u;
        usageSave.restart();
        if (e.runInTerminal) {
            // DesktopEntry.execute() не умеет Terminal=true — запускаем через терминал
            Quickshell.execDetached({
                command: ["sh", "-c", "xdg-terminal-exec \"$@\" 2>/dev/null || kitty -e \"$@\"", "sh"].concat(e.command),
                workingDirectory: e.workingDirectory || Quickshell.env("HOME")
            });
        } else {
            e.execute();
        }
        hide();
    }

    // --- окно ---
    // Монитор выбираем в момент открытия (где фокус), чтобы окно не прыгало.
    property ShellScreen targetScreen: Quickshell.screens[0] ?? null
    function focusedScreen() {
        const name = Hyprland.focusedMonitor?.name;
        return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0] ?? null;
    }

    // окно грузим при первом открытии и дальше держим скрытым — так Super срабатывает мгновенно
    property bool everOpened: false
    onOpenChanged: {
        if (open) {
            targetScreen = focusedScreen();
            everOpened = true;
        } else {
            query = "";
        }
    }

    LazyLoader {
        active: root.everOpened

        PanelWindow {
            id: win

            screen: root.targetScreen
            // окно видно, пока открыто или доигрывает закрытие
            property bool shown: false
            visible: shown
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "delta-launcher"
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"

            readonly property int panelW: 540
            readonly property int panelH: Math.min(620, (screen?.height ?? 800) - 140)
            mask: Region { x: panel.inputRect.x; y: panel.inputRect.y; width: panel.inputRect.width; height: panel.inputRect.height }

            // откуда течёт капля: кнопка «Приложения» в доке этого монитора,
            // иначе середина дока, иначе низ экрана (координаты экрана = окна)
            readonly property point source: {
                const name = screen?.name ?? "";
                const dock = (ShellState.dockGeometry[name] || {}).apps || null;
                const icon = ShellState.appIconGeometry["@launcher"];
                const ic = icon && icon.screen === name ? icon : null;
                if (!dock) return Qt.point(width / 2, height);
                const cx = ic ? ic.x + ic.size / 2 : dock.x + dock.w / 2;
                const cy = ic ? ic.y + ic.size / 2 : dock.y + dock.h / 2;
                // от края острова дока напротив кнопки: край вздувается каплей
                switch (dock.edge) {
                case "top": return Qt.point(cx, dock.y + dock.h);
                case "left": return Qt.point(dock.x + dock.w, cy);
                case "right": return Qt.point(dock.x, cy);
                default: return Qt.point(cx, dock.y);
                }
            }

            HyprlandFocusGrab {
                windows: [win]
                active: win.visible && root.open
                onCleared: { ShellState.noteDismiss("launcher"); root.hide(); }
            }

            Component.onCompleted: if (root.open) reset()
            function reset() {
                shown = true;
                list.currentIndex = 0;
                list.positionViewAtBeginning();
                field.focusInput();
            }

            Connections {
                target: root
                function onOpenChanged() { if (root.open) win.reset(); }
            }

            DockParts.Blob {
                id: panel
                strong: true
                x: Math.round((win.width - width) / 2)
                y: Math.round((win.height - height) / 2)
                width: win.panelW
                height: win.panelH
                radiusOpen: 26
                pullKey: (win.screen?.name ?? "") + "/@launcher"
                open: root.open && win.shown
                srcX: win.source.x - x
                srcY: win.source.y - y
                // доиграла обратная капля — окно можно прятать
                onClosed: if (!root.open) win.shown = false

                Column {
                    id: col
                    anchors { fill: parent; margins: 18 }
                    spacing: 12

                    Field {
                        id: field
                        width: parent.width
                        height: 50
                        radius: 16
                        fontSize: 16
                        placeholder: "Поиск приложений"
                        text: root.query
                        onTextChanged: if (root.query !== text) root.query = text
                        onAccepted: root.launch(root.results[list.currentIndex])
                        onKey: e => {
                            switch (e.key) {
                            case Qt.Key_Escape: root.hide(); break;
                            case Qt.Key_Down: list.incrementCurrentIndex(); break;
                            case Qt.Key_Up: list.decrementCurrentIndex(); break;
                            case Qt.Key_PageDown: list.currentIndex = Math.min(list.count - 1, list.currentIndex + 8); break;
                            case Qt.Key_PageUp: list.currentIndex = Math.max(0, list.currentIndex - 8); break;
                            case Qt.Key_Tab: list.incrementCurrentIndex(); break;
                            case Qt.Key_Backtab: list.decrementCurrentIndex(); break;
                            default: return;
                            }
                            e.accepted = true;
                        }

                        // подсказка «Super» справа, как в концепте
                        Rectangle {
                            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            visible: root.query.length === 0
                            width: kbd.implicitWidth + 12
                            height: 20
                            radius: 6
                            color: Theme.soft2
                            Label { id: kbd; anchors.centerIn: parent; text: "Super"; size: "caption"; tone: 2; font.weight: Font.DemiBold }
                        }
                    }

                    Label {
                        leftPadding: 6
                        text: root.query.trim().length ? "Найдено: " + root.results.length : "Все приложения · " + root.results.length
                        size: "small"
                        tone: 3
                        font.weight: Font.DemiBold
                    }

                    ListView {
                        id: list
                        width: parent.width
                        height: parent.height - y
                        clip: true
                        model: root.results
                        spacing: 2
                        boundsBehavior: Flickable.StopAtBounds
                        highlightMoveDuration: 120
                        highlightMoveVelocity: -1
                        keyNavigationWraps: false
                        reuseItems: true
                        cacheBuffer: 200
                        onModelChanged: currentIndex = 0

                        highlight: Rectangle {
                            radius: 14
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                        }

                        delegate: Item {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property bool isPinned: root.pinned.indexOf(modelData.id) !== -1

                            width: list.width
                            height: 56

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.launch(row.modelData)
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: 14
                                color: Theme.soft2
                                opacity: hover.hovered && list.currentIndex !== row.index ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Theme.anim.fast } }
                            }

                            IconImage {
                                id: icon
                                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                implicitSize: 38
                                asynchronous: true
                                source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                            }

                            Column {
                                anchors {
                                    left: icon.right; leftMargin: 12; right: pin.left; rightMargin: 10
                                    verticalCenter: parent.verticalCenter
                                }
                                spacing: 1
                                Label { width: parent.width; text: row.modelData.name; font.weight: Font.DemiBold }
                                Label {
                                    width: parent.width
                                    visible: text.length > 0
                                    text: root.subtitle(row.modelData)
                                    size: "caption"
                                    tone: 3
                                }
                            }

                            // «+ В док» / «В доке», как в концепте
                            Rectangle {
                                id: pin
                                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                width: pinLabel.implicitWidth + 20
                                height: 26
                                radius: 13
                                visible: hover.hovered || row.isPinned || list.currentIndex === row.index
                                color: row.isPinned ? Theme.fg : "transparent"
                                border.width: row.isPinned ? 0 : 1
                                border.color: Theme.line
                                Label {
                                    id: pinLabel
                                    anchors.centerIn: parent
                                    text: row.isPinned ? "В доке" : "+ В док"
                                    size: "caption"
                                    color: row.isPinned ? Theme.inv : Theme.fg2
                                    font.weight: Font.DemiBold
                                }
                                // MouseArea, а не TapHandler: нажатие не должно дойти до строки и запустить приложение
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.togglePin(row.modelData.id)
                                }
                            }

                            HoverHandler {
                                id: hover
                                onHoveredChanged: if (hovered) list.currentIndex = row.index
                            }
                        }

                        Label {
                            anchors.centerIn: parent
                            visible: list.count === 0
                            text: DesktopEntries.applications.values.length ? "Ничего не найдено" : "Загрузка…"
                            tone: 3
                        }
                    }
                }
            }
        }
    }
}
