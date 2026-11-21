pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.common
import qs.common.ui
import qs.settings.parts

// Delta Play (delta-play): все игры в одном окне.
//   Steam и Epic   — delta-games library (купленные и установленные), запуск
//                    и установка — delta-games play|install;
//   Windows        — программы, поставленные через delta-exe (ярлыки Categories=Wine);
//   Linux          — ярлыки меню с Categories=Game (кроме клиентов Steam и
//                    ярлыков steam://rungameid — эти игры уже есть из Steam).
// Сверху — «Недавние» (play.recent: ключи игр, последние запущенные отсюда),
// дальше фильтр, поиск и сетка обложек. Правый щелчок по игре — скрыть её
// (play.hidden), «Показать скрытые» — вернуть.
FloatingWindow {
    id: win

    property var store: []                // Steam и Epic
    property bool storeLoaded: false
    property string filter: "all"
    property string query: ""
    property bool showHidden: false

    readonly property var hidden: Settings.get("play.hidden", []) || []
    readonly property var recent: Settings.get("play.recent", []) || []

    title: "Delta Play"
    implicitWidth: 1120
    implicitHeight: 740
    minimumSize: Qt.size(680, 520)
    color: "transparent"

    onClosed: Qt.quit()

    // клиенты магазинов — не игры (их игры приходят из delta-games или своими ярлыками)
    readonly property var launchers: /(^|\.)(steam|delta-play|heroic.*|lutris|itch|bottles|minigalaxy|gamehub)$/i
    // ярлыки меню: игры Linux и программы Windows
    readonly property var entries: {
        const out = [];
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay) continue;
            const cats = e.categories || [];
            const cmd = (e.command || []).join(" ");
            let kind = "";
            if (cats.indexOf("Wine") !== -1 && cmd.indexOf("delta-exe") !== -1) kind = "windows";
            else if (cats.indexOf("Game") !== -1 && !/steam:\/\/rungameid/.test(cmd)
                     && !launchers.test(e.id)) kind = "linux";
            if (!kind) continue;
            out.push({ store: kind, id: e.id, title: e.name || e.id, installed: true, entry: e,
                       icon: e.icon ? Quickshell.iconPath(e.icon, true) : "" });
        }
        return out;
    }
    function keyOf(g) { return g.store + ":" + g.id; }
    readonly property var all: {
        const list = store.concat(entries);
        list.sort((a, b) => (!a.installed - !b.installed) || a.title.localeCompare(b.title));
        return list;
    }
    readonly property var shown: {
        const q = query.trim().toLowerCase();
        return all.filter(g => (showHidden || hidden.indexOf(keyOf(g)) === -1)
            && (filter === "all" || (filter === "installed" ? g.installed : g.store === filter))
            && (!q || g.title.toLowerCase().indexOf(q) !== -1));
    }
    readonly property var recentGames: {
        const out = [];
        for (const k of recent) {
            const g = all.find(x => keyOf(x) === k);
            if (g && g.installed && hidden.indexOf(k) === -1) out.push(g);
            if (out.length >= 5) break;
        }
        return out;
    }
    function count(f) { return all.filter(g => hidden.indexOf(keyOf(g)) === -1 && (f === "installed" ? g.installed : g.store === f)).length; }

    function play(g) {
        Sounds.play("oobe-step", 0);
        if (g.entry) g.entry.execute();
        else Quickshell.execDetached(["delta-games", g.installed ? "play" : "install", g.store, String(g.id)]);
        if (!g.installed) return;
        const k = keyOf(g);
        Settings.set("play.recent", [k].concat(recent.filter(x => x !== k)).slice(0, 12));
    }
    function toggleHidden(g) {
        const k = keyOf(g);
        Settings.set("play.hidden", hidden.indexOf(k) === -1 ? hidden.concat([k]) : hidden.filter(x => x !== k));
    }

    Process {
        id: libraryProc
        running: true
        property bool refresh: false
        command: ["delta-games", "library"].concat(refresh ? ["--refresh"] : [])
        stdout: StdioCollector {
            onStreamFinished: {
                try { win.store = JSON.parse(text); } catch (e) {}
                win.storeLoaded = true;
                libraryProc.refresh = false;
            }
        }
    }
    // установка в Steam и Epic идёт в фоне — список перечитываем, пока окно открыто
    Timer {
        interval: 6000; repeat: true; running: win.visible && win.store.some(g => g.installing === true)
        onTriggered: if (!libraryProc.running) libraryProc.running = true
    }

    readonly property var storeNames: ({ steam: "Steam", epic: "Epic", windows: "Windows", linux: "Linux" })

    // обложка игры: картинка магазина или значок ярлыка на цветной подложке
    component Cover: ClippingRectangle {
        id: cv
        property var game
        radius: 14
        color: Theme.soft2
        readonly property string art: game?.cover ?? ""
        Rectangle {
            anchors.fill: parent
            visible: cv.art === ""
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.34) }
                GradientStop { position: 1; color: Theme.soft2 }
            }
        }
        Sym {
            anchors.centerIn: parent
            visible: img.status !== Image.Ready && ico.status !== Image.Ready
            name: "gamepad"; size: 40; color: Theme.fg3
        }
        Image {
            id: img
            anchors.fill: parent
            visible: cv.art !== ""
            source: cv.art.startsWith("/") ? "file://" + cv.art : cv.art
            sourceSize: Qt.size(300, 450)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            opacity: cv.game?.installed ? 1 : 0.55
        }
        IconImage {
            id: ico
            anchors.centerIn: parent
            visible: cv.art === "" && (cv.game?.icon ?? "") !== ""
            implicitSize: Math.min(parent.width, parent.height) * 0.42
            source: cv.game?.icon ?? ""
            asynchronous: true
        }
        // магазин
        Rectangle {
            anchors { left: parent.left; top: parent.top; margins: 8 }
            implicitWidth: storeLbl.implicitWidth + 14
            implicitHeight: 22
            radius: 11
            color: Qt.rgba(0, 0, 0, 0.55)
            Label { id: storeLbl; anchors.centerIn: parent; text: win.storeNames[cv.game?.store] ?? ""; size: "caption"; color: "white" }
        }
    }

    // карточка в сетке
    component GameCard: Item {
        id: card
        required property var modelData
        readonly property bool busy: modelData.installing === true
        readonly property bool isHidden: win.hidden.indexOf(win.keyOf(modelData)) !== -1
        width: 150
        height: col.implicitHeight
        opacity: isHidden ? 0.45 : 1
        Column {
            id: col
            width: parent.width
            spacing: 8
            Cover {
                width: parent.width
                height: 225
                game: card.modelData
                scale: coverHov.hovered ? 1.03 : 1
                Behavior on scale { NumberAnimation { duration: Theme.anim.fast; easing.type: Easing.OutCubic } }
                HoverHandler { id: coverHov; cursorShape: Qt.PointingHandCursor }
                TapHandler { acceptedButtons: Qt.LeftButton; onDoubleTapped: win.play(card.modelData) }
                TapHandler { acceptedButtons: Qt.RightButton; onTapped: win.toggleHidden(card.modelData) }
            }
            Label {
                width: parent.width
                text: card.modelData.title
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WordWrap
                height: 36
                size: "small"
            }
            Btn {
                width: parent.width
                text: card.isHidden ? I18n.tr("Вернуть") : card.busy ? I18n.tr("Ставится…") : card.modelData.installed ? I18n.tr("Играть") : I18n.tr("Установить")
                icon: card.isHidden ? "eye" : card.modelData.installed ? "play" : "download"
                kind: !card.isHidden && card.modelData.installed ? "accent" : "soft"
                enabled: !card.busy
                onClicked: card.isHidden ? win.toggleHidden(card.modelData) : win.play(card.modelData)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.glass2
        border.width: 1
        border.color: Theme.line

        ColumnLayout {
            anchors { fill: parent; margins: 26 }
            spacing: 16

            // --- заголовок ---
            RowLayout {
                spacing: 14
                Layout.fillWidth: true
                Rectangle {
                    implicitWidth: 52; implicitHeight: 52; radius: 16
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2)
                    Sym { anchors.centerIn: parent; name: "gamepad"; size: 26; color: Theme.accent }
                }
                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true
                    Label { text: "Delta Play"; size: "h1"; Layout.fillWidth: true }
                    Label {
                        text: I18n.tr("Игры Steam, Epic, Windows и Linux в одном месте. Во время игры Super+G — игровая панель")
                        tone: 3; size: "small"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                }
                Field {
                    Layout.preferredWidth: 260
                    icon: "search"
                    placeholder: I18n.tr("Найти игру")
                    clearable: true
                    onTextChanged: win.query = text
                }
                Btn { icon: "refresh"; kind: "ghost"; onClicked: { libraryProc.refresh = true; libraryProc.running = true; } }
                Btn { icon: "settings"; kind: "ghost"; onClicked: Quickshell.execDetached(["delta-settings", "play"]) }
            }

            Flickable {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: body.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: body
                    width: list.width
                    spacing: 16

                    // --- недавние: широкие карточки ---
                    Label {
                        visible: rec.count > 0
                        text: I18n.tr("Недавние"); size: "title"
                    }
                    Row {
                        visible: rec.count > 0
                        spacing: 14
                        Repeater {
                            id: rec
                            model: win.filter === "all" && win.query === "" ? win.recentGames : []
                            delegate: Rectangle {
                                id: rc
                                required property var modelData
                                required property int index
                                width: index === 0 ? 300 : 200
                                height: 150
                                radius: 18
                                color: Theme.soft
                                border.width: 1
                                border.color: rcHov.hovered ? Theme.accent : Theme.line
                                Behavior on border.color { ColorAnimation { duration: Theme.anim.fast } }
                                Cover {
                                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 10 }
                                    width: (height - 0) * 2 / 3
                                    game: rc.modelData
                                }
                                ColumnLayout {
                                    anchors { left: parent.left; leftMargin: (rc.height - 20) * 2 / 3 + 22; right: parent.right; rightMargin: 14
                                              top: parent.top; bottom: parent.bottom; topMargin: 14; bottomMargin: 14 }
                                    spacing: 4
                                    Label { Layout.fillWidth: true; text: rc.modelData.title; font.weight: Font.Bold; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight }
                                    Label { text: win.storeNames[rc.modelData.store] ?? ""; size: "caption"; tone: 3 }
                                    Item { Layout.fillHeight: true }
                                    Btn { text: rc.index === 0 ? I18n.tr("Продолжить") : ""; icon: "play"; kind: "accent"; onClicked: win.play(rc.modelData) }
                                }
                                HoverHandler { id: rcHov }
                            }
                        }
                    }

                    Label { text: I18n.tr("Библиотека"); size: "title"; Layout.topMargin: rec.count > 0 ? 6 : 0 }
                    Chips {
                        Layout.fillWidth: true
                        model: [{ value: "all", label: I18n.tr("Все") }, { value: "installed", label: I18n.tr("Установленные") }]
                            .concat(["steam", "epic", "windows", "linux"].filter(s => win.count(s) > 0)
                                    .map(s => ({ value: s, label: win.storeNames[s] + " · " + win.count(s) })))
                        current: win.filter
                        onPicked: v => win.filter = v
                    }
                    Label {
                        visible: win.storeLoaded && win.shown.length === 0
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        tone: 3
                        text: win.query !== "" ? I18n.tr("Ничего не нашлось")
                            : win.all.length === 0 ? I18n.tr("Войдите в Steam или Epic Games в «Программах Windows», поставьте игру Windows или Linux — она появится здесь")
                            : I18n.tr("Здесь пока нет игр")
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 14
                        Repeater {
                            model: win.shown
                            delegate: GameCard {}
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: win.hidden.length > 0
                        Label { text: I18n.tr("Правый щелчок по обложке — скрыть игру"); size: "caption"; tone: 3; Layout.fillWidth: true }
                        Btn {
                            kind: "ghost"
                            icon: win.showHidden ? "eye-off" : "eye"
                            text: win.showHidden ? I18n.tr("Спрятать скрытые") : I18n.tr("Показать скрытые") + " · " + win.hidden.length
                            onClicked: win.showHidden = !win.showHidden
                        }
                    }
                }
            }
        }
    }
}
