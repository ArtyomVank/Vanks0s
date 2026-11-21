import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.common
import qs.common.ui
import qs.lock

// Панель управления стиля «Слои» (Delta 2): лист во всю высоту у правого
// края. Внутри — тот же центр управления, что в «Акриле» (lock/ControlCenter:
// блоки музыки, света, сети, быстрых кнопок, VPN и уведомлений, правятся
// карандашом). Рабочий стол под листом уходит назад: окно во весь экран
// с тёмной вуалью — композитор размывает его, как все слои delta-*.
// Открывается меню «power» верхнего дока (Theme.sheetMenu); щелчок мимо
// листа, Esc или повторное нажатие — закрыть. После анимации закрытия —
// finished, и Docks выгружает окно.
PanelWindow {
    id: win

    property bool open: false
    signal dismissed()
    signal finished()

    WlrLayershell.namespace: "delta-sheet"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    readonly property real sheetW: Math.min(440, width - 32)
    readonly property real gap: 10

    // 0 — лист за краем экрана, 1 — на месте
    property real t: 0
    Component.onCompleted: t = open ? 1 : 0
    onOpenChanged: t = open ? 1 : 0
    Behavior on t {
        NumberAnimation {
            id: slide
            duration: win.open ? Theme.anim.slow : Theme.anim.normal
            easing.type: win.open ? Easing.OutQuint : Easing.InCubic
            onRunningChanged: if (!running && !win.open) win.finished()
        }
    }

    // вуаль: рабочий стол темнеет и (через размытие слоя) уходит назад
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.32 * win.t
        // MouseArea, а не TapHandler: обработчик вуали получал и нажатия по
        // кнопкам листа (их TapHandler не забирает нажатие) — карандаш
        // «Изменить» и быстрые кнопки закрывали лист
        MouseArea { anchors.fill: parent; onClicked: win.dismissed() }
    }

    Rectangle {
        id: sheet
        width: win.sheetW
        height: parent.height - 2 * win.gap
        y: win.gap
        x: win.width - (win.sheetW + win.gap) * win.t
        // при открытии лист чуть «подплывает» из глубины
        scale: 0.96 + 0.04 * win.t
        transformOrigin: Item.Right
        opacity: Math.min(1, win.t * 1.6)
        radius: Math.max(18, Theme.radius + 8)
        color: Theme.glass
        border.color: Theme.line
        border.width: 1

        // нажатия по самому листу не доходят до вуали (она закрывает)
        MouseArea { anchors.fill: parent }

        Flickable {
            id: flick
            anchors { fill: parent; margins: 20 }
            contentWidth: width
            contentHeight: cc.implicitHeight
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            ControlCenter {
                id: cc
                width: flick.width
                screen: win.screen
                onClose: win.dismissed()
            }
        }
    }

    HyprlandFocusGrab {
        active: win.open && win.visible
        windows: [win]
        onCleared: if (win.open) win.dismissed()
    }

    Shortcut {
        sequence: "Escape"
        enabled: win.open
        onActivated: win.dismissed()
    }
}
