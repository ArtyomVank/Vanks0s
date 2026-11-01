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
    // IPC (демо, проверки): меню первой строки, как правый щелчок по ней
    property bool menuPending: false
    function showMenu() { menuPending = true; }
    // IPC: окно удаления для первой строки, как «Удалить» в её меню
    function showRemove() { if (results.length) askRemove(results[0]); }

    // --- удаление приложения (меню строки → «Удалить») ---
    // delta-store what <id> говорит, что это (программа Windows, flatpak,
    // пакет, просто ярлык) и можно ли удалить; окно подтверждения показывает
    // это словами, delta-store uninstall удаляет как положено. Меню само
    // обновится: DesktopEntries следит за папками ярлыков.
    property var removal: null          // ответ what: { id, name, kind, can, why, … }
    property bool removing: false
    property string removeStep: ""
    function askRemove(entry) {
        removal = { id: entry.id, name: entry.name, kind: "", can: false, why: "" };
        whatProc.command = ["delta-store", "what", entry.id];
        whatProc.running = true;
    }
    function confirmRemove() {
        if (!removal || !removal.can || removing) return;
        removing = true;
        removeStep = I18n.tr("Удаляю…");
        uninstallProc.command = ["delta-store", "uninstall", removal.id];
        uninstallProc.running = true;
    }
    // тексты delta-store — по-русски; «Удаляю <имя>» и «Причина: <пакеты>» переводим по частям
    function trStep(t) {
        if (t.startsWith("Удаляю ")) return I18n.tr("Удаляю…");
        const i = t.indexOf(": ");
        return i > 0 ? I18n.tr(t.slice(0, i)) + ": " + t.slice(i + 2) : I18n.tr(t);
    }
    Process {
        id: whatProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.removal) return;
                try {
                    const r = JSON.parse(text);
                    root.removal = Object.assign({ name: root.removal.name }, r, { name: r.name || root.removal.name });
                } catch (e) {
                    root.removal = Object.assign({}, root.removal, { kind: "none", why: I18n.tr("Не удалось узнать, откуда это приложение") });
                }
            }
        }
    }
    Process {
        id: uninstallProc
        stdout: SplitParser {
            onRead: line => { if (line.startsWith("::step:: ")) root.removeStep = root.trStep(line.slice(9)); }
        }
        onExited: code => {
            const name = root.removal ? root.removal.name : "";
            root.removing = false;
            root.removal = null;
            Sounds.play(code === 0 ? "swoosh" : "dialog-error", 0);
            Quickshell.execDetached(["notify-send", "-a", "Delta", "-i", code === 0 ? "user-trash" : "dialog-error",
                code === 0 ? I18n.tr("Приложение удалено") : I18n.tr("Удалить не получилось"),
                code === 0 ? name : root.removeStep]);
        }
    }
    // ярлыки удалённых программ Windows убираются сами — при открытии меню
    property real tidiedAt: 0
    function tidy() {
        if (Date.now() - tidiedAt < 60000) return;
        tidiedAt = Date.now();
        Quickshell.execDetached(["sh", "-c", "command -v delta-exe >/dev/null && exec delta-exe --tidy"]);
    }

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
            Sounds.play("launcher", 0);
            tidy();
        } else {
            query = "";
            if (!removing) removal = null;
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
                // док спрятан — капля течёт от края экрана, где его язычок
                if (dock.shown === false) {
                    const mx = dock.x + dock.w / 2, my = dock.y + dock.h / 2;
                    switch (dock.edge) {
                    case "top": return Qt.point(mx, 0);
                    case "left": return Qt.point(0, my);
                    case "right": return Qt.point(width, my);
                    default: return Qt.point(mx, height);
                    }
                }
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
            // меню строки (правый щелчок): { entry, x, y } в координатах панели
            property var ctx: null
            function reset() {
                shown = true;
                ctx = null;
                list.currentIndex = 0;
                list.positionViewAtBeginning();
                field.focusInput();
                // подсказка в поле печатается со щелчками, строки въезжают по очереди
                hint.play(140);
                counter.play(220);
                rowsIn.restart();
            }
            Timer {
                running: root.menuPending && root.open
                interval: 500
                onTriggered: {
                    root.menuPending = false;
                    const it = list.itemAtIndex(0);
                    if (!it) return;
                    list.currentIndex = 0;
                    const p = it.mapToItem(panel, it.width * 0.62, it.height * 0.75);
                    win.ctx = { entry: it.modelData, x: p.x, y: p.y };
                }
            }
            Typewriter { id: hint; full: I18n.tr("Поиск приложений") }
            Typewriter {
                id: counter
                sound: false
                full: root.query.trim().length ? I18n.tr("Найдено") + ": " + root.results.length : I18n.tr("Все приложения") + " · " + root.results.length
            }
            property real appear: 1
            NumberAnimation { id: rowsIn; target: win; property: "appear"; from: 0; to: 1; duration: 620; easing.type: Easing.OutCubic }

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

                // меню строки: щелчок мимо закрывает
                MouseArea {
                    anchors.fill: parent
                    z: 10
                    visible: win.ctx !== null
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressed: win.ctx = null
                }
                Rectangle {
                    id: ctxMenu
                    z: 11
                    visible: win.ctx !== null
                    readonly property var entry: win.ctx ? win.ctx.entry : null
                    readonly property bool pinned: entry ? root.pinned.indexOf(entry.id) !== -1 : false
                    width: 250
                    height: ctxCol.implicitHeight + 16
                    x: win.ctx ? Math.max(8, Math.min(panel.width - width - 8, win.ctx.x)) : 0
                    y: win.ctx ? Math.max(8, Math.min(panel.height - height - 8, win.ctx.y)) : 0
                    radius: 16
                    color: Theme.glass
                    border.width: 1
                    border.color: Theme.line
                    scale: visible ? 1 : 0.92
                    transformOrigin: Item.TopLeft
                    Behavior on scale { NumberAnimation { duration: 200 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }

                    component CtxItem: Rectangle {
                        id: ci
                        property string icon
                        property string text
                        signal picked()
                        width: ctxCol.width
                        height: 38
                        radius: 10
                        color: ciHov.hovered ? Theme.soft2 : "transparent"
                        Row {
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 10
                            Sym { name: ci.icon; size: 18; color: Theme.fg2; anchors.verticalCenter: parent.verticalCenter }
                            Label { text: ci.text; anchors.verticalCenter: parent.verticalCenter }
                        }
                        HoverHandler { id: ciHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { ci.picked(); win.ctx = null; } }
                    }

                    Column {
                        id: ctxCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                        spacing: 2
                        Label {
                            width: parent.width
                            leftPadding: 10; topPadding: 4; bottomPadding: 6
                            text: ctxMenu.entry ? ctxMenu.entry.name : ""
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                        }
                        CtxItem {
                            icon: "play"; text: I18n.tr("Открыть")
                            onPicked: root.launch(ctxMenu.entry)
                        }
                        CtxItem {
                            icon: ctxMenu.pinned ? "pin-off" : "pin"
                            text: ctxMenu.pinned ? I18n.tr("Убрать из дока") : I18n.tr("Закрепить в доке")
                            onPicked: root.togglePin(ctxMenu.entry.id)
                        }
                        CtxItem {
                            icon: "widgets"; text: I18n.tr("Ярлык на рабочий стол")
                            onPicked: { ShellState.addAppWidget(ctxMenu.entry.id); root.hide(); }
                        }
                        CtxItem {
                            icon: "trash"; text: I18n.tr("Удалить")
                            onPicked: root.askRemove(ctxMenu.entry)
                        }
                    }
                }

                // подтверждение удаления: что именно удалится
                MouseArea {
                    anchors.fill: parent
                    z: 12
                    visible: root.removal !== null
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressed: if (!root.removing) root.removal = null
                    // список под окном удаления притушен
                    Rectangle { anchors.fill: parent; radius: panel.radiusOpen; color: Qt.rgba(0, 0, 0, 0.35) }
                }
                Rectangle {
                    id: removeBox
                    z: 13
                    visible: root.removal !== null
                    readonly property var r: root.removal || ({})
                    readonly property string details: {
                        if (r.kind === "") return I18n.tr("Смотрю, что это за приложение…");
                        if (!r.can) return r.why ? root.trStep(r.why) : I18n.tr("Это приложение удалить нельзя");
                        switch (r.kind) {
                        case "windows": {
                            let t = r.whole ? I18n.tr("Удалится программа вместе с её системой Windows")
                                : r.dir ? I18n.tr("Удалится папка программы в Delta Box") : I18n.tr("Уберётся её ярлык");
                            if (r.size && r.size !== "0") t += " (" + r.size + ")";
                            if (r.keep) t += ". " + I18n.tr("Файлы в папке") + " «" + r.keep.split("/").pop() + "» " + I18n.tr("останутся");
                            return t + ".";
                        }
                        case "flatpak": return I18n.tr("Приложение Flatpak удалится. Ваши файлы останутся.");
                        case "pacman": return I18n.tr("Пакет") + " «" + r.pkg + "» " + I18n.tr("удалится — понадобится пароль администратора.");
                        case "shortcut": return I18n.tr("Ярлык уберётся из меню приложений.");
                        }
                        return r.why ? root.trStep(r.why) : "";
                    }
                    width: Math.min(panel.width - 48, 400)
                    height: rmCol.implicitHeight + 36
                    x: Math.round((panel.width - width) / 2)
                    y: Math.round((panel.height - height) / 2)
                    radius: 20
                    // поверх списка — плотная, иначе строки просвечивают сквозь текст
                    color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.97)
                    border.width: 1
                    border.color: Theme.line
                    scale: visible ? 1 : 0.92
                    Behavior on scale { NumberAnimation { duration: 220 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }

                    Column {
                        id: rmCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
                        spacing: 12
                        Row {
                            spacing: 10
                            Sym { name: "trash"; size: 22; color: "#ff6b6b"; anchors.verticalCenter: parent.verticalCenter }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                width: rmCol.width - 32
                                text: I18n.tr("Удалить") + " «" + (removeBox.r.name || "") + "»?"
                                size: "title"
                                elide: Text.ElideRight
                            }
                        }
                        Label {
                            width: parent.width
                            text: root.removing ? root.removeStep : removeBox.details
                            tone: 3
                            wrapMode: Text.WordWrap
                        }
                        Row {
                            anchors.right: parent.right
                            spacing: 8
                            Btn {
                                text: removeBox.r.can || removeBox.r.kind === "" ? I18n.tr("Отмена") : I18n.tr("Понятно")
                                enabled: !root.removing
                                onClicked: root.removal = null
                            }
                            Btn {
                                visible: removeBox.r.can === true
                                text: root.removing ? I18n.tr("Удаляю…") : I18n.tr("Удалить")
                                kind: "danger"
                                enabled: !root.removing
                                onClicked: root.confirmRemove()
                            }
                        }
                    }
                }

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
                        placeholder: hint.text
                        text: root.query
                        onTextChanged: if (root.query !== text) root.query = text
                        onAccepted: root.launch(root.results[list.currentIndex])
                        onKey: e => {
                            switch (e.key) {
                            case Qt.Key_Escape: if (root.removal && !root.removing) root.removal = null; else if (win.ctx) win.ctx = null; else root.hide(); break;
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
                        text: counter.text
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
                            // при открытии строки выезжают снизу одна за другой
                            readonly property real enter: win.appear >= 1 ? 1 : Math.max(0, Math.min(1, win.appear * 12 - index * 0.8))
                            opacity: enter
                            transform: Translate { y: (1 - row.enter) * 18 }

                            // левый — открыть, правый — меню: в док, ярлык на рабочий стол
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: m => {
                                    if (m.button !== Qt.RightButton) { root.launch(row.modelData); return; }
                                    const p = mapToItem(panel, m.x, m.y);
                                    win.ctx = { entry: row.modelData, x: p.x, y: p.y };
                                }
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
