pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.common
import qs.common.ui
import qs.minimize

// Кнопки окна: свернуть, развернуть на весь экран, закрыть.
//
// Hyprland не рисует заголовки, поэтому кнопки — слой оболочки поверх
// активного окна на каждом мониторе. Геометрию окна знает только Hyprland:
// Quickshell спрашивает её сам (refreshToplevels, без запуска hyprctl) —
// чаще после событий окна, реже в покое, а пока окно перетаскивают — совсем
// нет: каждый такой запрос — работа для композитора, окно бы подтормаживало.
//
// Программы со своими кнопками в заголовке (браузеры, Electron, GNOME) кнопок
// Delta не получают: список — windows.buttonsSkip (регулярные выражения по
// классу окна). Правый щелчок по пилюле добавляет туда текущую программу.
// Без кнопок всегда: окна на весь экран (игры, видео), игры (Hyprland
// помечает их content type «game», Proton — класс steam_app_* или *.exe) и
// окна самой Delta — настройки, первая настройка, delta-exe рисуют своё.
//
// Пока окно двигается (перетаскивание, клавиши, анимация), пилюля прячется:
// поспевать за окном кадр в кадр слой оболочки не может и дёргался бы.
//
// Настройка: windows.buttons (Настройки → Окна → Кнопки окна).
Scope {
    id: root

    readonly property bool enabled: Settings.get("windows.buttons", true) !== false
    readonly property bool hidden: ShellState.locked || ShellState.unlocking
                                   || ShellState.overlay !== "" || ShellState.menu !== "" || ShellState.desktopMenu !== null
                                   || ShellState.widgetEditing || ShellState.dockEditing || ShellState.lockEditing

    // классы окон со своими кнопками
    readonly property var skipRe: {
        const list = Settings.get("windows.buttonsSkip", []);
        const out = [];
        for (const p of (Array.isArray(list) ? list : [])) {
            if (typeof p !== "string" || !p.length) continue;
            try { out.push(new RegExp(p, "i")); } catch (e) { console.warn("[delta] windows.buttonsSkip: " + p + ": " + e); }
        }
        return out;
    }
    function skipped(cls) { return cls.length > 0 && skipRe.some(r => r.test(cls)); }
    // игры и окна Delta — без кнопок, что бы ни было в списке
    readonly property var builtinSkip: /^(delta(-.*)?|steam_app_.*|.*\.exe|gamescope|steam_proton|explorer\.exe)$/i
    function system(w) {
        return (w.fullscreen ?? 0) >= 2 || w.contentType === "game" || builtinSkip.test(w.class ?? "")
            || builtinSkip.test(w.initialClass ?? "");
    }
    function skipApp(cls) {
        if (!cls) return;
        const list = Settings.get("windows.buttonsSkip", []);
        const re = "^" + cls.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "$";
        Settings.set("windows.buttonsSkip", (Array.isArray(list) ? list : []).concat([re]));
    }

    // активное окно: { address, x, y, w, h, monitor, fullscreen, floating, class, title }
    property var win: null

    function norm(a) { return String(a || "").replace(/^0x/, ""); }

    // w — lastIpcObject активного окна (то, что Hyprland отдаёт в j/clients)
    function parse(w) {
        if (!w || !w.address || w.mapped === false || w.hidden === true) { setWin(null); return; }
        const ws = w.workspace?.name ?? "";
        // свёрнутые живут на скрытом столе — кнопки им не нужны
        if (ws.startsWith("special:")) { setWin(null); return; }
        // at/size — списки Qt, не массивы JS: Array.isArray для них false
        if (!(w.at?.length >= 2) || !(w.size?.length >= 2)) { setWin(null); return; }
        if (skipped(w.class ?? "") || system(w)) { setWin(null); return; }
        setWin({
            address: norm(w.address),
            x: w.at[0], y: w.at[1], w: w.size[0], h: w.size[1],
            monitor: w.monitor,
            fullscreen: w.fullscreen ?? 0,
            floating: w.floating === true,
            class: w.class ?? "",
            title: w.title ?? ""
        });
    }
    // Новое значение — только если что-то изменилось: иначе привязки
    // пересчитывались бы на каждом опросе. Движение включает частый опрос.
    function setWin(n) {
        const o = win;
        if (o === null && n === null) return;
        if (o && n && o.address === n.address && o.x === n.x && o.y === n.y && o.w === n.w && o.h === n.h
            && o.monitor === n.monitor && o.fullscreen === n.fullscreen && o.class === n.class) return;
        if (o && n && o.address === n.address) {
            wakeFast();
            // сдвинулось или поменяло размер — прячем пилюлю до остановки
            if (o.x !== n.x || o.y !== n.y || o.w !== n.w || o.h !== n.h) { moving = true; still.restart(); }
        }
        win = n;
    }
    property bool moving: false
    Timer { id: still; interval: 260; onTriggered: root.moving = false }

    // --- опрос --------------------------------------------------------------

    // после событий окна опрашиваем чаще, пока не замрёт на 400 мс
    property bool fast: false
    function wakeFast() { fast = true; calm.restart(); }
    Timer { id: calm; interval: 400; onTriggered: root.fast = false }

    function refresh() {
        if (!enabled || hidden) { setWin(null); return; }
        Hyprland.refreshToplevels();
    }
    function readActive() {
        if (!enabled || hidden) { setWin(null); return; }
        const h = Hyprland.activeToplevel;
        parse(h ? h.lastIpcObject : null);
    }

    Timer {
        interval: root.fast ? 80 : 200
        repeat: true
        running: root.enabled && !root.hidden && !DragState.dragging
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // окно отпустили — сразу узнаём, где оно теперь
    Connections {
        target: DragState
        function onDraggingChanged() { if (!DragState.dragging) { root.wakeFast(); root.refresh(); } }
    }

    // ответ Hyprland пришёл — данные активного окна обновились
    Connections {
        target: Hyprland.activeToplevel
        function onLastIpcObjectChanged() { root.readActive(); }
    }
    Connections {
        target: Hyprland
        function onActiveToplevelChanged() { root.readActive(); }
    }

    // События Hyprland меняют активное окно или его состояние — обновляем сразу
    // и какое-то время часто: окно может доигрывать анимацию появления.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            switch (event.name) {
            case "activewindow":
            case "activewindowv2":
            case "openwindow":
            case "closewindow":
            case "changefloatingmode":
            case "fullscreen":
            case "movewindow":
            case "movewindowv2":
                root.wakeFast();
                root.refresh();
                break;
            }
        }
    }

    // --- действия -----------------------------------------------------------

    function focus(addr) {
        Hyprland.dispatch(Hyprland.usingLua
            ? 'hl.dsp.focus({ window = "address:0x' + addr + '" })'
            : "focuswindow address:0x" + addr);
    }
    function close(addr) {
        if (Hyprland.usingLua) {
            Hyprland.dispatch('hl.dsp.window.close({ window = "address:0x' + addr + '" })');
        } else {
            focus(addr);
            Hyprland.dispatch("killactive");
        }
    }
    function fullscreen(addr) {
        // без window диспетчер действует на активное окно — сначала фокус
        focus(addr);
        Motion.maximize();
    }
    function minimize(addr) {
        const h = Minimizer.byAddress(addr);
        if (h) Minimizer.minimize(h);
    }

    // --- слой на каждом мониторе -------------------------------------------

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: layer
            required property ShellScreen modelData
            screen: layer.modelData

            readonly property var mon: Hyprland.monitors.values.find(m => m.name === layer.modelData.name) ?? null
            readonly property var w: root.win && mon && root.win.monitor === mon.id ? root.win : null
            readonly property bool show: root.enabled && !root.hidden && w !== null
            // двигается — пилюля исчезает (ввод в неё тоже), потом появляется на месте
            readonly property bool still: !root.moving && !DragState.dragging

            // размеры пилюли с тремя кнопками
            readonly property int btn: 22
            readonly property int pad: 6
            readonly property int gap: 6
            readonly property int bw: btn * 3 + gap * 2 + pad * 2
            readonly property int bh: btn + pad * 2
            // окно в локальных координатах монитора, кнопки — в правом верхнем углу
            readonly property real bx: w ? w.x - layer.modelData.x + w.w - bw - 8 : 0
            readonly property real by: w ? w.y - layer.modelData.y + 8 : 0

            visible: show
            color: "transparent"
            WlrLayershell.namespace: "delta-window-controls"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; left: true }
            implicitWidth: layer.modelData.width
            implicitHeight: layer.modelData.height

            // ввод — только в прямоугольник кнопок, остальное пропускаем в окно
            mask: show && still ? buttonRegion : emptyRegion
            Region { id: emptyRegion }
            Region {
                id: buttonRegion
                Region { x: layer.bx; y: layer.by; width: layer.bw; height: layer.bh }
            }

            Rectangle {
                id: pill
                x: layer.bx; y: layer.by
                width: layer.bw; height: layer.bh
                radius: height / 2
                color: Theme.glass2
                border.width: 1
                border.color: Theme.line
                opacity: layer.show && layer.still ? 1 : 0
                visible: opacity > 0

                // правый щелчок — эта программа рисует свои кнопки, наши ей не нужны
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: if (layer.w) root.skipApp(layer.w.class)
                }
                Behavior on opacity { NumberAnimation { duration: Theme.anim.fast } }

                Row {
                    anchors.centerIn: parent
                    spacing: layer.gap

                    // свернуть в значок дока
                    Rectangle {
                        width: layer.btn; height: layer.btn
                        radius: height / 2
                        color: minHover.hovered ? Theme.soft2 : "transparent"
                        scale: minTap.pressed ? 0.9 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.anim.fast } }
                        Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
                        Sym { anchors.centerIn: parent; name: "minus"; size: Math.round(layer.btn * 0.52); color: Theme.fg }
                        HoverHandler { id: minHover }
                        TapHandler { id: minTap; onTapped: if (layer.w) root.minimize(layer.w.address) }
                    }

                    // развернуть / вернуть прежний размер
                    Rectangle {
                        width: layer.btn; height: layer.btn
                        radius: height / 2
                        color: maxHover.hovered ? Theme.soft2 : "transparent"
                        scale: maxTap.pressed ? 0.9 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.anim.fast } }
                        Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
                        Sym {
                            anchors.centerIn: parent
                            name: layer.w && layer.w.fullscreen > 0 ? "restore" : "maximize"
                            size: Math.round(layer.btn * 0.48)
                            color: Theme.fg
                        }
                        HoverHandler { id: maxHover }
                        TapHandler { id: maxTap; onTapped: if (layer.w) root.fullscreen(layer.w.address) }
                    }

                    // закрыть
                    Rectangle {
                        width: layer.btn; height: layer.btn
                        radius: height / 2
                        color: closeHover.hovered ? Theme.accents[5] : "transparent"
                        scale: closeTap.pressed ? 0.9 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.anim.fast } }
                        Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
                        Sym {
                            anchors.centerIn: parent
                            name: "close"
                            size: Math.round(layer.btn * 0.5)
                            color: closeHover.hovered ? "#ffffff" : Theme.fg
                        }
                        HoverHandler { id: closeHover }
                        TapHandler { id: closeTap; onTapped: if (layer.w) root.close(layer.w.address) }
                    }
                }
            }
        }
    }
}
