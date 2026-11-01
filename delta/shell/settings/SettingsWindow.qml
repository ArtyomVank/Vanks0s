pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.common
import qs.common.ui
import qs.settings
import qs.settings.parts

// Окно «Настроек»: слева поиск и разделы, справа открытый раздел.
//
// Разделы — файлы settings/sections/<Имя>.qml (их пишут разные модули, см.
// CONTRACTS.md §6). Каждый грузится только при первом открытии и потом
// остаётся живым: прокрутка и состояние списков сохраняются. Нет файла или он
// не загрузился — вместо раздела заглушка, окно продолжает работать.
//
// Класс окна (app id) «delta-settings» задаёт `//@ pragma AppId` во входном
// файле: на него завязано правило Hyprland (плавающее 1100×720 по центру).
FloatingWindow {
    id: win

    // закрыли окно — завершаем процесс (в отладочной сессии не нужно)
    property bool quitOnClose: true
    readonly property int contentWidth: Math.min(720, pane.width - 56)

    title: I18n.tr("Настройки")
    implicitWidth: 1100
    implicitHeight: 720
    minimumSize: Qt.size(880, 560)
    color: "transparent"

    onClosed: if (quitOnClose) Qt.quit()

    Component.onCompleted: {
        const first = Registry.resolve(Quickshell.env("DELTA_SETTINGS_SECTION") || "");
        Nav.open(first || Nav.current);
    }

    function close() {
        Settings.flush();
        if (quitOnClose) Qt.quit();
        else visible = false;
    }
    Connections {
        target: Nav
        function onCloseRequested() { win.close(); }
    }

    // поднять уже открытое окно (повторный запуск delta-settings)
    // (Hyprland 0.56 с Lua-конфигом принимает в dispatch выражение Lua)
    function raise() {
        Hyprland.dispatch('hl.dsp.focus({ window = "class:^delta-settings$" })');
    }

    // Скругление и рамку окну рисует Hyprland, поэтому подложка — без углов.
    Glass {
        anchors.fill: parent
        strong: true
        radius: 0
        border.width: 0
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Sidebar {
            id: sidebar
            Layout.preferredWidth: 260
            Layout.fillHeight: true
        }

        Item {
            id: pane
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            readonly property var sec: Registry.byId(Nav.current)

            // заголовок раздела
            RowLayout {
                id: header
                x: (pane.width - win.contentWidth) / 2
                width: win.contentWidth
                y: 20
                height: 44
                spacing: 12
                Label {
                    id: headTitle
                    text: Nav.searching ? I18n.tr("Поиск") : pane.sec ? pane.sec.title : Nav.current === "home" ? I18n.tr("Все настройки") : ""
                    font.pixelSize: 24
                    font.weight: Font.Bold
                    font.family: Theme.fontDisplay
                    Layout.fillWidth: true
                }
                Rectangle {
                    visible: Exec.dryRun
                    implicitWidth: dryLbl.implicitWidth + 20
                    implicitHeight: 26
                    radius: 13
                    color: Qt.rgba(0.94, 0.6, 0.17, 0.18)
                    Label { id: dryLbl; anchors.centerIn: parent; text: I18n.tr("пробный режим"); size: "caption"; color: "#F09A2B" }
                }
                Btn { icon: "close"; onClicked: win.close() }
            }

            // разделы: один Flickable на раздел, видим только текущий
            Item {
                id: stack
                anchors { fill: parent; topMargin: header.y + header.height + 6 }
                // прокрученное не заезжает под заголовок раздела
                clip: true

                // главная: папки карточками
                Flickable {
                    id: home
                    readonly property bool cur: Nav.current === "home" && !Nav.searching
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: homeGrid.implicitHeight + 58
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: cur
                    enabled: cur
                    visible: opacity > 0.01
                    opacity: cur ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.anim.normal; easing.type: Theme.anim.outCurve } }
                    Home {
                        id: homeGrid
                        x: (home.width - win.contentWidth) / 2
                        y: 10 + slide
                        width: win.contentWidth
                        property real slide: home.cur ? 0 : 18
                        Behavior on slide { NumberAnimation { duration: Theme.anim.slow; easing.type: Theme.anim.outCurve } }
                    }
                }

                // поиск: всё найденное — разделы и строки в них
                Flickable {
                    id: found
                    readonly property bool cur: Nav.searching
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: foundCol.implicitHeight + 48
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: cur
                    enabled: cur
                    visible: opacity > 0.01
                    opacity: cur ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.anim.normal; easing.type: Theme.anim.outCurve } }
                    onCurChanged: if (cur) contentY = 0

                    // выбранное стрелками — в видимой части
                    Connections {
                        target: Nav
                        function onPickChanged() {
                            const it = foundRep.itemAt(Nav.pick);
                            if (!it) return;
                            const y = foundCol.y + it.y;
                            if (y < found.contentY) found.contentY = Math.max(0, y - 8);
                            else if (y + it.height > found.contentY + found.height) found.contentY = y + it.height - found.height + 8;
                        }
                    }

                    Column {
                        id: foundCol
                        x: (found.width - win.contentWidth) / 2
                        y: 10
                        width: win.contentWidth
                        spacing: 4

                        Repeater {
                            id: foundRep
                            model: Nav.results
                            delegate: Rectangle {
                                id: res
                                required property var modelData
                                required property int index
                                readonly property var sec: Registry.byId(modelData.sec)
                                readonly property bool sel: Nav.pick === index
                                width: foundCol.width
                                height: Math.max(56, resText.implicitHeight + 20)
                                radius: 14
                                color: sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                                     : resHov.hovered ? Theme.soft2 : Theme.soft
                                border.width: 1
                                border.color: sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5) : Theme.line
                                Behavior on color { ColorAnimation { duration: Theme.anim.fast } }

                                RowLayout {
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 14 }
                                    spacing: 12
                                    Rectangle {
                                        implicitWidth: 36
                                        implicitHeight: 36
                                        radius: 11
                                        color: res.modelData.kind === "section" ? Theme.accent : Theme.soft2
                                        Sym {
                                            anchors.centerIn: parent
                                            name: res.sec ? res.sec.icon : "settings"
                                            size: 18
                                            color: res.modelData.kind === "section" ? Theme.onAccent : Theme.fg2
                                        }
                                    }
                                    ColumnLayout {
                                        id: resText
                                        spacing: 2
                                        Layout.fillWidth: true
                                        Label {
                                            text: res.modelData.key ? Registry.label(I18n.tr(res.modelData.key)) : (res.sec ? res.sec.title : "")
                                            font.weight: Font.Medium
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Label {
                                            // где это: раздел › карточка
                                            text: {
                                                const r = res.modelData;
                                                if (!res.sec) return "";
                                                if (r.kind === "section") {
                                                    const f = Registry.folder(res.sec.group);
                                                    return (f ? f.title + " › " : "") + I18n.tr("раздел");
                                                }
                                                return res.sec.title + (r.card ? " › " + Registry.label(I18n.tr(r.card)) : "");
                                            }
                                            size: "small"
                                            color: Theme.accent
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Label {
                                            visible: text.length > 0
                                            text: res.modelData.sub ? Registry.label(I18n.tr(res.modelData.sub)) : ""
                                            size: "small"
                                            tone: 3
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                            Layout.fillWidth: true
                                        }
                                    }
                                    Sym { name: "chevron-right"; size: 16; color: Theme.fg3 }
                                }
                                HoverHandler { id: resHov; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) Nav.pick = res.index }
                                TapHandler { onTapped: Nav.openResult(res.modelData) }
                            }
                        }

                        Placeholder {
                            visible: Nav.results.length === 0
                            width: parent.width
                            icon: "search"
                            text: I18n.tr("Ничего не найдено")
                            detail: I18n.tr("Попробуйте другое слово: «яркость», «обои», «пароль», «звук при входе»")
                        }
                    }
                }

                Repeater {
                    model: Registry.sections
                    delegate: Flickable {
                        id: page
                        required property var modelData
                        readonly property bool cur: Nav.current === modelData.id && !Nav.searching
                        readonly property bool exists: Registry.present[modelData.file] === true
                        readonly property bool failed: loader.status === Loader.Error

                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: holder.height + 48
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: cur
                        enabled: cur
                        visible: opacity > 0.01
                        opacity: cur ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.anim.normal; easing.type: Theme.anim.outCurve } }

                        Connections {
                            target: Nav
                            enabled: page.cur
                            function onScrollTo(y) { page.contentY = Math.max(0, Math.min(y, page.contentHeight - page.height)); }
                        }

                        // найденное в поиске: прокрутить к строке и подсветить её.
                        // Строку ищем в дереве раздела по заголовку (у «Теплота: 40 %»
                        // — по началу); раздел мог только что загрузиться — пробуем
                        // ещё несколько раз, пока не уляжется раскладка.
                        Connections {
                            target: Nav
                            function onReveal(section, key, card, inCard) {
                                if (section !== page.modelData.id) return;
                                reveal.key = key;
                                reveal.card = card;
                                reveal.inCard = inCard;
                                reveal.tries = 0;
                                reveal.restart();
                            }
                        }
                        function findRow(item, text, card) {
                            if (!item || item.visible === false) return null;
                            if (item !== loader.item && typeof item.title === "string" && item.title.length > 0
                                    && item.title.startsWith(text) && (card ? item.rows !== undefined : item.wide !== undefined))
                                return item;
                            const kids = item.children || [];
                            for (let i = 0; i < kids.length; i++) {
                                const r = findRow(kids[i], text, card);
                                if (r) return r;
                            }
                            return null;
                        }
                        Timer {
                            id: reveal
                            property string key
                            property bool card
                            property string inCard
                            property int tries
                            interval: 120
                            onTriggered: {
                                // одинаковые строки в разных карточках: сначала карточка
                                const box = loader.item && inCard ? page.findRow(loader.item, Registry.label(I18n.tr(inCard)), true) : null;
                                const row = loader.item ? (box && page.findRow(box, Registry.label(I18n.tr(key)), false))
                                                          || page.findRow(loader.item, Registry.label(I18n.tr(key)), card) : null;
                                if (!row) {
                                    if (++tries < 8) restart();
                                    else Nav.toast(I18n.tr("Эта настройка сейчас недоступна"));
                                    return;
                                }
                                const p = row.mapToItem(holder, 0, 0);
                                scroll.to = Math.max(0, Math.min(10 + p.y - page.height * 0.28, page.contentHeight - page.height));
                                scroll.restart();
                                flash.x = p.x - 6;
                                flash.y = p.y - 4;
                                flash.width = row.width + 12;
                                flash.height = row.height + 8;
                                blink.restart();
                            }
                        }
                        NumberAnimation { id: scroll; target: page; property: "contentY"; duration: Theme.anim.slow; easing.type: Theme.anim.outCurve }

                        Item {
                            id: holder
                            x: (page.width - win.contentWidth) / 2
                            y: 10 + slide
                            width: win.contentWidth
                            height: page.exists && !page.failed ? loader.height : placeholder.implicitHeight
                            // раздел въезжает снизу при открытии
                            property real slide: page.cur ? 0 : 18
                            Behavior on slide { NumberAnimation { duration: Theme.anim.slow; easing.type: Theme.anim.outCurve } }

                            Loader {
                                id: loader
                                width: parent.width
                                active: page.exists && Nav.visited[page.modelData.id] === true
                                source: active ? Registry.dir + "/" + page.modelData.file + ".qml" : ""
                                onStatusChanged: if (status === Loader.Error)
                                    console.warn("[delta-settings] раздел " + page.modelData.file + " не загрузился, показываю заглушку")
                            }
                            // подсветка найденной строки: дважды мигает цветом акцента
                            Rectangle {
                                id: flash
                                z: 10
                                radius: 14
                                opacity: 0
                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                border.width: 2
                                border.color: Theme.accent
                                SequentialAnimation {
                                    id: blink
                                    NumberAnimation { target: flash; property: "opacity"; to: 1; duration: 180 }
                                    NumberAnimation { target: flash; property: "opacity"; to: 0.35; duration: 260 }
                                    NumberAnimation { target: flash; property: "opacity"; to: 1; duration: 220 }
                                    PauseAnimation { duration: 900 }
                                    NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 600 }
                                }
                            }
                            Placeholder {
                                id: placeholder
                                width: parent.width
                                visible: Registry.scanned && (!page.exists || page.failed)
                                icon: page.modelData.icon
                                text: page.failed ? "Раздел не загрузился" : "Раздел скоро появится"
                                detail: page.failed ? "Раздел не загрузился — подробности в журнале оболочки."
                                                    : "Он ещё в работе — загляните сюда после обновления."
                            }
                        }

                        // тонкий индикатор прокрутки
                        Rectangle {
                            visible: page.contentHeight > page.height + 1
                            parent: page
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            width: 4
                            radius: 2
                            color: Theme.fg3
                            opacity: page.moving ? 0.6 : 0.22
                            Behavior on opacity { NumberAnimation { duration: Theme.anim.normal } }
                            height: Math.max(30, page.height * page.height / page.contentHeight)
                            y: (page.height - height) * (page.contentY / Math.max(1, page.contentHeight - page.height))
                        }
                    }
                }
            }
        }
    }

    // слой для диалогов разделов и подсказка снизу
    Item {
        id: overlay
        anchors.fill: parent
        z: 50
        Component.onCompleted: Nav.overlay = overlay
        Toast {}
    }

    Shortcut { sequence: "Ctrl+F"; onActivated: sidebar.searchField.focusInput() }
    Shortcut { sequences: ["Ctrl+Q", "Ctrl+W"]; onActivated: win.close() }

    // delta-settings <раздел> при уже открытом окне и проверки:
    //   qs -p …/settings-app.qml ipc call settings open keyboard
    IpcHandler {
        target: "settings"

        function open(section: string): string {
            const id = Registry.resolve(section);
            if (id) Nav.open(id);
            win.visible = true;
            win.raise();
            return id || ("нет раздела «" + section + "», открыт " + Nav.current);
        }
        function search(text: string): void { Nav.query = text; }
        // найденное: список (JSON) и открыть n-е, как Enter после стрелок
        function found(): string {
            return JSON.stringify(Nav.results.map(r => [r.sec, r.kind, Registry.label(r.key), Math.round(r.score)]));
        }
        function pick(n: int): void { Nav.openResult(Nav.results[n]); }
        function act(name: string, arg: string): void { Nav.action(name, arg); }
        function scroll(y: real): void { Nav.scrollTo(y); }
        function toast(text: string): void { Nav.toast(text); }
        function state(): string {
            return JSON.stringify({ section: Nav.current, query: Nav.query, dryRun: Exec.dryRun,
                                    found: Registry.filtered(Nav.query).map(s => s.id), present: Object.keys(Registry.present) });
        }
        function journal(): string { return JSON.stringify(Exec.journal, null, 1); }
        function get(key: string): string { return JSON.stringify(Settings.get(key, null)); }
        function set(key: string, json: string): void { Settings.set(key, JSON.parse(json)); }
        function quit(): void { Qt.quit(); }
    }
}
