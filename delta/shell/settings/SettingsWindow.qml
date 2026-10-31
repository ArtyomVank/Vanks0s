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
                    text: pane.sec ? pane.sec.title : Nav.current === "home" ? I18n.tr("Все настройки") : ""
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

                // главная: папки карточками
                Flickable {
                    id: home
                    readonly property bool cur: Nav.current === "home"
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

                Repeater {
                    model: Registry.sections
                    delegate: Flickable {
                        id: page
                        required property var modelData
                        readonly property bool cur: Nav.current === modelData.id
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
