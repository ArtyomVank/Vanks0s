pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.common
import qs.common.ui
import qs.settings.parts

// «Игры и программы Windows» (delta-exe --manager). Сверху — аккаунты
// магазинов (Steam, Epic Games, облачный Xbox) и библиотека игр из них с
// обложками: «Играть» или «Установить». Ниже — все префиксы лаунчера с их
// программами — установленными (ярлыки в меню) и просто запущенными, —
// раннер каждого префикса (Авто, версия Proton CachyOS или Wine), настройки
// Wine, папка C:, удаление. Внизу — что запускали обычно, Wine системы.
// Данные — delta-games status/library и delta-exe --list, действия — они же с ключами.
FloatingWindow {
    id: win

    property var db: ({ prefixes: [], normal: [], runners: { protons: [], wine: false, umu: false } })
    property bool loaded: false
    property string removing: ""          // префикс, который ждёт второго нажатия «Удалить»
    readonly property var protons: db.runners?.protons ?? []

    // аккаунты и библиотека игр
    property var accounts: ({ steam: { installed: false, running: false, user: "" }, epic: { ready: false, user: "", installing: [] }, xbox: { browser: "" } })
    property var games: []
    property bool gamesLoaded: false
    property string filter: "all"
    property bool epicLogin: false        // открыт ли шаг «вставьте код со страницы Epic»
    property string epicBusy: ""          // «готовлю вход» / «проверяю код»
    readonly property var shownGames: games.filter(g => filter === "all" || (filter === "installed" ? g.installed : g.store === filter))

    title: I18n.tr("Игры и программы Windows")
    implicitWidth: 1000
    implicitHeight: 720
    minimumSize: Qt.size(640, 520)
    color: "transparent"

    onClosed: Qt.quit()

    function reload() { lister.running = true; statusProc.running = true; libraryProc.running = true; }
    function run(cmd) { Sounds.play("oobe-step", 0); Quickshell.execDetached(cmd); }
    function runnerLabel(r) {
        if (r === "wine") return "Wine";
        if (r.startsWith("proton:")) return r.split("/").pop();
        return I18n.tr("Авто");
    }

    // --- аккаунты: раз в 4 с (вход в Steam идёт в его окне), библиотека — при смене ---
    Process {
        id: statusProc
        running: true
        command: ["delta-games", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let a;
                try { a = JSON.parse(text); } catch (e) { return; }
                const was = JSON.stringify([win.accounts.steam?.user, win.accounts.epic?.user, win.accounts.epic?.installing]);
                win.accounts = a;
                if (was !== JSON.stringify([a.steam?.user, a.epic?.user, a.epic?.installing])) libraryProc.running = true;
            }
        }
    }
    Timer { interval: 4000; repeat: true; running: win.visible; onTriggered: if (!statusProc.running) statusProc.running = true }
    Process {
        id: libraryProc
        running: true
        property bool refresh: false
        command: ["delta-games", "library"].concat(refresh ? ["--refresh"] : [])
        stdout: StdioCollector {
            onStreamFinished: {
                try { win.games = JSON.parse(text); } catch (e) {}
                win.gamesLoaded = true;
                libraryProc.refresh = false;
            }
        }
    }
    Process {
        id: gamesAct
        onExited: { win.epicBusy = ""; statusProc.running = true; libraryProc.running = true; }
    }
    function games_(args) { gamesAct.command = ["delta-games"].concat(args); gamesAct.running = true; }
    Process {
        id: clip
        command: ["wl-paste", "-n"]
        stdout: StdioCollector { onStreamFinished: codeField.text = text.trim() }
    }

    Process {
        id: lister
        running: true
        command: ["delta-exe", "--list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { win.db = JSON.parse(text); } catch (e) {}
                win.loaded = true;
            }
        }
    }
    Process {
        id: fetcher
        command: ["delta-exe", "--fetch"]
        onExited: win.reload()
    }
    Process {
        id: changer
        onExited: win.reload()
    }
    function change(cmd) { changer.command = cmd; changer.running = true; }

    // плитка магазина: значок, название, состояние входа и кнопки (вложенные элементы)
    component StoreTile: Rectangle {
        id: tile
        property string icon
        property string name
        property string note
        property bool ok: false
        default property alias actions: tileBtns.data
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        implicitHeight: tileCol.implicitHeight + 28
        radius: 20
        color: Theme.soft
        border.width: 1
        border.color: ok ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6) : Theme.line
        ColumnLayout {
            id: tileCol
            anchors { fill: parent; margins: 14 }
            spacing: 10
            RowLayout {
                spacing: 10
                Layout.fillWidth: true
                Rectangle {
                    implicitWidth: 38; implicitHeight: 38; radius: 12
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, tile.ok ? 0.28 : 0.14)
                    Sym { anchors.centerIn: parent; name: tile.icon; size: 20; color: Theme.accent }
                }
                Label { text: tile.name; size: "title"; Layout.fillWidth: true }
                Sym { visible: tile.ok; name: "check"; size: 18; color: Theme.accent }
            }
            Label {
                text: tile.note
                Layout.fillWidth: true
                Layout.fillHeight: true
                verticalAlignment: Text.AlignTop
                wrapMode: Text.WordWrap
                tone: 3; size: "small"
            }
            RowLayout { id: tileBtns; spacing: 8 }
        }
    }

    // карточка игры: обложка, название, магазин и «Играть» / «Установить»
    component GameCard: Item {
        id: game
        required property var modelData
        readonly property string cover: modelData.cover ?? ""
        readonly property bool busy: modelData.installing === true
        signal act(var m)
        width: 150
        height: gameCol.implicitHeight
        Column {
            id: gameCol
            width: parent.width
            spacing: 8
            ClippingRectangle {
                width: parent.width
                height: 225
                radius: 14
                color: Theme.soft2
                Sym {
                    anchors.centerIn: parent
                    visible: art.status !== Image.Ready
                    name: "gamepad"; size: 40; color: Theme.fg3
                }
                Image {
                    id: art
                    anchors.fill: parent
                    source: game.cover.startsWith("/") ? "file://" + game.cover : game.cover
                    sourceSize: Qt.size(300, 450)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: game.modelData.installed ? 1 : 0.55
                }
                // какой магазин
                Rectangle {
                    anchors { left: parent.left; top: parent.top; margins: 8 }
                    implicitWidth: storeName.implicitWidth + 14
                    implicitHeight: 22
                    radius: 11
                    color: Qt.rgba(0, 0, 0, 0.55)
                    Label {
                        id: storeName
                        anchors.centerIn: parent
                        text: game.modelData.store === "epic" ? "Epic" : "Steam"
                        size: "caption"
                        color: "white"
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onDoubleClicked: gameBtn.clicked()
                }
            }
            Label {
                width: parent.width
                text: game.modelData.title
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WordWrap
                height: 36
                size: "small"
            }
            Btn {
                id: gameBtn
                width: parent.width
                text: game.busy ? I18n.tr("Ставится…") : game.modelData.installed ? I18n.tr("Играть") : I18n.tr("Установить")
                icon: game.modelData.installed ? "play" : "download"
                kind: game.modelData.installed ? "accent" : "soft"
                enabled: !game.busy
                onClicked: if (enabled) game.act(game.modelData)
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
                    Sym { anchors.centerIn: parent; name: "windows"; size: 26; color: Theme.accent }
                }
                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true
                    Label { text: I18n.tr("Игры и программы Windows"); size: "h1"; Layout.fillWidth: true }
                    Label {
                        text: I18n.tr("Аккаунты магазинов и ваши игры, а ниже — всё, что ставили и запускали через лаунчер")
                        tone: 3; size: "small"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                }
                Btn { icon: "refresh"; kind: "ghost"; onClicked: { libraryProc.refresh = true; win.reload(); } }
            }

            // --- всё листается ---
            Flickable {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: cards.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: cards
                    width: list.width
                    spacing: 12

                    // --- аккаунты магазинов ---
                    Label { text: I18n.tr("Аккаунты"); size: "title"; Layout.fillWidth: true }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        StoreTile {
                            icon: "gamepad"
                            name: "Steam"
                            ok: win.accounts.steam?.user ? true : false
                            note: !win.accounts.steam?.installed ? I18n.tr("Steam не установлен")
                                : win.accounts.steam?.user ? I18n.tr("Вы вошли как") + " " + win.accounts.steam.user
                                : I18n.tr("Войдите в окне Steam — игры появятся ниже")
                            Btn {
                                text: !win.accounts.steam?.installed ? I18n.tr("Поставить")
                                    : win.accounts.steam?.user ? I18n.tr("Открыть Steam") : I18n.tr("Войти")
                                icon: win.accounts.steam?.installed ? "user" : "download"
                                kind: win.accounts.steam?.user ? "soft" : "accent"
                                onClicked: win.accounts.steam?.installed ? win.run(["delta-games", "login", "steam"])
                                    : Quickshell.execDetached(["pkexec", "delta-setup", "install", "steam"])
                            }
                        }

                        StoreTile {
                            icon: "store"
                            name: "Epic Games"
                            ok: win.accounts.epic?.ready ? true : false
                            note: win.epicBusy === "setup" ? I18n.tr("Готовлю вход — первый раз около минуты…")
                                : win.epicBusy === "code" ? I18n.tr("Проверяю код…")
                                : win.accounts.epic?.ready ? I18n.tr("Вы вошли как") + " " + (win.accounts.epic.user || "Epic")
                                : I18n.tr("Вход через сайт Epic — игры запускаются с вашим аккаунтом")
                            Btn {
                                visible: !win.accounts.epic?.ready
                                text: I18n.tr("Войти")
                                icon: "user"
                                kind: "accent"
                                enabled: win.epicBusy === ""
                                onClicked: { win.epicLogin = true; win.epicBusy = "setup"; win.games_(["login", "epic"]); }
                            }
                            Btn {
                                visible: win.accounts.epic?.ready ? true : false
                                text: I18n.tr("Выйти")
                                icon: "logout"
                                kind: "ghost"
                                enabled: win.epicBusy === ""
                                onClicked: win.games_(["logout", "epic"])
                            }
                        }

                        StoreTile {
                            icon: "cloud"
                            name: "Xbox"
                            ok: false
                            note: I18n.tr("Игры Microsoft Store в Linux не запускаются — играйте в облаке Xbox Cloud Gaming (нужен Game Pass)")
                            Btn {
                                text: I18n.tr("Облачные игры")
                                icon: "cloud"
                                enabled: (win.accounts.xbox?.browser ?? "") !== ""
                                onClicked: win.run(["delta-games", "xbox"])
                            }
                        }
                    }

                    // вход в Epic: сайт показывает код — его надо вставить сюда
                    Rectangle {
                        visible: win.epicLogin && !win.accounts.epic?.ready
                        Layout.fillWidth: true
                        implicitHeight: epicCol.implicitHeight + 28
                        radius: 20
                        color: Theme.soft
                        border.width: 1
                        border.color: Theme.accent
                        ColumnLayout {
                            id: epicCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                            spacing: 10
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                size: "small"
                                text: I18n.tr("В браузере откроется вход Epic Games. После входа страница покажет код (authorizationCode) — скопируйте его или весь текст страницы и вставьте сюда")
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                Field {
                                    id: codeField
                                    Layout.fillWidth: true
                                    icon: "user"
                                    placeholder: I18n.tr("Код со страницы Epic")
                                    clearable: true
                                    onAccepted: epicOk.clicked()
                                }
                                Btn { text: I18n.tr("Вставить"); kind: "ghost"; onClicked: clip.running = true }
                                Btn {
                                    id: epicOk
                                    text: I18n.tr("Войти")
                                    kind: "accent"
                                    enabled: codeField.text.trim().length > 0 && win.epicBusy === ""
                                    onClicked: {
                                        if (!enabled) return;
                                        win.epicBusy = "code";
                                        win.games_(["epic-code", codeField.text.trim()]);
                                        codeField.text = "";
                                    }
                                }
                                Btn { icon: "close"; kind: "ghost"; onClicked: win.epicLogin = false }
                            }
                            Btn {
                                text: I18n.tr("Открыть страницу входа ещё раз")
                                kind: "ghost"
                                enabled: win.epicBusy === ""
                                onClicked: win.games_(["login", "epic"])
                            }
                        }
                    }

                    // --- библиотека ---
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        spacing: 12
                        Label { text: I18n.tr("Библиотека"); size: "title"; Layout.fillWidth: true }
                        Chips {
                            model: [
                                { value: "all", label: I18n.tr("Все") },
                                { value: "installed", label: I18n.tr("Установленные") },
                                { value: "steam", label: "Steam" },
                                { value: "epic", label: "Epic" }
                            ]
                            current: win.filter
                            onPicked: v => win.filter = v
                        }
                    }
                    Label {
                        visible: win.gamesLoaded && win.shownGames.length === 0
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        tone: 3
                        text: win.games.length === 0 ? I18n.tr("Войдите в Steam или Epic Games — здесь появятся игры из вашей библиотеки")
                            : I18n.tr("Здесь пока нет игр")
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 14
                        Repeater {
                            model: win.shownGames
                            delegate: GameCard {
                                onAct: m => {
                                    win.run(["delta-games", m.installed ? "play" : "install", m.store, String(m.id)]);
                                    if (!m.installed && m.store === "epic") statusProc.running = true;
                                }
                            }
                        }
                    }

                    // --- программы: Proton и префиксы ---
                    Label { text: I18n.tr("Программы"); size: "title"; Layout.fillWidth: true; Layout.topMargin: 6 }
                        // --- Proton CachyOS ---
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: protonCol.implicitHeight + 28
                            radius: 20
                            color: Theme.soft
                            border.width: 1
                            border.color: Theme.line
                            ColumnLayout {
                                id: protonCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                                spacing: 8
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Sym { name: "rocket"; size: 20; color: Theme.fg2 }
                                    ColumnLayout {
                                        spacing: 1
                                        Layout.fillWidth: true
                                        Label { text: "Proton CachyOS"; font.weight: Font.DemiBold }
                                        Label {
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                            tone: 3; size: "small"
                                            text: fetcher.running ? I18n.tr("Скачивается последняя версия…")
                                                : win.protons.length > 0 ? I18n.tr("Скачано:") + " " + win.protons.map(p => p.name).join(", ")
                                                : I18n.tr("Ещё не скачан — скачается при первом запуске (около 500 МБ)")
                                        }
                                    }
                                    Btn {
                                        text: I18n.tr("Скачать последний")
                                        icon: "download"
                                        enabled: !fetcher.running
                                        onClicked: { fetcher.running = true; Sounds.play("pop", 60); }
                                    }
                                }
                                RowLayout {
                                    visible: win.loaded && !win.db.runners?.umu
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Label {
                                        text: I18n.tr("Без umu-launcher Proton запустится напрямую — с ним совместимость лучше")
                                        tone: 3; size: "small"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                                    }
                                    Btn {
                                        text: I18n.tr("Поставить")
                                        icon: "download"
                                        onClicked: Quickshell.execDetached(["pkexec", "delta-setup", "install", "umu-launcher"])
                                    }
                                }
                            }
                        }

                    Label {
                        visible: win.loaded && win.db.prefixes.length === 0 && win.db.normal.length === 0
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        tone: 3
                        text: I18n.tr("Пока пусто. Откройте файл .exe или .msi и выберите «Через лаунчер» — программа появится здесь")
                    }

                    Repeater {
                        model: win.db.prefixes
                        delegate: Rectangle {
                            id: card
                            required property var modelData
                            readonly property string name: modelData.name
                            Layout.fillWidth: true
                            implicitHeight: cardCol.implicitHeight + 28
                            radius: 20
                            color: Theme.soft
                            border.width: 1
                            border.color: Theme.line

                            ColumnLayout {
                                id: cardCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Sym { name: "folder"; size: 20; color: Theme.accent }
                                    Label { text: card.name; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Label { text: card.modelData.size; tone: 3; size: "small"; visible: text !== "0" }
                                    Btn { icon: "folder"; kind: "ghost"; enabled: card.modelData.ready; onClicked: win.run(["delta-exe", "--folder", card.name]) }
                                    Btn { icon: "settings"; kind: "ghost"; onClicked: win.run(["delta-exe", "--winecfg", card.name]) }
                                    Btn {
                                        icon: "trash"
                                        text: win.removing === card.name ? I18n.tr("Точно удалить?") : ""
                                        kind: "danger"
                                        onClicked: {
                                            if (win.removing !== card.name) { win.removing = card.name; return; }
                                            win.removing = "";
                                            win.change(["delta-exe", "--remove", card.name]);
                                        }
                                    }
                                }

                                // чем запускать программы этого префикса
                                Chips {
                                    Layout.fillWidth: true
                                    model: [{ value: "auto", label: I18n.tr("Авто") }]
                                        .concat(win.protons.map(p => ({ value: "proton:" + p.path, label: p.name })))
                                        .concat(win.db.runners?.wine ? [{ value: "wine", label: "Wine" }] : [])
                                    current: card.modelData.runner
                                    onPicked: v => { win.change(["delta-exe", "--set-runner", card.name, v]); Sounds.play("oobe-select", 60); }
                                }

                                Label {
                                    visible: card.modelData.apps.length === 0
                                    text: I18n.tr("Программ не нашлось — запустите её .exe через лаунчер ещё раз")
                                    tone: 3; size: "small"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                                }
                                Repeater {
                                    model: card.modelData.apps
                                    delegate: AppRow {
                                        onLaunch: exe => win.run(["delta-exe", "--app", card.name, exe])
                                    }
                                }
                            }
                        }
                    }

                    // --- обычно (Wine системы) ---
                    Rectangle {
                        visible: win.db.normal.length > 0
                        Layout.fillWidth: true
                        implicitHeight: normalCol.implicitHeight + 28
                        radius: 20
                        color: Theme.soft
                        border.width: 1
                        border.color: Theme.line
                        ColumnLayout {
                            id: normalCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                            spacing: 10
                            RowLayout {
                                spacing: 10
                                Sym { name: "file"; size: 20; color: Theme.fg2 }
                                Label { text: I18n.tr("Открывали обычно (Wine системы)"); font.weight: Font.DemiBold }
                            }
                            Repeater {
                                model: win.db.normal
                                delegate: AppRow {
                                    onLaunch: exe => win.run(["delta-exe", "--run", "normal", exe])
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // программа: значок, название, путь, «Запустить»
    component AppRow: RowLayout {
        id: row
        required property var modelData
        signal launch(string exe)
        Layout.fillWidth: true
        spacing: 12
        Item {
            implicitWidth: 28; implicitHeight: 28
            // значок из exe или темы, а нет его — «окно Windows»
            readonly property string src: row.modelData.icon.startsWith("/") ? "file://" + row.modelData.icon
                : row.modelData.icon ? Quickshell.iconPath(row.modelData.icon, true) : ""
            IconImage { id: appIcon; anchors.fill: parent; source: parent.src; visible: parent.src !== "" && status === Image.Ready }
            Sym { anchors.centerIn: parent; name: "windows"; size: 22; color: Theme.fg2; visible: !appIcon.visible }
        }
        ColumnLayout {
            spacing: 0
            Layout.fillWidth: true
            Label { text: row.modelData.title; elide: Text.ElideRight; Layout.fillWidth: true }
            Label { text: row.modelData.exe; tone: 3; size: "small"; font.family: Theme.fontMono; elide: Text.ElideMiddle; Layout.fillWidth: true }
        }
        Btn { text: I18n.tr("Запустить"); icon: "play"; onClicked: row.launch(row.modelData.exe) }
    }

    Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
    Shortcut { sequence: "F5"; onActivated: win.reload() }
}
