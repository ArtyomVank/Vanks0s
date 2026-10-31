pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.common
import qs.common.ui

// «Программы Windows» (delta-exe --manager): все префиксы лаунчера с их
// программами — установленными (ярлыки в меню) и просто запущенными, —
// раннер каждого префикса (Авто, версия Proton CachyOS или Wine), настройки
// Wine, папка C:, удаление. Внизу — что запускали обычно, Wine системы.
// Данные — delta-exe --list, действия — delta-exe с ключами.
FloatingWindow {
    id: win

    property var db: ({ prefixes: [], normal: [], runners: { protons: [], wine: false, umu: false } })
    property bool loaded: false
    property string removing: ""          // префикс, который ждёт второго нажатия «Удалить»
    readonly property var protons: db.runners?.protons ?? []

    title: I18n.tr("Программы Windows")
    implicitWidth: 760
    implicitHeight: 720
    minimumSize: Qt.size(560, 480)
    color: "transparent"

    onClosed: Qt.quit()

    function reload() { lister.running = true; }
    function run(cmd) { Sounds.play("oobe-step", 0); Quickshell.execDetached(cmd); }
    function runnerLabel(r) {
        if (r === "wine") return "Wine";
        if (r.startsWith("proton:")) return r.split("/").pop();
        return I18n.tr("Авто");
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
                    Label { text: I18n.tr("Программы Windows"); size: "h1"; Layout.fillWidth: true }
                    Label {
                        text: I18n.tr("Всё, что ставили и запускали через лаунчер, — у каждой программы своя папка Windows")
                        tone: 3; size: "small"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                }
                Btn { icon: "refresh"; kind: "ghost"; onClicked: win.reload() }
            }

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

            // --- префиксы ---
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

                    Label {
                        visible: win.loaded && win.db.prefixes.length === 0 && win.db.normal.length === 0
                        Layout.fillWidth: true
                        Layout.topMargin: 40
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
