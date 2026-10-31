pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import qs.common
import qs.common.ui
import qs.launcher.parts
import "../wallpaper/media.js" as Media
import "../launcher/fuzzy.js" as Fuzzy

// Выбор обоев (Super+S, правый щелчок по столу → «Изменить обои»):
// карусель скошенных карточек поверх стола — выбранная крупно слева, дальше
// уходят вглубь всё меньше. Сверху панель: сетка/карусель, недавние, только
// видео, восемь цветов и поиск по имени файла.
// Открывается через ShellState.overlay === "wallpapers". Здесь же живёт
// смена обоев по таймеру (wallpaper.rotate, минуты; 0 — выключено).
Scope {
    id: root

    readonly property bool open: ShellState.overlay === "wallpapers"
    property string type: "all"     // all | photo | video
    property string tint: "all"     // all | id из WallStore.buckets
    property string query: ""
    // name — по имени, recent — сначала недавно добавленные
    property string sort: "name"
    // carousel | grid — запоминается
    readonly property string view: Settings.get("wallpaper.pickerView", "carousel") === "grid" ? "grid" : "carousel"

    // для IPC: открыть с фильтрами
    function show(t, c, q) {
        type = t || "all";
        tint = c || "all";
        query = q || "";
        ShellState.overlay = "wallpapers";
    }
    function hide() { if (open) ShellState.closeOverlay(); }

    readonly property string current: Settings.get("wallpaper.path", "")

    readonly property var results: {
        const q = query.trim();
        const cols = WallStore.colors;
        const out = [];
        for (const it of WallStore.items) {
            if (type === "photo" && it.video) continue;
            if (type === "video" && !it.video) continue;
            if (tint !== "all" && (!cols[it.key] || cols[it.key].b !== tint)) continue;
            if (q.length && Fuzzy.score(q, [[it.name, 1]]) < 30) continue;
            out.push(it);
        }
        if (sort === "recent") out.sort((a, b) => b.mtime - a.mtime);
        return out;
    }

    // --- смена по таймеру ---
    readonly property int rotate: Number(Settings.get("wallpaper.rotate", 0)) || 0
    onRotateChanged: if (rotate > 0) WallStore.scan()
    Component.onCompleted: if (rotate > 0) WallStore.scan()
    Timer {
        interval: Math.max(1, root.rotate) * 60000
        running: root.rotate > 0 && !ShellState.locked
        repeat: true
        onTriggered: {
            const allowVideo = Settings.get("wallpaper.allowVideo", true) !== false;
            const list = WallStore.items.filter(it => allowVideo || !it.video);
            if (list.length < 2) { WallStore.scan(); return; }
            const i = list.findIndex(it => it.path === root.current);
            WallStore.apply(list[(i + 1) % list.length]);
        }
    }

    // --- выбор папки ---
    // zenity — окно поверх выбора обоев не видно, поэтому выбор на это время прячем
    property bool pickingFolder: false
    function chooseFolder() {
        pickingFolder = true;
        hide();
        folderProc.running = true;
    }
    Process {
        id: folderProc
        command: ["sh", "-c", "command -v zenity >/dev/null || exit 3; zenity --file-selection --directory --title='Папка с обоями' --filename=\"$1/\"", "sh", WallStore.folder]
        stdout: StdioCollector { id: folderOut }
        onExited: code => {
            root.pickingFolder = false;
            const p = folderOut.text.trim();
            if (code === 0 && p) Settings.set("wallpaper.folder", p);
            root.editFolder = code === 3;       // zenity нет — даём ввести путь руками
            ShellState.overlay = "wallpapers";
        }
    }
    property bool editFolder: false

    // --- окно ---
    property ShellScreen targetScreen: Quickshell.screens[0] ?? null
    property bool everOpened: false
    onOpenChanged: {
        if (open) {
            const name = Hyprland.focusedMonitor?.name;
            targetScreen = Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0] ?? null;
            everOpened = true;
            WallStore.scan();
        } else if (!pickingFolder) {
            editFolder = false;
        }
    }

    LazyLoader {
        active: root.everOpened

        PanelWindow {
            id: win

            screen: root.targetScreen
            property bool shown: false
            visible: shown
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "delta-wallpapers"
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"

            HyprlandFocusGrab {
                windows: [win]
                active: win.visible && root.open
                onCleared: { ShellState.noteDismiss("wallpapers"); root.hide(); }
            }

            // --- геометрия карусели ---
            // выбранная карточка: высота hMax, ширина wMax; остальные — уже и ниже
            readonly property real hMax: Math.round(Math.max(220, Math.min(height * 0.52, 480)))
            readonly property real wMax: Math.round(Math.min(hMax * 1.34, width * 0.5))
            // наклон краёв карточек (сдвиг верха вправо на долю высоты)
            readonly property real k: 0.27
            readonly property real gap: 16
            readonly property real x0: Math.max(24, width * 0.04)
            readonly property real cy: height * 0.5 + 26
            function hAt(d) { return d <= 0 ? hMax : hMax * Math.pow(0.915, d); }
            function wAt(d) {
                if (d <= 0) return wMax;
                const side = hAt(d) * 0.7;
                return d >= 1 ? side : wMax + (side - wMax) * d;
            }
            function xAt(d) {
                if (d <= 0) return x0 + d * (wMax + gap);
                const n = Math.floor(d);
                let x = x0;
                for (let j = 0; j < n; j++) x += wAt(j) + gap;
                return x + (d - n) * (wAt(n) + gap);
            }

            // какая карточка выбрана (cur) и плавное положение ленты (pos)
            property int cur: 0
            property real pos: cur
            property bool snapping: false
            Behavior on pos { enabled: !win.snapping; NumberAnimation { duration: 460 * Theme.anim.k; easing.type: Easing.OutCubic } }
            function go(i) {
                const n = root.results.length;
                if (n === 0) return;
                cur = Math.max(0, Math.min(n - 1, i));
            }
            function pick(i) {
                go(i);
                WallStore.apply(root.results[cur]);
            }

            // выезд карточек справа и обратно
            property real enter: 0
            NumberAnimation {
                id: enterAnim
                target: win; property: "enter"
                to: 1; duration: 700 * Theme.anim.k; easing.type: Easing.OutCubic
            }
            NumberAnimation {
                id: leaveAnim
                target: win; property: "enter"
                to: 0; duration: 280 * Theme.anim.k; easing.type: Easing.InCubic
                onFinished: if (!root.open) win.shown = false
            }

            Component.onCompleted: if (root.open) reset()
            function reset() {
                shown = true;
                const i = Math.max(0, root.results.findIndex(it => it.path === root.current));
                // при открытии лента сразу на текущих обоях, без прокрутки
                snapping = true;
                cur = i;
                snapping = false;
                if (root.editFolder) folderField.focusInput(); else keys.forceActiveFocus();
                leaveAnim.stop();
                enterAnim.restart();
            }
            Connections {
                target: root
                function onOpenChanged() {
                    if (root.open) win.reset();
                    else { enterAnim.stop(); leaveAnim.restart(); }
                }
                function onResultsChanged() {
                    const i = root.results.findIndex(it => it.path === root.current);
                    win.go(i >= 0 ? i : 0);
                }
            }

            // лёгкое затемнение сверху и снизу, чтобы карточки читались на любых обоях
            Rectangle {
                anchors.fill: parent
                opacity: win.enter
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.35) }
                    GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.12) }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.35) }
                }
            }

            // нажатие мимо карточек и панели — закрыть
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: root.hide()
                onWheel: w => {
                    if (root.view !== "carousel") return;
                    const dy = w.angleDelta.y !== 0 ? w.angleDelta.y : -w.angleDelta.x;
                    win.go(win.cur + (dy < 0 ? 1 : -1));
                }
            }

            // клавиатура: стрелки, Enter — поставить, Esc — закрыть, буквы — поиск
            Item {
                id: keys
                focus: true
                Keys.onPressed: e => {
                    switch (e.key) {
                    case Qt.Key_Escape: root.hide(); break;
                    case Qt.Key_Left: case Qt.Key_Up: case Qt.Key_Backtab: win.go(win.cur - 1); break;
                    case Qt.Key_Right: case Qt.Key_Down: case Qt.Key_Tab: win.go(win.cur + 1); break;
                    case Qt.Key_Home: win.go(0); break;
                    case Qt.Key_End: win.go(root.results.length - 1); break;
                    case Qt.Key_Return: case Qt.Key_Enter: WallStore.apply(root.results[win.cur]); break;
                    default:
                        if (e.text && e.text.trim().length && !(e.modifiers & Qt.ControlModifier)) {
                            bar.searching = true;
                            search.text = root.query + e.text;
                            search.focusInput();
                            break;
                        }
                        return;
                    }
                    e.accepted = true;
                }
            }

            // --- панель сверху: вид, недавние, видео, цвета, поиск, папка ---
            Rectangle {
                id: bar
                property bool searching: root.query.length > 0
                x: win.x0 + win.k * win.hMax * 0.15
                y: win.cy - win.hMax / 2 - height - 22 - (1 - win.enter) * 30
                opacity: win.enter
                width: barRow.implicitWidth + 16
                height: 48
                radius: 24
                color: Theme.glass2
                border.width: 1
                border.color: Theme.line
                Behavior on width { NumberAnimation { duration: 260 * Theme.anim.k; easing.type: Easing.OutCubic } }
                // нажатия по панели не закрывают выбор
                MouseArea { anchors.fill: parent }

                Row {
                    id: barRow
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    spacing: 6

                    BarBtn {
                        icon: root.view === "grid" ? "image" : "grid"
                        hint: root.view === "grid" ? "Лентой" : "Сеткой"
                        onClicked: Settings.set("wallpaper.pickerView", root.view === "grid" ? "carousel" : "grid")
                    }
                    BarBtn {
                        icon: "clock"; hint: "Сначала новые"
                        on: root.sort === "recent"
                        onClicked: root.sort = root.sort === "recent" ? "name" : "recent"
                    }
                    BarBtn {
                        icon: "play"; hint: "Только видео"
                        on: root.type === "video"
                        onClicked: root.type = root.type === "video" ? "all" : "video"
                    }

                    Item { width: 4; height: 1 }

                    Repeater {
                        model: WallStore.buckets
                        delegate: Item {
                            id: dot
                            required property var modelData
                            readonly property bool sel: root.tint === modelData.id
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34; height: 34
                            Rectangle {
                                anchors.centerIn: parent
                                width: 34; height: 34; radius: 17
                                color: "transparent"
                                border.width: 2
                                border.color: Theme.fg
                                opacity: dot.sel ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Theme.anim.fast } }
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 28; height: 28; radius: 14
                                color: dot.modelData.color
                                scale: dotHover.hovered ? 1.1 : dot.sel ? 0.86 : 1
                                Behavior on scale { NumberAnimation { duration: Theme.anim.fast; easing.type: Easing.OutBack } }
                            }
                            HoverHandler { id: dotHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.tint = dot.sel ? "all" : dot.modelData.id }
                        }
                    }

                    Item { width: 4; height: 1 }

                    Field {
                        id: search
                        anchors.verticalCenter: parent.verticalCenter
                        visible: bar.searching
                        width: 200
                        height: 34
                        radius: 17
                        fontSize: 13
                        placeholder: "Поиск обоев"
                        text: root.query
                        onTextChanged: if (root.query !== text) root.query = text
                        onAccepted: WallStore.apply(root.results[win.cur])
                        onKey: e => {
                            switch (e.key) {
                            case Qt.Key_Escape:
                                if (search.text.length) search.text = "";
                                else { bar.searching = false; keys.forceActiveFocus(); }
                                break;
                            case Qt.Key_Left: if (search.text.length) return; win.go(win.cur - 1); break;
                            case Qt.Key_Right: if (search.text.length) return; win.go(win.cur + 1); break;
                            case Qt.Key_Up: win.go(win.cur - 1); break;
                            case Qt.Key_Down: win.go(win.cur + 1); break;
                            default: return;
                            }
                            e.accepted = true;
                        }
                    }
                    BarBtn {
                        visible: !bar.searching
                        icon: "search"; hint: "Поиск"
                        onClicked: { bar.searching = true; search.focusInput(); }
                    }
                    BarBtn {
                        icon: "folder"; hint: "Папка: " + WallStore.pretty(WallStore.folder)
                        onClicked: root.chooseFolder()
                    }
                }
            }

            // путь к папке руками (нет zenity)
            Field {
                id: folderField
                visible: root.editFolder
                x: bar.x
                y: bar.y + bar.height + 10
                width: 420
                height: 36
                radius: 12
                fontSize: 13
                icon: "folder"
                placeholder: "Путь к папке с обоями"
                onAccepted: {
                    const p = text.trim();
                    if (p) Settings.set("wallpaper.folder", p);
                    root.editFolder = false;
                    keys.forceActiveFocus();
                }
                onKey: e => {
                    if (e.key === Qt.Key_Escape) { root.editFolder = false; keys.forceActiveFocus(); e.accepted = true; }
                }
            }

            // --- лента ---
            Item {
                id: strip
                anchors.fill: parent
                visible: root.view === "carousel"

                Repeater {
                    model: root.results
                    delegate: Item {
                        id: card
                        required property var modelData
                        required property int index
                        readonly property real d: index - win.pos
                        readonly property bool near: d > -1.6 && d < 11
                        readonly property bool focused: index === win.cur
                        readonly property bool selected: modelData.path === root.current
                        // выезд: дальние карточки чуть позже
                        readonly property real e: Math.max(0, Math.min(1, win.enter * 1.5 - Math.max(0, d) * 0.06))

                        visible: near && opacity > 0.01
                        width: win.wAt(d)
                        height: win.hAt(d)
                        x: win.xAt(d) + (1 - e) * win.width * 0.5
                        y: win.cy - height / 2
                        z: 1000 - index
                        opacity: (d < 0 ? Math.max(0, 1 + d * 1.25) : 1) * e
                        // скошенные края: верх сдвинут вправо
                        transform: Matrix4x4 {
                            matrix: Qt.matrix4x4(1, -win.k, 0, win.k * card.height, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }

                        ClippingRectangle {
                            anchors.fill: parent
                            radius: 24
                            color: Theme.soft2
                            border.width: card.selected ? 3 : 0
                            border.color: Theme.accent
                            contentUnderBorder: true

                            // содержимое прямое: обратный сдвиг, скошены только края
                            Item {
                                id: flat
                                width: card.width + win.k * card.height
                                height: card.height
                                transform: Matrix4x4 {
                                    matrix: Qt.matrix4x4(1, win.k, 0, -win.k * card.height, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                                }

                                Sym {
                                    anchors.centerIn: parent
                                    visible: thumb.status !== Image.Ready
                                    name: card.modelData.video ? "video" : "image"
                                    size: 28
                                    color: Theme.fg3
                                }
                                Image {
                                    id: thumb
                                    anchors.fill: parent
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectCrop
                                    sourceSize: Qt.size(384, 384)
                                    source: card.near && WallStore.thumbs[card.modelData.key] === true ? Media.fileUrl(card.modelData.thumb) : ""
                                }
                                // выбранная крупно — сам файл, а не миниатюра
                                Image {
                                    anchors.fill: parent
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectCrop
                                    sourceSize: Qt.size(1280, 1280)
                                    source: Math.abs(card.d) < 1.5 && !card.modelData.video ? Media.fileUrl(card.modelData.path) : ""
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Theme.anim.normal } }
                                }

                                // затемнение дальних — глубина
                                Rectangle {
                                    anchors.fill: parent
                                    color: "#000000"
                                    opacity: Math.min(0.35, Math.max(0, card.d) * 0.06) * (cardHover.hovered ? 0.3 : 1)
                                    Behavior on opacity { NumberAnimation { duration: Theme.anim.fast } }
                                }

                                // плашка «Видео» — в верхнем левом углу видимой части
                                Rectangle {
                                    visible: card.modelData.video
                                    x: win.k * card.height + 14; y: 14
                                    width: badge.implicitWidth + 16
                                    height: 22
                                    radius: 11
                                    color: Qt.rgba(0, 0, 0, 0.55)
                                    Row {
                                        id: badge
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Sym { name: "play"; size: 10; color: "#ffffff"; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: "Видео"; color: "#ffffff"; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold }
                                    }
                                }
                                // текущие обои — галочка
                                Rectangle {
                                    visible: card.selected
                                    x: win.k * card.height + card.width - width - 14; y: 14
                                    width: 26; height: 26; radius: 13
                                    color: Theme.accent
                                    Sym { anchors.centerIn: parent; name: "check"; size: 15; color: Theme.onAccent }
                                }
                            }
                        }

                        HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: win.pick(card.index) }
                    }
                }

                // имя выбранной под лентой
                Label {
                    x: win.x0
                    y: win.cy + win.hMax / 2 + 16
                    opacity: win.enter
                    visible: root.results.length > 0
                    text: root.results[win.cur]?.name ?? ""
                    color: "#ffffff"
                    font.weight: Font.DemiBold
                    width: win.wMax
                }
            }

            // --- сетка ---
            Rectangle {
                id: gridBox
                visible: root.view === "grid"
                x: win.x0
                y: bar.y + bar.height + 16
                width: win.width - 2 * win.x0
                height: Math.min(win.height - y - 40, win.hMax + 120)
                opacity: win.enter
                radius: 28
                color: Theme.glass2
                border.width: 1
                border.color: Theme.line
                MouseArea { anchors.fill: parent }

                GridView {
                    id: grid
                    anchors { fill: parent; margins: 18; rightMargin: 4 }
                    clip: true
                    model: root.view === "grid" ? root.results : []
                    readonly property int cols: Math.max(2, Math.floor(width / 220))
                    cellWidth: Math.floor(width / cols)
                    cellHeight: Math.round((cellWidth - 14) * 0.62) + 14
                    boundsBehavior: Flickable.StopAtBounds
                    reuseItems: true
                    currentIndex: win.cur
                    onCurrentIndexChanged: if (currentIndex !== win.cur && currentIndex >= 0) win.go(currentIndex)

                    delegate: Item {
                        id: cell
                        required property var modelData
                        required property int index
                        readonly property bool selected: modelData.path === root.current
                        width: grid.cellWidth
                        height: grid.cellHeight

                        ClippingRectangle {
                            width: cell.width - 14
                            height: cell.height - 14
                            radius: 18
                            color: Theme.soft2
                            border.width: cell.selected ? 3 : cell.index === win.cur ? 2 : 0
                            border.color: cell.selected ? Theme.accent : Theme.fg3
                            contentUnderBorder: true
                            y: gHover.hovered ? -3 : 0
                            Behavior on y { NumberAnimation { duration: Theme.anim.fast } }
                            Image {
                                anchors.fill: parent
                                asynchronous: true
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(384, 216)
                                source: WallStore.thumbs[cell.modelData.key] === true ? Media.fileUrl(cell.modelData.thumb) : ""
                            }
                            Sym {
                                visible: cell.modelData.video
                                x: 10; y: 10
                                name: "play"; size: 14; color: "#ffffff"
                            }
                        }
                        HoverHandler { id: gHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: win.pick(cell.index) }
                    }
                }
            }

            // пусто
            Column {
                x: win.x0 + 40
                y: win.cy - height / 2
                visible: root.results.length === 0
                opacity: win.enter
                spacing: 12
                Sym { name: WallStore.folderMissing ? "folder" : "image"; size: 36; color: "#ffffff" }
                Label {
                    color: "#ffffff"
                    font.weight: Font.DemiBold
                    text: WallStore.scanning && WallStore.items.length === 0 ? "Загрузка…"
                        : WallStore.folderMissing ? "Папка не найдена: " + WallStore.pretty(WallStore.folder)
                        : WallStore.items.length === 0 ? "В папке нет картинок и видео"
                        : "Ничего не найдено"
                }
                Btn {
                    visible: WallStore.folderMissing || (!WallStore.scanning && WallStore.items.length === 0)
                    icon: "folder"; text: "Выбрать папку"
                    onClicked: root.chooseFolder()
                }
            }
        }
    }
}
