pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.common
import qs.common.ui
import qs.docks.parts

// Меню значка дока приложений (правый щелчок) и окно «Добавить в док»:
// приложение из списка, ярлык (название + команда) или файл/папка.
PopupLayer {
    id: pop

    property var appDock: null
    readonly property var req: DockService.appMenu
    readonly property bool wanted: req !== null && req.screen === screen?.name
    // запрос держится и во время закрытия
    property var shown: null
    onWantedChanged: if (wanted && req) { shown = req; anchorRect = req.anchor; }
    onReqChanged: if (wanted && req) { shown = req; anchorRect = req.anchor; }
    Component.onCompleted: if (wanted) { shown = req; anchorRect = req.anchor; }

    open: wanted
    edge: appDock?.edge ?? "bottom"
    reach: appDock?.reach ?? 90
    grabWith: appDock ? [appDock] : []
    onDismissed: { ShellState.noteDismiss(DockService.appMenuKey(DockService.appMenu)); DockService.closeAppMenu(); }

    readonly property bool addMode: shown?.mode === "add"
    pullKey: shown && screen ? screen.name + "/" + (addMode ? "@add" : shown.app?.key ?? "") : ""
    cardW: addMode ? 380 : 260
    cardH: (addMode ? addBox.implicitHeight : ctxBox.implicitHeight) + 28

    readonly property var app: shown?.app ?? null
    readonly property var wins: app && appDock ? appDock.windowsFor(app.key) : []

    // --- меню значка ---
    ColumnLayout {
        id: ctxBox
        visible: !pop.addMode
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 2

        Label {
            text: pop.app?.name ?? ""
            size: "body"
            font.weight: Font.Bold
            Layout.fillWidth: true
            Layout.leftMargin: 10
            Layout.bottomMargin: 6
        }
        Row_ {
            icon: "window-plus"; text: "Новое окно"
            visible: pop.app !== null && pop.app.kind !== "path"
            onPicked: { pop.appDock.launchKey(pop.app.key); DockService.closeAppMenu(); }
        }
        Row_ {
            icon: pop.app?.kind === "path" ? "folder" : "window-plus"; text: "Открыть"
            visible: pop.app?.kind === "path"
            onPicked: { pop.appDock.launchKey(pop.app.key); DockService.closeAppMenu(); }
        }
        Row_ {
            readonly property bool pinned: pop.app ? DockService.isPinned(pop.app.key) : false
            icon: pinned ? "pin-off" : "pin"
            text: pinned ? "Убрать из дока" : "Закрепить в доке"
            visible: pop.app !== null && (pinned || pop.app.kind === "run")
            onPicked: {
                if (pinned) DockService.unpin(pop.app.key);
                else {
                    const e = DesktopEntries.heuristicLookup(pop.app.appId);
                    DockService.pin(e ? e.id : pop.app.appId);
                }
                DockService.closeAppMenu();
            }
        }
        Row_ {
            icon: "close"; danger: true
            text: pop.wins.length > 1 ? "Закрыть все окна (" + pop.wins.length + ")" : "Закрыть"
            visible: pop.wins.length > 0
            onPicked: { for (const t of pop.wins) t.close(); DockService.closeAppMenu(); }
        }
    }

    component Row_: Rectangle {
        id: r
        property string icon
        property string text
        property bool danger: false
        signal picked()
        Layout.fillWidth: true
        implicitHeight: 38
        radius: 10
        color: hov.hovered ? Theme.soft2 : "transparent"
        Behavior on color { ColorAnimation { duration: 120 * Theme.anim.k } }
        RowLayout {
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            spacing: 10
            Sym { name: r.icon; size: 18; color: r.danger ? "#ff6b6b" : Theme.fg2 }
            Label { text: r.text; color: r.danger ? "#ff6b6b" : Theme.fg; Layout.fillWidth: true }
        }
        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: r.picked() }
    }

    // --- «Добавить в док» ---
    ColumnLayout {
        id: addBox
        visible: pop.addMode
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        spacing: 12

        property string tab: "app"
        Connections {
            target: pop
            function onShownChanged() { if (pop.addMode) { addBox.tab = "app"; search.text = ""; name.text = ""; cmd.text = ""; path.text = ""; } }
        }

        Label { text: "Добавить в док"; size: "title" }
        Chips {
            model: [{ value: "app", label: "Приложение" }, { value: "cmd", label: "Ярлык" }, { value: "path", label: "Файл или папка" }]
            current: addBox.tab
            onPicked: v => {
                addBox.tab = v;
                (v === "app" ? search : v === "cmd" ? name : path).focusField();
            }
        }

        // приложение
        Field {
            id: search
            visible: addBox.tab === "app"
            Layout.fillWidth: true
            icon: "search"
            placeholder: "Поиск приложения"
            Component.onCompleted: focusField()
        }
        ListView {
            id: apps
            visible: addBox.tab === "app"
            Layout.fillWidth: true
            Layout.preferredHeight: 264
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: {
                if (!pop.addMode || addBox.tab !== "app") return [];
                const q = search.text.trim().toLowerCase();
                return DesktopEntries.applications.values
                    .filter(e => !e.noDisplay && (!q || e.name.toLowerCase().indexOf(q) !== -1 || (e.genericName || "").toLowerCase().indexOf(q) !== -1))
                    .sort((a, b) => a.name.localeCompare(b.name));
            }
            delegate: Rectangle {
                id: ar
                required property DesktopEntry modelData
                readonly property bool pinned: DockService.isPinned("app:" + modelData.id)
                width: ListView.view.width
                height: 44
                radius: 10
                color: ah.hovered ? Theme.soft2 : "transparent"
                RowLayout {
                    anchors { fill: parent; leftMargin: 8; rightMargin: 10 }
                    spacing: 10
                    IconImage { implicitSize: 30; source: Quickshell.iconPath(ar.modelData.icon, "application-x-executable"); asynchronous: true }
                    Label { text: ar.modelData.name; Layout.fillWidth: true }
                    Sym { visible: ar.pinned; name: "check"; size: 18; color: Theme.accent }
                }
                HoverHandler { id: ah; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        if (!ar.pinned) DockService.pin(ar.modelData.id);
                        DockService.closeAppMenu();
                    }
                }
            }
            Label {
                anchors.centerIn: parent
                visible: apps.count === 0
                text: "Ничего не найдено"
                tone: 3
            }
        }

        // ярлык
        Field { id: name; visible: addBox.tab === "cmd"; Layout.fillWidth: true; placeholder: "Название"; onAccepted: cmd.focusField() }
        Field { id: cmd; visible: addBox.tab === "cmd"; Layout.fillWidth: true; icon: "terminal"; placeholder: "Команда, например: kitty -e htop"; onAccepted: addCmd.clicked() }
        // файл или папка
        Field { id: path; visible: addBox.tab === "path"; Layout.fillWidth: true; icon: "folder"; placeholder: "Путь, например: ~/Документы"; onAccepted: addPath.clicked() }
        Label {
            visible: addBox.tab === "path"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Открывается программой по умолчанию (xdg-open)"
            size: "small"
            tone: 3
        }

        RowLayout {
            visible: addBox.tab !== "app"
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            Btn { text: "Отмена"; onClicked: DockService.closeAppMenu() }
            Btn {
                id: addCmd
                visible: addBox.tab === "cmd"
                text: "Добавить"; kind: "accent"
                enabled: cmd.text.trim().length > 0
                onClicked: {
                    if (!enabled) return;
                    DockService.pin({ type: "cmd", name: name.text.trim() || cmd.text.trim().split(/\s+/)[0], command: cmd.text.trim() });
                    DockService.closeAppMenu();
                }
            }
            Btn {
                id: addPath
                visible: addBox.tab === "path"
                text: "Добавить"; kind: "accent"
                enabled: path.text.trim().length > 0
                onClicked: {
                    if (!enabled) return;
                    const p = path.text.trim();
                    DockService.pin({ type: "path", name: p.replace(/\/+$/, "").split("/").pop() || p, path: p });
                    DockService.closeAppMenu();
                }
            }
        }
    }
}
