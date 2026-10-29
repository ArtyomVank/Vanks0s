pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.common
import qs.common.ui
// с квалификатором: в docks/parts есть свой Field, он перекрыл бы поле поиска
import qs.docks.parts as DockParts
import qs.launcher.parts

// Меню рабочего стола: правый щелчок по обоям (wallpaper/Wallpaper.qml).
// Капля выходит из точки щелчка и растекается в карточку: виджеты, обои,
// настройки. Нажатие мимо или Esc — закрыть.
//     ShellState.openDesktopMenu(screen, x, y)
Scope {
    id: root

    readonly property var req: ShellState.desktopMenu
    readonly property bool wanted: req !== null
    // запрос держится, пока доигрывает закрытие
    property var shown: null
    onReqChanged: if (req) shown = req

    LazyLoader {
        active: root.shown !== null

        PanelWindow {
            id: win
            screen: root.shown?.screen ?? null

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "delta-popup"
            // не Exclusive: иначе Hyprland держит всю мышь на меню и нажатие мимо не закроет его
            WlrLayershell.keyboardFocus: root.wanted ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            mask: Region { x: blob.inputRect.x; y: blob.inputRect.y; width: blob.inputRect.width; height: blob.inputRect.height }

            HyprlandFocusGrab {
                active: root.wanted && win.visible
                windows: [win]
                onCleared: ShellState.closeDesktopMenu()
            }
            Shortcut {
                sequence: "Escape"
                enabled: root.wanted
                onActivated: ShellState.closeDesktopMenu()
            }

            readonly property real px: root.shown?.x ?? 0
            readonly property real py: root.shown?.y ?? 0

            DockParts.Blob {
                id: blob
                width: 280
                height: box.implicitHeight + 24
                // карточка справа-снизу от курсора, но в пределах экрана
                x: Math.max(12, Math.min(win.width - width - 12, win.px + 14))
                y: Math.max(12, Math.min(win.height - height - 12, win.py + 14))
                radiusOpen: 20
                open: root.wanted
                srcX: win.px - x
                srcY: win.py - y
                onClosed: if (!root.wanted) root.shown = null

                ColumnLayout {
                    id: box
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 6

                    MenuTitle { text: I18n.tr("Рабочий стол"); Layout.leftMargin: 4 }
                    MenuRow {
                        icon: "widgets"; title: I18n.tr("Изменить виджеты"); subtitle: I18n.tr("Добавить, переставить, настроить")
                        onClicked: { ShellState.closeDesktopMenu(); ShellState.widgetEditing = true; }
                    }
                    MenuRow {
                        icon: "image"; title: I18n.tr("Изменить обои"); subtitle: I18n.tr("Лента обоев из папки")
                        onClicked: { ShellState.closeDesktopMenu(); ShellState.overlay = "wallpapers"; }
                    }
                    MenuRow {
                        icon: "palette"; title: I18n.tr("Настройки обоев")
                        onClicked: { ShellState.closeDesktopMenu(); ShellState.openSettings("wallpapers", null); }
                    }
                    MenuRow {
                        icon: "lock"; title: I18n.tr("Экран блокировки")
                        onClicked: { ShellState.closeDesktopMenu(); ShellState.openSettings("lock", null); }
                    }
                    MenuRow {
                        icon: "settings"; title: I18n.tr("Настройки")
                        onClicked: { ShellState.closeDesktopMenu(); ShellState.openSettings("", null); }
                    }
                }
            }
        }
    }
}
