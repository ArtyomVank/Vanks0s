import QtQuick
import Quickshell
import qs.common
import qs.common.ui
import qs.docks.parts

// Меню модуля верхнего дока: шарик выпадает из модуля и раскрывается
// в стеклянную карточку, внутри — menus/<Id>Menu.qml (CONTRACTS.md §5).
// Нет файла (или он с ошибкой) — аккуратная заглушка.
PopupLayer {
    id: pop

    property var topDock: null
    readonly property bool wanted: ShellState.menu !== "" && ShellState.menuScreen === screen
    // id держится и во время анимации закрытия
    property string menuId: ""
    property string loadedId: ""

    open: wanted
    edge: topDock?.edge ?? "top"
    reach: topDock?.reach ?? 58
    grabWith: topDock ? [topDock] : []
    pullKey: menuId && screen ? screen.name + "/top:" + menuId : ""
    onDismissed: { ShellState.noteDismiss("menu:" + ShellState.menu); ShellState.closeMenu(); }

    readonly property real maxH: (edge === "top" || edge === "bottom" ? sh : sh) - reach - 40
    readonly property Item menuItem: loader.status === Loader.Ready ? loader.item : null
    cardW: Math.max(240, (menuItem ? menuItem.implicitWidth : stub.implicitWidth) + 32)
    cardH: Math.min(maxH, (menuItem ? menuItem.implicitHeight : stub.implicitHeight) + 32)

    function sync() {
        if (!wanted) return;
        const id = ShellState.menu;
        if (topDock) anchorRect = topDock.anchorFor(id);
        menuId = id;
        if (loadedId === "" || blob.stage < 3) loadedId = id;
        else if (loadedId !== id) swap.restart();
    }
    onWantedChanged: sync()
    Connections { target: ShellState; function onMenuChanged() { pop.sync(); } }
    Component.onCompleted: sync()

    // смена меню без закрытия: старое гаснет, карточка переезжает, новое проявляется
    SequentialAnimation {
        id: swap
        NumberAnimation { target: holder; property: "opacity"; to: 0; duration: 90 }
        ScriptAction { script: pop.loadedId = pop.menuId }
        NumberAnimation { target: holder; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
    }

    Item {
        id: holder
        anchors.fill: parent

        Flickable {
            anchors { fill: parent; margins: 16 }
            contentWidth: width
            contentHeight: pop.menuItem ? pop.menuItem.implicitHeight : height
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            clip: interactive

            Loader {
                id: loader
                width: parent.width
                height: item ? item.implicitHeight : 0
                source: pop.loadedId ? Qt.resolvedUrl("../menus/" + DockService.cap(pop.loadedId) + "Menu.qml") : ""
                onLoaded: {
                    if ("screen" in item) item.screen = pop.screen;
                }
            }
            Connections {
                target: pop.menuItem
                ignoreUnknownSignals: true
                function onClose() { ShellState.closeMenu(); }
            }
        }

        // заглушка, пока владелец меню его не написал
        Column {
            id: stub
            visible: pop.menuItem === null
            anchors.centerIn: parent
            spacing: 10
            width: 260
            Sym {
                anchors.horizontalCenter: parent.horizontalCenter
                name: DockService.catalog[pop.loadedId]?.icon ?? "info"
                size: 30
                color: Theme.accent
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: DockService.catalog[pop.loadedId]?.name ?? "Меню"
                size: "title"
            }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: loader.status === Loader.Loading ? "Загрузка…" : "Это меню скоро появится"
                size: "small"
                tone: 3
            }
        }
    }
}
