import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.common
import qs.common.ui
import qs.docks.parts

// Значок дока приложений: приложение, ярлык, файл/папка, кнопка «Приложения»,
// «Добавить» или разделитель. Увеличение при наведении растёт от края,
// подскок при запуске — от края и обратно с затуханием (как в концепте).
Item {
    id: root

    required property var modelData
    required property int index
    // окружение дока
    property string edge: "bottom"
    readonly property bool vertical: edge === "left" || edge === "right"
    property int iconSize: 48
    property real across: 76
    property bool tiles: false
    property bool magnify: true
    property int hoverIndex: -1
    property var windows: []
    property string screenName: ""
    signal hoverChanged2(int index, bool on)
    signal activated(Item item)
    signal menuRequested(Item item)
    signal middleClicked(Item item)

    readonly property string kind: modelData.kind
    readonly property bool sep: kind === "sep"
    readonly property bool running: windows.length > 0
    readonly property DesktopEntry entry: {
        DesktopEntries.applications.values;
        if (kind === "app") return DesktopEntries.byId(modelData.id) ?? DesktopEntries.heuristicLookup(modelData.id);
        if (kind === "run") return DesktopEntries.heuristicLookup(modelData.appId);
        return null;
    }
    readonly property string name: kind === "launcher" ? "Приложения"
        : kind === "add" ? "Добавить в док"
        : entry ? entry.name
        : modelData.name || modelData.appId || modelData.id || ""
    // приложение из настроек, которого нет в системе, не показываем
    visible: !(kind === "app" && entry === null && DesktopEntries.applications.values.length > 0)

    // вектор к краю экрана
    readonly property real ex: edge === "left" ? -1 : edge === "right" ? 1 : 0
    readonly property real ey: edge === "top" ? -1 : edge === "bottom" ? 1 : 0
    readonly property real cell: sep ? 13 : iconSize + (tiles ? 12 : 0)
    width: !visible ? 0 : vertical ? across : cell
    height: !visible ? 0 : vertical ? cell : across

    readonly property real zoom: !magnify || sep || hoverIndex < 0 ? 1
        : hoverIndex === index ? 1.36 : Math.abs(hoverIndex - index) === 1 ? 1.14 : 1
    property real bounceOff: 0

    function bounce() { bounceAnim.restart(); }

    // разделитель
    Rectangle {
        visible: root.sep
        anchors.centerIn: parent
        width: root.vertical ? 40 : 1
        height: root.vertical ? 1 : 40
        color: Theme.line
    }

    Item {
        id: tile
        visible: !root.sep
        width: root.cell
        height: root.cell
        x: (root.width - width) / 2 - root.ex * (4.5 + root.bounceOff)
        y: (root.height - height) / 2 - root.ey * (4.5 + root.bounceOff)
        scale: root.zoom
        transformOrigin: root.edge === "top" ? Item.Top : root.edge === "left" ? Item.Left : root.edge === "right" ? Item.Right : Item.Bottom
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2 } }

        // Из плитки вытекает капля (окно приложений, «Добавить», меню значка):
        // плитка тянется за ней от края дока и пружинит, когда капля оторвалась.
        readonly property string pullKey: root.screenName + "/" + (root.kind === "launcher" ? "@launcher" : root.kind === "add" ? "@add" : root.modelData.key)
        property real pull: ShellState.pullKey === pullKey ? ShellState.pull : 0
        Behavior on pull { SpringAnimation { spring: 4.5; damping: 0.2; epsilon: 0.002 } }
        transform: [
            Scale {
                origin.x: root.edge === "left" ? 0 : root.edge === "right" ? tile.width : tile.width / 2
                origin.y: root.edge === "top" ? 0 : root.edge === "bottom" ? tile.height : tile.height / 2
                xScale: root.vertical ? 1 + 0.3 * tile.pull : 1 - 0.14 * tile.pull
                yScale: root.vertical ? 1 - 0.14 * tile.pull : 1 + 0.3 * tile.pull
            },
            // «желе» плитки: в плиточном режиме у каждого значка своё стекло,
            // и оно колышется само — как общее тело дока в других режимах
            Scale {
                origin.x: tile.width / 2
                origin.y: tile.height / 2
                xScale: 1 + tjx.value
                yScale: 1 + tjy.value
            }
        ]
        Spring { id: tjx; stiffness: 320; damping: 10 }
        Spring { id: tjy; stiffness: 320; damping: 10 }
        function wobble(k) { if (!root.tiles || root.sep) return; tjx.kick(k); tjy.kick(-0.8 * k); }
        Connections {
            target: area
            function onContainsMouseChanged() { if (area.containsMouse) tile.wobble(0.8); }
            function onPressedChanged() {
                if (area.pressed) { tjx.kick(root.tiles ? 1.3 : 0); tjy.kick(root.tiles ? -1.6 : 0); }
                else tile.wobble(-0.9);
            }
        }
        // толчок дока (открылось окно) — волна по плиткам
        Timer { id: tileRipple; property real k: 0; onTriggered: tile.wobble(k) }
        Connections {
            target: ShellState
            function onDockPoked(dockId, strength) {
                if (dockId !== "apps") return;
                tileRipple.k = 1.3 * strength;
                tileRipple.interval = 30 + 40 * root.index;
                tileRipple.restart();
            }
        }

        // плитка (режим «плитки»)
        Rectangle {
            anchors.fill: parent
            visible: root.tiles
            radius: 20
            color: Theme.glass
            border.width: 1
            border.color: Theme.line
        }

        Item {
            id: face
            anchors.centerIn: parent
            width: root.iconSize
            height: root.iconSize

            IconImage {
                anchors.fill: parent
                visible: root.kind === "app" || root.kind === "run"
                implicitSize: root.iconSize
                source: visible ? Quickshell.iconPath(root.entry?.icon ?? root.modelData.appId ?? "", "application-x-executable") : ""
                asynchronous: true
            }

            // кнопка «Приложения» — как значок приложения в концепте
            Rectangle {
                anchors.fill: parent
                visible: root.kind === "launcher"
                radius: 14
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.35) }
                    GradientStop { position: 1; color: Qt.darker(Theme.accent, 1.35) }
                }
                Sym { anchors.centerIn: parent; name: "apps"; size: 24; color: Theme.onAccent }
            }

            // ярлык, файл, «добавить»
            Rectangle {
                anchors.fill: parent
                visible: root.kind === "cmd" || root.kind === "path" || root.kind === "add"
                radius: 14
                color: root.kind === "add" ? "transparent" : Theme.soft2
                border.width: 1.5
                border.color: root.kind === "add" ? Theme.fg3 : Theme.line
                Sym {
                    anchors.centerIn: parent
                    size: root.kind === "add" ? 22 : 24
                    color: root.kind === "add" ? Theme.fg2 : Theme.fg
                    name: root.kind === "add" ? "plus" : root.kind === "cmd" ? "terminal"
                        : /\.[A-Za-z0-9]{1,5}$/.test(root.modelData.path || "") ? "file" : "folder"
                }
            }
        }
    }

    // точка «запущено» — со стороны края
    Rectangle {
        visible: !root.sep
        width: 5; height: 5; radius: 2.5
        x: (root.width - width) / 2 + root.ex * (root.cell / 2 + 2)
        y: (root.height - height) / 2 + root.ey * (root.cell / 2 + 2)
        color: Theme.accent
        opacity: root.running ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.anim.normal } }
    }

    // подсказка с названием — с дальней от края стороны
    Rectangle {
        id: tip
        visible: opacity > 0
        opacity: area.containsMouse && !root.sep && DockService.appMenu === null ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        width: tipText.implicitWidth + 20
        height: 26
        radius: 8
        color: Theme.glass2
        border.width: 1
        border.color: Theme.line
        readonly property real dist: root.cell * 1.36 / 2 + 18
        x: root.width / 2 - width / 2 - root.ex * (dist + width / 2) + (root.ex !== 0 ? 0 : 0)
        y: root.height / 2 - height / 2 - root.ey * (dist + height / 2)
        Label { id: tipText; anchors.centerIn: parent; text: root.name; size: "caption"; font.weight: Font.Bold }
    }

    SequentialAnimation {
        id: bounceAnim
        NumberAnimation { target: root; property: "bounceOff"; to: 26; duration: 180; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "bounceOff"; to: 0; duration: 180; easing.type: Easing.InQuad }
        NumberAnimation { target: root; property: "bounceOff"; to: 12; duration: 160; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "bounceOff"; to: 0; duration: 160; easing.type: Easing.InQuad }
        NumberAnimation { target: root; property: "bounceOff"; to: 4; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "bounceOff"; to: 0; duration: 110; easing.type: Easing.InQuad }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: !root.sep
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: root.hoverChanged2(root.index, containsMouse)
        onClicked: m => {
            if (m.button === Qt.RightButton) root.menuRequested(root);
            else if (m.button === Qt.MiddleButton) root.middleClicked(root);
            else root.activated(root);
        }
    }
}
