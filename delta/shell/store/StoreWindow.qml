pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.common
import qs.common.ui
import qs.settings.parts
import "Featured.js" as Featured

// Магазин Delta (delta-store): пакеты Arch и Flathub в одном окне. Слева —
// поиск и разделы, справа — подборка (Featured.js), результаты поиска,
// установленные или страница приложения с выбором источника. Установки идут
// по очереди, внизу — что ставится сейчас. Данные и действия — delta-store.
FloatingWindow {
    id: win

    property string page: "home"          // home · section · search · installed · app
    property string sectionId: ""
    property string query: ""
    property var results: []
    property bool searching: false
    property var status: ({ pacman: {}, flatpak: {}, flathub: true, hasFlatpak: true })
    property var meta: ({})               // Flathub: id → значок, названия, описания
    property var installedList: []
    property bool installedLoaded: false
    property var app: null                // открытое приложение: { title, text, pkg, fp, icon }
    property string appSource: ""         // pacman · flatpak
    property var info: null               // delta-store info выбранного источника
    property string backTo: "home"

    // очередь установок и удалений
    property var queue: []                // [{ action, source, id, title }]
    property var job: null
    property string jobStep: ""
    property string jobLine: ""
    property string toast: ""
    property bool toastError: false

    readonly property var section: Featured.sections.find(s => s.id === sectionId) ?? null
    // карточки подборки — во всю ширину: столько в ряд, сколько влезет по 250
    readonly property int cardCols: Math.max(1, Math.floor((pageCol.width + 12) / 262))
    readonly property int cardWidth: Math.floor((pageCol.width - 12 * (cardCols - 1)) / cardCols)

    title: I18n.tr("Магазин")
    implicitWidth: 1120
    implicitHeight: 760
    minimumSize: Qt.size(760, 540)
    color: "transparent"

    onClosed: Qt.quit()

    // --- приложение: название, описание, значок, что стоит ---
    function titleOf(e) {
        const m = e.fp ? meta[e.fp] : null;
        if (e.title) return I18n.tr(e.title);
        if (m) return (!I18n.en && m.nameRu) ? m.nameRu : m.name;
        return e.pkg || e.fp || "";
    }
    function textOf(e) {
        if (e.text) return I18n.tr(e.text);
        const m = e.fp ? meta[e.fp] : null;
        if (m) return (!I18n.en && m.summaryRu) ? m.summaryRu : m.summary;
        return "";
    }
    function iconOf(e) {
        if (e.icon && e.icon.startsWith("/")) return "file://" + e.icon;
        const m = e.fp ? meta[e.fp] : null;
        if (m && m.icon) return "file://" + m.icon;
        const name = e.icon || e.pkg || "";
        return name ? Quickshell.iconPath(name, true) : "";
    }
    function installedIn(e, src) { return src === "pacman" ? !!(e.pkg && status.pacman[e.pkg]) : !!(e.fp && status.flatpak[e.fp]); }
    function installedAny(e) { return installedIn(e, "pacman") || installedIn(e, "flatpak"); }
    function sourceOf(e) {
        // уже стоит — тот источник; иначе Arch, если есть пакет
        if (installedIn(e, "pacman")) return "pacman";
        if (installedIn(e, "flatpak")) return "flatpak";
        return e.pkg ? "pacman" : "flatpak";
    }
    function idIn(e, src) { return src === "pacman" ? e.pkg : e.fp; }
    function busyWith(e) {
        const all = (job ? [job] : []).concat(queue);
        return all.find(j => (j.source === "pacman" && j.id === e.pkg) || (j.source === "flatpak" && j.id === e.fp)) ?? null;
    }
    // результат поиска или строка «Установленных» → приложение
    function fromRow(r) {
        return { title: (!I18n.en && r.nameRu) ? r.nameRu : r.name, text: (!I18n.en && r.summaryRu) ? r.summaryRu : (r.summary ?? ""),
                 pkg: r.source === "pacman" ? r.id : "", fp: r.source === "flatpak" ? r.id : (r.fp ?? ""), icon: r.icon ?? "", desktop: r.desktop ?? "" };
    }

    function openApp(e) {
        if (page !== "app") backTo = page;
        app = e;
        appSource = sourceOf(e);
        loadInfo();
        page = "app";
        content.contentY = 0;
    }
    function loadInfo() {
        info = null;
        const id = idIn(app, appSource);
        if (!id) return;
        infoProc.command = ["delta-store", "info", appSource, id];
        infoProc.running = true;
    }
    function go(p, sec) {
        page = p;
        sectionId = sec ?? "";
        content.contentY = 0;
        if (p === "installed") installedProc.running = true;
    }

    function enqueue(action, e, src) {
        const id = idIn(e, src);
        if (!id || busyWith(e)) return;
        Sounds.play("oobe-select", 60);
        queue = queue.concat([{ action: action, source: src, id: id, title: titleOf(e) }]);
        next();
    }
    function next() {
        if (job || queue.length === 0) return;
        job = queue[0];
        queue = queue.slice(1);
        jobStep = job.action === "connect" ? I18n.tr("Подключаю Flathub")
            : job.action === "remove" ? I18n.tr("Ждём пароль администратора") : I18n.tr("Готовлю установку");
        jobLine = "";
        jobProc.command = job.action === "connect" ? ["delta-store", "connect"] : ["delta-store", job.action, job.source, job.id];
        jobProc.running = true;
    }
    function launch(e, src) {
        Sounds.play("oobe-step", 0);
        if (src === "flatpak") { Quickshell.execDetached(["flatpak", "run", e.fp]); return; }
        const d = e.desktop || (info && info.source === "pacman" ? info.desktop : "");
        const entry = (d ? DesktopEntries.byId(d) : null) ?? DesktopEntries.heuristicLookup(e.pkg);
        if (entry) entry.execute();
        else showToast(I18n.tr("У программы нет ярлыка — запустите её из терминала"), true);
    }
    function showToast(t, err) { toast = t; toastError = !!err; toastTimer.restart(); }

    // --- процессы ---
    Process {
        id: statusProc
        running: true
        command: ["delta-store", "status"]
        stdout: StdioCollector { onStreamFinished: { try { win.status = JSON.parse(text); } catch (e) {} } }
    }
    Process {
        id: metaProc
        running: true
        command: ["delta-store", "lookup"].concat(Featured.allFlatpaks())
        stdout: StdioCollector { onStreamFinished: { try { win.meta = JSON.parse(text); } catch (e) {} } }
    }
    Process {
        id: searchProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { win.results = JSON.parse(text); } catch (e) { win.results = []; }
                win.searching = false;
            }
        }
    }
    Timer {
        id: searchDelay
        interval: 300
        onTriggered: {
            if (win.query.trim().length < 2) { win.results = []; win.searching = false; return; }
            searchProc.running = false;
            searchProc.command = ["delta-store", "search", win.query.trim()];
            searchProc.running = true;
        }
    }
    onQueryChanged: {
        if (query.trim().length === 0) { if (page === "search") go("home"); return; }
        if (page !== "search") go("search");
        searching = true;
        searchDelay.restart();
    }
    Process {
        id: installedProc
        command: ["delta-store", "installed"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { win.installedList = JSON.parse(text); } catch (e) {}
                win.installedLoaded = true;
            }
        }
    }
    Process {
        id: infoProc
        stdout: StdioCollector {
            onStreamFinished: {
                let r = null;
                try { r = JSON.parse(text); } catch (e) {}
                if (r && win.app && r.id === win.idIn(win.app, win.appSource)) win.info = r;
            }
        }
    }
    Process {
        id: jobProc
        property string errText: ""
        onStarted: errText = ""
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("::step:: ")) win.jobStep = line.slice(9);
                else if (line === "::reboot::") {}
                else if (line.trim().length) win.jobLine = line.trim();
            }
        }
        stderr: SplitParser { onRead: line => { if (line.trim().length) jobProc.errText = line.trim(); } }
        onExited: code => {
            const j = win.job;
            win.job = null;
            if (code === 0) {
                win.showToast(j.action === "connect" ? I18n.tr("Flathub подключён")
                    : j.action === "remove" ? j.title + " — " + I18n.tr("удалено") : j.title + " — " + I18n.tr("установлено"), false);
                Sounds.play(j.action === "remove" ? "oobe-step" : "oobe-done", 0);
                if (j.action === "connect") metaProc.running = true;
            } else if (code === 126 || code === 127) {
                win.showToast(I18n.tr("Отменено"), true);
            } else {
                win.showToast((jobProc.errText || win.jobLine || I18n.tr("Не получилось")), true);
            }
            statusProc.running = true;
            if (win.page === "installed") installedProc.running = true;
            if (win.page === "app") win.loadInfo();
            win.next();
        }
    }
    Timer { id: toastTimer; interval: 4500; onTriggered: win.toast = "" }

    // --- части ---
    // значок приложения: свой, из Flathub или темы; нет — «магазин»
    component AppIcon: Item {
        id: ai
        property var entry
        property int size: 48
        implicitWidth: size
        implicitHeight: size
        readonly property string src: entry ? win.iconOf(entry) : ""
        IconImage { id: aiImg; anchors.fill: parent; source: ai.src; visible: ai.src !== "" && status === Image.Ready; asynchronous: true }
        Rectangle {
            anchors.fill: parent
            visible: !aiImg.visible
            radius: ai.size * 0.3
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
            Sym { anchors.centerIn: parent; name: "apps"; size: ai.size * 0.5; color: Theme.accent }
        }
    }
    // метка источника
    component SourceTag: Rectangle {
        id: st
        property string source
        implicitWidth: stl.implicitWidth + 14
        implicitHeight: 20
        radius: 10
        color: source === "flatpak" ? Qt.rgba(0.29, 0.56, 0.89, 0.2) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2)
        Label { id: stl; anchors.centerIn: parent; text: st.source === "flatpak" ? "Flathub" : "Arch"; size: "caption"; font.weight: Font.Medium }
    }
    // кнопка действия: «Установить» · «Открыть» · ставится
    component ActionBtn: Btn {
        id: ab
        property var entry
        readonly property string src: win.sourceOf(entry)
        readonly property var busy: win.busyWith(entry)
        readonly property bool have: win.installedAny(entry)
        text: busy ? (busy === win.job ? (busy.action === "remove" ? I18n.tr("Удаляется…") : I18n.tr("Ставится…")) : I18n.tr("В очереди"))
            : have ? I18n.tr("Открыть") : I18n.tr("Установить")
        icon: busy ? "refresh" : have ? "play" : "download"
        kind: have || busy ? "soft" : "accent"
        enabled: !busy
        onClicked: have ? win.launch(entry, src) : win.enqueue("install", entry, src)
    }

    // пункт слева: значок и название
    component NavItem: Rectangle {
        id: nav
        property string icon
        property string label
        property bool current: false
        signal picked()
        Layout.fillWidth: true
        implicitHeight: 38
        radius: 12
        color: current ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2) : navHov.hovered ? Theme.soft : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
        HoverHandler { id: navHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: nav.picked() }
        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 10 }
            spacing: 10
            Sym { name: nav.icon; size: 17; color: nav.current ? Theme.accent : Theme.fg2 }
            Label { text: nav.label; Layout.fillWidth: true; elide: Text.ElideRight; font.weight: nav.current ? Font.DemiBold : Font.Normal }
        }
    }

    // карточка подборки
    component AppCard: Rectangle {
        id: card
        required property var modelData
        width: win.cardWidth
        height: 168
        radius: 20
        color: cardHov.hovered ? Theme.soft2 : Theme.soft
        border.width: 1
        border.color: Theme.line
        Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
        HoverHandler { id: cardHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: win.openApp(card.modelData) }
        ColumnLayout {
            anchors { fill: parent; margins: 14 }
            spacing: 8
            RowLayout {
                spacing: 12
                Layout.fillWidth: true
                AppIcon { entry: card.modelData; size: 48 }
                ColumnLayout {
                    spacing: 3
                    Layout.fillWidth: true
                    Label { text: win.titleOf(card.modelData); font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                    Row {
                        spacing: 4
                        SourceTag { visible: !!card.modelData.pkg; source: "pacman" }
                        SourceTag { visible: !!card.modelData.fp; source: "flatpak" }
                    }
                }
            }
            Label {
                text: win.textOf(card.modelData)
                tone: 3; size: "small"
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.fillHeight: true
                verticalAlignment: Text.AlignTop
            }
            ActionBtn { entry: card.modelData; Layout.alignment: Qt.AlignRight }
        }
    }

    // строка результата поиска и «Установленных»
    component AppRow: Rectangle {
        id: row
        required property var modelData
        readonly property var entry: win.fromRow(modelData)
        property bool removable: false
        width: ListView.view ? ListView.view.width : parent.width
        implicitHeight: 64
        radius: 16
        color: rowHov.hovered ? Theme.soft2 : "transparent"
        HoverHandler { id: rowHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: win.openApp(row.entry) }
        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            spacing: 12
            AppIcon { entry: row.entry; size: 40 }
            ColumnLayout {
                spacing: 1
                Layout.fillWidth: true
                Row {
                    spacing: 8
                    Layout.fillWidth: true
                    Label {
                        id: rowTitle
                        text: row.entry.title
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, parent.width - rowTags.width - rowVer.width - 16)
                    }
                    Row {
                        id: rowTags
                        spacing: 4
                        anchors.verticalCenter: rowTitle.verticalCenter
                        SourceTag { visible: !!row.entry.pkg; source: "pacman" }
                        SourceTag { visible: !!row.entry.fp; source: "flatpak" }
                    }
                    Label { id: rowVer; text: row.modelData.version ?? ""; tone: 3; size: "caption"; anchors.verticalCenter: rowTitle.verticalCenter }
                }
                Label { text: row.entry.text; tone: 3; size: "small"; elide: Text.ElideRight; Layout.fillWidth: true; visible: text !== "" }
            }
            ActionBtn { entry: row.entry }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.glass2
        border.width: 1
        border.color: Theme.line

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // --- слева: поиск и разделы ---
            ColumnLayout {
                Layout.preferredWidth: 236
                Layout.maximumWidth: 236
                Layout.fillWidth: false
                Layout.fillHeight: true
                Layout.margins: 18
                Layout.rightMargin: 6
                spacing: 6

                RowLayout {
                    spacing: 10
                    Layout.bottomMargin: 10
                    Rectangle {
                        implicitWidth: 40; implicitHeight: 40; radius: 13
                        color: Theme.accent
                        Sym { anchors.centerIn: parent; name: "store"; size: 22; color: Theme.onAccent }
                    }
                    Label { text: I18n.tr("Магазин"); size: "title"; font.weight: Font.Bold }
                }
                Field {
                    id: search
                    Layout.fillWidth: true
                    Layout.bottomMargin: 8
                    icon: "search"
                    placeholder: I18n.tr("Программы и игры")
                    clearable: true
                    onTextChanged: win.query = text
                }

                NavItem { icon: "grid"; label: I18n.tr("Главная"); current: win.page === "home"; onPicked: { search.text = ""; win.go("home"); } }
                Repeater {
                    model: Featured.sections
                    delegate: NavItem {
                        required property var modelData
                        icon: modelData.icon
                        label: I18n.tr(modelData.title)
                        current: win.page === "section" && win.sectionId === modelData.id
                        onPicked: { search.text = ""; win.go("section", modelData.id); }
                    }
                }
                Rectangle { Layout.fillWidth: true; Layout.topMargin: 6; Layout.bottomMargin: 6; implicitHeight: 1; color: Theme.line }
                NavItem { icon: "check"; label: I18n.tr("Установленные"); current: win.page === "installed"; onPicked: { search.text = ""; win.go("installed"); } }
                Item { Layout.fillHeight: true }
                Label {
                    text: I18n.tr("Arch — пакеты системы, быстрые и общие с ней. Flathub — в своей песочнице, свежие версии")
                    tone: 3; size: "caption"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }

            // --- справа: содержимое ---
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Flickable {
                    id: content
                    anchors { fill: parent; margins: 18; leftMargin: 8; bottomMargin: jobBar.visible ? jobBar.height + 26 : 18 }
                    clip: true
                    contentWidth: width
                    contentHeight: pageCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: pageCol
                        width: content.width
                        spacing: 14

                        // Flathub не подключён
                        Rectangle {
                            visible: !win.status.flathub && win.page !== "app"
                            Layout.fillWidth: true
                            implicitHeight: 64
                            radius: 18
                            color: Qt.rgba(0.29, 0.56, 0.89, 0.14)
                            RowLayout {
                                anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                                spacing: 12
                                Sym { name: "store"; size: 20; color: Theme.accent }
                                Label {
                                    text: I18n.tr("Flathub не подключён — видны только пакеты Arch. Подключите, и появятся тысячи приложений")
                                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                                }
                                Btn {
                                    text: I18n.tr("Подключить")
                                    kind: "accent"
                                    enabled: !win.job || win.job.action !== "connect"
                                    onClicked: { win.queue = win.queue.concat([{ action: "connect", source: "", id: "flathub", title: "Flathub" }]); win.next(); }
                                }
                            }
                        }

                        // --- главная ---
                        Rectangle {
                            visible: win.page === "home"
                            Layout.fillWidth: true
                            implicitHeight: 150
                            radius: 24
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55) }
                                GradientStop { position: 1; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12) }
                            }
                            ColumnLayout {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 26 }
                                spacing: 6
                                Label { text: I18n.tr("Всё для Vanks OS в одном месте"); size: "h1"; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                                Label {
                                    text: I18n.tr("Пакеты Arch и приложения Flathub: ищите слева, ставьте в один щелчок — установки идут по очереди")
                                    tone: 2; wrapMode: Text.WordWrap; Layout.fillWidth: true
                                }
                            }
                        }
                        Repeater {
                            model: win.page === "home" ? Featured.sections : win.page === "section" && win.section ? [win.section] : []
                            delegate: ColumnLayout {
                                id: sec
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 10
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    Label { text: I18n.tr(sec.modelData.title); size: win.page === "section" ? "h1" : "title"; Layout.fillWidth: true }
                                    Btn {
                                        visible: win.page === "home"
                                        text: I18n.tr("Все")
                                        kind: "ghost"
                                        icon: "chevron-right"
                                        onClicked: win.go("section", sec.modelData.id)
                                    }
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 12
                                    Repeater {
                                        // на главной — одна строка раздела
                                        model: win.page === "home" ? sec.modelData.items.slice(0, win.cardCols) : sec.modelData.items
                                        delegate: AppCard {}
                                    }
                                }
                            }
                        }

                        // --- поиск ---
                        ColumnLayout {
                            visible: win.page === "search"
                            Layout.fillWidth: true
                            spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: I18n.tr("Поиск") + ": " + win.query; size: "h1"; elide: Text.ElideRight; Layout.fillWidth: true }
                                Label { text: win.searching ? I18n.tr("Ищу…") : win.results.length + " " + I18n.tr("найдено"); tone: 3 }
                            }
                            Label {
                                visible: !win.searching && win.results.length === 0 && win.query.trim().length >= 2
                                text: I18n.tr("Ничего не нашлось. Попробуйте по-английски или короче")
                                tone: 3
                            }
                            Repeater {
                                model: win.page === "search" ? win.results : []
                                delegate: AppRow { width: pageCol.width }
                            }
                        }

                        // --- установленные ---
                        ColumnLayout {
                            visible: win.page === "installed"
                            Layout.fillWidth: true
                            spacing: 8
                            Label { text: I18n.tr("Установленные"); size: "h1"; Layout.fillWidth: true }
                            Label {
                                text: win.installedLoaded ? I18n.tr("Приложения со значком в меню: пакеты Arch и Flatpak") : I18n.tr("Собираю список…")
                                tone: 3
                            }
                            Repeater {
                                model: win.page === "installed" ? win.installedList : []
                                delegate: AppRow { width: pageCol.width }
                            }
                        }

                        // --- страница приложения ---
                        ColumnLayout {
                            visible: win.page === "app" && win.app !== null
                            Layout.fillWidth: true
                            spacing: 16

                            Btn { text: I18n.tr("Назад"); icon: "chevron-left"; kind: "ghost"; onClicked: win.go(win.backTo === "app" ? "home" : win.backTo, win.sectionId) }

                            RowLayout {
                                spacing: 20
                                Layout.fillWidth: true
                                AppIcon { entry: win.app; size: 96 }
                                ColumnLayout {
                                    spacing: 6
                                    Layout.fillWidth: true
                                    Label { text: win.app ? win.titleOf(win.app) : ""; size: "h1"; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                    Label {
                                        text: win.app ? (win.textOf(win.app) || (win.info?.summary ?? "")) : ""
                                        tone: 2; wrapMode: Text.WordWrap; Layout.fillWidth: true
                                    }
                                    Label {
                                        visible: text !== ""
                                        text: win.info?.developer ?? ""
                                        tone: 3; size: "small"
                                    }
                                }
                            }

                            // откуда ставить
                            RowLayout {
                                visible: win.app !== null && !!win.app.pkg && !!win.app.fp
                                spacing: 12
                                Label { text: I18n.tr("Источник"); tone: 2 }
                                Chips {
                                    model: [{ value: "pacman", label: "Arch (pacman)" }, { value: "flatpak", label: "Flathub" }]
                                    current: win.appSource
                                    onPicked: v => { win.appSource = v; win.loadInfo(); }
                                }
                            }

                            RowLayout {
                                spacing: 10
                                readonly property bool have: win.app ? win.installedIn(win.app, win.appSource) : false
                                readonly property var busy: win.app ? win.busyWith(win.app) : null
                                Btn {
                                    text: parent.busy ? (parent.busy === win.job ? I18n.tr("Идёт…") : I18n.tr("В очереди"))
                                        : parent.have ? I18n.tr("Открыть") : I18n.tr("Установить")
                                    icon: parent.busy ? "refresh" : parent.have ? "play" : "download"
                                    kind: "accent"
                                    enabled: !parent.busy
                                    onClicked: parent.have ? win.launch(win.app, win.appSource) : win.enqueue("install", win.app, win.appSource)
                                }
                                Btn {
                                    visible: parent.have && !parent.busy
                                    text: I18n.tr("Удалить")
                                    icon: "trash"
                                    kind: "danger"
                                    onClicked: win.enqueue("remove", win.app, win.appSource)
                                }
                                Label {
                                    visible: win.appSource === "pacman" && !parent.have && !parent.busy
                                    text: I18n.tr("Вместе с программой обновится система — так в Arch правильно")
                                    tone: 3; size: "small"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                                }
                            }

                            // снимок экрана (Flathub)
                            ClippingRectangle {
                                visible: shotImg.status === Image.Ready
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.min(420, width * (shotImg.implicitHeight / Math.max(1, shotImg.implicitWidth)))
                                radius: 18
                                color: Theme.soft
                                Image {
                                    id: shotImg
                                    anchors.fill: parent
                                    source: win.appSource === "flatpak" && win.info?.screenshot ? win.info.screenshot : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }
                            }

                            Label {
                                visible: text !== ""
                                text: win.info ? ((!I18n.en && win.info.descriptionRu) ? win.info.descriptionRu : (win.info.description ?? "")) : ""
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                                lineHeight: 1.25
                            }

                            // сведения
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: infoGrid.implicitHeight + 28
                                radius: 18
                                color: Theme.soft
                                border.width: 1
                                border.color: Theme.line
                                visible: win.info !== null
                                GridLayout {
                                    id: infoGrid
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                                    columns: 2
                                    columnSpacing: 18
                                    rowSpacing: 8
                                    Repeater {
                                        model: {
                                            const i = win.info ?? {};
                                            return [
                                                [I18n.tr("Пакет"), i.id],
                                                [I18n.tr("Версия"), i.version],
                                                [I18n.tr("Скачать"), i.download],
                                                [I18n.tr("На диске"), i.size],
                                                [I18n.tr("Репозиторий"), i.repo],
                                                [I18n.tr("Лицензия"), i.license],
                                                [I18n.tr("Сайт"), i.homepage]
                                            ].filter(r => r[1]).reduce((a, r) => a.concat(r), []);
                                        }
                                        delegate: Label {
                                            required property var modelData
                                            required property int index
                                            text: modelData
                                            tone: index % 2 === 0 ? 3 : 1
                                            size: "small"
                                            Layout.fillWidth: index % 2 === 1
                                            wrapMode: Text.WrapAnywhere
                                            font.family: index % 2 === 1 && index === 1 ? Theme.fontMono : font.family
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // --- что ставится сейчас ---
                Rectangle {
                    id: jobBar
                    visible: win.job !== null
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 18; leftMargin: 8 }
                    height: 58
                    radius: 18
                    color: Theme.soft2
                    border.width: 1
                    border.color: Theme.line
                    RowLayout {
                        anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                        spacing: 12
                        Sym {
                            name: "refresh"; size: 18; color: Theme.accent
                            RotationAnimation on rotation { running: jobBar.visible; from: 0; to: 360; duration: 1200; loops: Animation.Infinite }
                        }
                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            Label {
                                text: win.job ? win.job.title + " — " + win.jobStep : ""
                                font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true
                            }
                            Label { text: win.jobLine; tone: 3; size: "caption"; elide: Text.ElideRight; Layout.fillWidth: true; visible: text !== "" }
                        }
                        Label { visible: win.queue.length > 0; text: I18n.tr("ещё в очереди:") + " " + win.queue.length; tone: 3; size: "small" }
                    }
                }

                // --- уведомление ---
                Rectangle {
                    visible: win.toast !== ""
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: jobBar.visible ? 90 : 24 }
                    width: Math.min(parent.width - 60, toastLbl.implicitWidth + 36)
                    height: 44
                    radius: 22
                    color: win.toastError ? "#5a2a2a" : Theme.accent
                    Label {
                        id: toastLbl
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 36)
                        elide: Text.ElideRight
                        text: win.toast
                        color: win.toastError ? "white" : Theme.onAccent
                    }
                }
            }
        }
    }

    // delta-store ipc call store … — демо и проверки: go section games ·
    // go home "" · find krita · open org.kde.krita · scroll 600 · quit
    IpcHandler {
        target: "store"
        function go(p: string, sec: string): void { search.text = ""; win.go(p, sec); }
        function find(text: string): void { search.text = text; }
        function open(id: string): void {
            for (const s of Featured.sections)
                for (const e of s.items)
                    if (e.pkg === id || e.fp === id) { win.openApp(e); return; }
        }
        function scroll(y: real): void { scroller.to = y; scroller.restart(); }
        function quit(): void { Qt.quit(); }
    }
    NumberAnimation { id: scroller; target: content; property: "contentY"; duration: 900 * Theme.anim.k; easing.type: Easing.InOutCubic }

    Shortcut { sequence: "Escape"; onActivated: { if (win.page === "app") win.go(win.backTo, win.sectionId); else if (search.text) search.text = ""; else Qt.quit(); } }
    Shortcut { sequence: "Ctrl+F"; onActivated: search.focusInput() }
}
