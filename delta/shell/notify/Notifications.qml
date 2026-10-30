pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import qs.common
import qs.docks

// Сервер уведомлений Delta (единственный) и всплывающие карточки.
// Карточки появляются на мониторе с фокусом, шариком из верхнего дока.
// История — NotifyStore, центр уведомлений — menus/NotificationsMenu.qml.
//     Notifications { id: notifications }   // Super+N → notifications.toggleCenter()
Scope {
    id: root

    NotificationServer {
        id: server
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: false
        bodyImagesSupported: false
        actionsSupported: true
        actionIconsSupported: false
        imageSupported: true
        inlineReplySupported: true
        onNotification: n => NotifyStore.add(n)
    }

    // «Не беспокоить»: источник правды — notifications.dnd, ShellState.dnd — зеркало
    // (его может переключить и чужой модуль, например меню питания).
    readonly property bool dndSetting: Settings.get("notifications.dnd", false) === true
    onDndSettingChanged: ShellState.dnd = dndSetting
    Component.onCompleted: ShellState.dnd = dndSetting
    Connections {
        target: ShellState
        function onDndChanged() {
            if (Settings.ready && ShellState.dnd !== root.dndSetting) Settings.set("notifications.dnd", ShellState.dnd);
        }
        // открыли центр уведомлений — всё прочитано
        function onMenuChanged() { if (ShellState.menu === "notifications") NotifyStore.markRead(); }
        function onNotificationsCleared() { NotifyStore.clear(); }
    }

    // центр уведомлений — меню модуля «Уведомления» на мониторе с фокусом
    function toggleCenter() {
        if (ShellState.menu === "notifications") ShellState.closeMenu();
        else ShellState.openMenu("notifications", DockService.focusedScreen());
    }

    // монитор для карточек выбираем в момент появления первой
    property ShellScreen target: null
    readonly property bool hasPopups: NotifyStore.popups.length > 0
    onHasPopupsChanged: if (hasPopups) target = DockService.focusedScreen()

    LazyLoader {
        active: root.hasPopups && root.target !== null

        PanelWindow {
            id: win
            screen: root.target

            readonly property var geo: ShellState.dockGeometry[screen?.name ?? ""] ?? ({})
            readonly property var top: geo.top ?? ({ edge: "top", x: 0, y: 0, w: 0, h: 0, shown: false })
            readonly property string edge: top.edge || "top"
            readonly property real sw: screen?.width ?? 0
            readonly property real sh: screen?.height ?? 0
            // дальний от края край верхнего дока (если он виден)
            readonly property real reach: !top.shown ? 4
                : edge === "top" ? top.y + top.h : edge === "bottom" ? sh - top.y
                : edge === "left" ? top.x + top.w : sw - top.x

            WlrLayershell.namespace: "delta-notifications"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            exclusionMode: ExclusionMode.Ignore
            anchors { top: edge === "top"; bottom: edge === "bottom"; left: edge === "left"; right: edge === "right" }
            margins { top: edge === "top" ? reach + 4 : 0; bottom: edge === "bottom" ? reach + 4 : 0; left: edge === "left" ? reach + 4 : 0; right: edge === "right" ? reach + 4 : 0 }
            implicitWidth: 420
            implicitHeight: Math.min(sh - 40, 600)
            color: "transparent"
            mask: Region { item: maskItem }

            Item {
                id: maskItem
                x: 20
                width: parent.width - 40
                height: Math.min(parent.height, list.contentHeight)
                y: win.edge === "bottom" ? parent.height - height : 0
            }

            ListView {
                id: list
                anchors.fill: parent
                interactive: false
                spacing: 0
                verticalLayoutDirection: win.edge === "bottom" ? ListView.BottomToTop : ListView.TopToBottom
                model: ScriptModel { values: NotifyStore.popups; objectProp: "key" }
                delegate: Toast {
                    x: (list.width - width) / 2
                    dirX: win.edge === "left" ? -1 : win.edge === "right" ? 1 : 0
                    dirY: win.edge === "top" ? -1 : win.edge === "bottom" ? 1 : 0
                    edge: win.edge
                    winW: win.width
                    winH: win.height
                    screenName: win.screen?.name ?? ""
                    // где окно карточек на экране (оно у края, по центру)
                    winOffset: Qt.point(win.edge === "left" ? win.reach + 4 : win.edge === "right" ? win.sw - win.reach - 4 - win.width : (win.sw - win.width) / 2,
                                        win.edge === "top" ? win.reach + 4 : win.edge === "bottom" ? win.sh - win.reach - 4 - win.height : (win.sh - win.height) / 2)
                }
                // новая карточка встаёт у дока, старые плавно отъезжают
                displaced: Transition {
                    NumberAnimation { properties: "y"; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                }
            }
        }
    }
}
