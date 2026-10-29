pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.common

// Доки одного монитора: верхний (модули), нижний (приложения), их меню,
// панель правки и резервирование места под постоянно видимые доки.
//     Docks { screen: modelData }
Scope {
    id: root

    required property ShellScreen screen

    TopDock {
        id: top
        screen: root.screen
    }

    AppDock {
        id: apps
        screen: root.screen
        topEdge: top.edge
        topReach: top.reach
    }

    // место под окна — только для постоянно видимых полных/плиточных доков
    LazyLoader {
        active: top.zone > 0
        Reserve { screen: root.screen; edge: top.edge; zone: top.zone }
    }
    LazyLoader {
        active: apps.zone > 0
        Reserve { screen: root.screen; edge: apps.edge; zone: apps.zone }
    }

    // Всплывающие окна грузятся, только пока они нужны (и доигрывают закрытие).
    property bool menuAlive: false
    readonly property bool menuWanted: ShellState.menu !== "" && ShellState.menuScreen === root.screen
    onMenuWantedChanged: if (menuWanted) menuAlive = true
    LazyLoader {
        active: root.menuAlive
        MenuPopup {
            screen: root.screen
            topDock: top
            onFinished: if (!wanted) root.menuAlive = false
        }
    }

    property bool appAlive: false
    readonly property bool appWanted: DockService.appMenu !== null && DockService.appMenu.screen === root.screen.name
    onAppWantedChanged: if (appWanted) appAlive = true
    LazyLoader {
        active: root.appAlive
        AppPopup {
            screen: root.screen
            appDock: apps
            onFinished: if (!wanted) root.appAlive = false
        }
    }

    property bool editAlive: false
    readonly property bool editWanted: ShellState.dockEditing && (DockService.editScreen === "" || DockService.editScreen === root.screen.name)
    onEditWantedChanged: if (editWanted) editAlive = true
    LazyLoader {
        active: root.editAlive
        EditPalette {
            screen: root.screen
            topDock: top
            onFinished: if (!wanted) root.editAlive = false
        }
    }
}
