import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.common

// Всплывающая карточка у дока (меню модуля, меню значка, «Добавить», правка).
//
// Окно на весь экран, но ввод принимает только карточка (mask), поэтому
// координаты карточки — координаты экрана. Нажатие мимо (HyprlandFocusGrab)
// или Esc — сигнал dismissed; после анимации закрытия — finished, и владелец
// может выгрузить окно.
PanelWindow {
    id: win

    property bool open: false
    // край дока, от которого раскрывается карточка, и сколько места док занимает
    property string edge: "top"
    property real reach: 60
    property real gap: 10
    // прямоугольник того, что открыло карточку (модуль, значок) — на экране
    property var anchorRect: ({ x: 0, y: 0, w: 0, h: 0 })
    property real cardW: 320
    property real cardH: 200
    property bool keyboard: true
    property bool grab: true
    property var grabWith: []
    property bool strong: true
    // плитка дока, из которой течёт капля (см. Blob.pullKey)
    property string pullKey: ""
    default property alias content: blob.content
    readonly property alias blob: blob
    signal dismissed()
    signal finished()

    WlrLayershell.namespace: "delta-popup"
    WlrLayershell.layer: WlrLayer.Top
    // Не Exclusive: слою с исключительной клавиатурой Hyprland отдаёт и всю мышь,
    // и нажатия по доку (другой модуль, повторно тот же) терялись бы. OnDemand
    // слой верхнего уровня всё равно получает фокус, когда появляется.
    WlrLayershell.keyboardFocus: open && keyboard ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    mask: Region { x: blob.inputRect.x; y: blob.inputRect.y; width: blob.inputRect.width; height: blob.inputRect.height }

    // окно на весь экран — его размер и есть размер экрана
    readonly property real sw: width
    readonly property real sh: height
    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

    readonly property real cx: edge === "left" ? reach + gap
        : edge === "right" ? sw - reach - gap - cardW
        : clamp(anchorRect.x + anchorRect.w / 2 - cardW / 2, 16, sw - cardW - 16)
    readonly property real cy: edge === "top" ? reach + gap
        : edge === "bottom" ? sh - reach - gap - cardH
        : clamp(anchorRect.y + anchorRect.h / 2 - cardH / 2, 16, sh - cardH - 16)

    Blob {
        id: blob
        x: win.cx
        y: win.cy
        width: win.cardW
        height: win.cardH
        open: win.open
        strong: win.strong
        pullKey: win.pullKey
        radiusOpen: 22
        dirX: win.edge === "left" ? -1 : win.edge === "right" ? 1 : 0
        dirY: win.edge === "top" ? -1 : win.edge === "bottom" ? 1 : 0
        fly: win.gap + 30
        // капля отрывается от дока прямо у того, что открыло карточку
        readonly property bool anchored: win.anchorRect && win.anchorRect.w > 0
        srcX: !anchored ? NaN
            : win.edge === "left" ? win.reach - x
            : win.edge === "right" ? win.sw - win.reach - x
            : win.anchorRect.x + win.anchorRect.w / 2 - x
        srcY: !anchored ? NaN
            : win.edge === "top" ? win.reach - y
            : win.edge === "bottom" ? win.sh - win.reach - y
            : win.anchorRect.y + win.anchorRect.h / 2 - y
        onClosed: win.finished()
        // переход между меню соседних модулей — карточка переезжает пружиной
        Behavior on x { enabled: blob.stage === 3; NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
        Behavior on y { enabled: blob.stage === 3; NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
    }

    HyprlandFocusGrab {
        active: win.open && win.grab && win.visible
        windows: [win].concat(win.grabWith)
        onCleared: if (win.open) win.dismissed()
    }

    Shortcut {
        sequence: "Escape"
        enabled: win.open
        onActivated: win.dismissed()
    }
}
