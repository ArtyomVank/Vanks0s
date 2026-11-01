pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.common
import qs.common.ui

// Delta Box (delta-box): одна система Windows для программ из папок.
// «Добавить папку» — папка копируется в C:\Program Files общего префикса,
// у программы выбирается файл запуска (единственный — сам), и она появляется
// плиткой здесь и в меню приложений. Ниже — что поставили в Box установщиком,
// «Скачать в Box» — Steam и Chrome для Windows официальными установщиками
// (для опытных: версии для Linux работают лучше),
// и сама система: раннер, настройки Wine, диск C:. Данные — delta-box --list,
// действия — он же с ключами; окна выбора папки и файла — zenity.
FloatingWindow {
    id: win

    property var db: ({ apps: [], others: [], runners: { protons: [], wine: false }, runner: "auto", size: "", ready: false })
    property bool loaded: false
    property string importing: ""        // папка, которая сейчас копируется
    property string error: ""
    property string removing: ""         // программа, которая ждёт второго нажатия «Удалить»
    property var picking: null           // { name, exes } — выбор файла запуска
    readonly property var protons: db.runners?.protons ?? []
    // «Скачать в Box»: что качается и ставится сейчас
    property string getting: ""          // steam · chrome
    property string getStep: ""
    property int getProgress: 0

    title: "Delta Box"
    implicitWidth: 960
    implicitHeight: 680
    minimumSize: Qt.size(620, 500)
    color: "transparent"

    onClosed: Qt.quit()

    function reload() { lister.running = true; }
    function run(cmd) { Sounds.play("oobe-step", 0); Quickshell.execDetached(cmd); }
    function launch(app) {
        if (!app.exe) { pick(app.name); return; }
        run(app.name ? ["delta-box", "--run", app.name] : ["delta-exe", "--app", "delta-box", app.exe]);
    }
    function pick(name) { exesProc.name = name; exesProc.running = true; }
    function sizeText(b) {
        if (b >= 1073741824) return (b / 1073741824).toFixed(1).replace(".", ",") + " " + I18n.tr("ГБ");
        if (b >= 1048576) return Math.round(b / 1048576) + " " + I18n.tr("МБ");
        return Math.max(1, Math.round(b / 1024)) + " " + I18n.tr("КБ");
    }

    Process {
        id: lister
        running: true
        command: ["delta-box", "--list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { win.db = JSON.parse(text); } catch (e) {}
                win.loaded = true;
            }
        }
    }
    Process {
        id: changer
        onExited: win.reload()
    }
    function change(cmd) { changer.command = cmd; changer.running = true; }

    // «Скачать в Box»: delta-box --get — шаги и проценты строками
    Process {
        id: getter
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("::progress:: ")) win.getProgress = parseInt(line.slice(13)) || 0;
                else if (line.startsWith("::step:: ")) win.getStep = I18n.tr(line.slice(9));
            }
        }
        onExited: code => {
            Sounds.play(code === 0 ? "oobe-select" : "dialog-warning", 60);
            win.getting = "";
            win.reload();
        }
    }
    function getApp(id) {
        if (getting) return;
        getting = id; getStep = ""; getProgress = 0;
        Sounds.play("oobe-step", 0);
        getter.command = ["delta-box", "--get", id];
        getter.running = true;
    }

    // окно выбора папки → копия в Box
    Process {
        id: folderDlg
        command: ["zenity", "--file-selection", "--directory", "--title=" + I18n.tr("Папка программы для Delta Box")]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                if (!p) return;
                win.error = "";
                win.importing = p;
                importer.command = ["delta-box", "--import", p];
                importer.running = true;
            }
        }
    }
    Process {
        id: importer
        stdout: StdioCollector {
            onStreamFinished: {
                win.importing = "";
                let r;
                try { r = JSON.parse(text); } catch (e) { win.error = I18n.tr("Не удалось добавить папку"); return; }
                if (r.error) { win.error = I18n.tr(r.error); return; }
                Sounds.play("oobe-select", 60);
                win.reload();
                // файл запуска не угадан — спросить сразу
                if (!r.exe) win.picking = { name: r.name, exes: r.exes };
            }
        }
    }
    Process {
        id: exesProc
        property string name
        command: ["delta-box", "--exes", name]
        stdout: StdioCollector {
            onStreamFinished: {
                let l = [];
                try { l = JSON.parse(text); } catch (e) {}
                win.picking = { name: exesProc.name, exes: l };
            }
        }
    }
    // «Другой файл…» внутри папки программы, «Открыть файл» и «Установить» — любой
    Process {
        id: fileDlg
        property string mode            // set · file · install
        property string name
        property string dir
        command: ["zenity", "--file-selection", "--title=" + (mode === "install" ? I18n.tr("Установщик программы") : I18n.tr("Программа Windows")),
            "--file-filter=" + I18n.tr("Программы Windows") + " | *.exe *.EXE *.msi *.MSI *.bat"]
            .concat(dir ? ["--filename=" + dir + "/"] : [])
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                if (!p) return;
                if (fileDlg.mode === "set") { win.picking = null; win.change(["delta-box", "--set", fileDlg.name, p]); }
                else if (fileDlg.mode === "install") win.run(["delta-box", "--install", p]);
                else win.run(["delta-box", "--file", p]);
            }
        }
    }
    function chooseFile(mode, name, dir) {
        fileDlg.mode = mode; fileDlg.name = name || ""; fileDlg.dir = dir || "";
        fileDlg.running = true;
    }

    // плитка программы: значок, название, файл запуска; щелчок — запустить
    component AppTile: Rectangle {
        id: tile
        required property var modelData
        readonly property bool own: modelData.name !== ""
        readonly property string src: modelData.icon.startsWith("/") ? "file://" + modelData.icon
            : modelData.icon && modelData.icon !== "wine" ? Quickshell.iconPath(modelData.icon, true) : ""
        width: 168
        height: 176
        radius: 20
        color: hov.hovered ? Theme.soft2 : Theme.soft
        border.width: 1
        border.color: !modelData.exe ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6) : Theme.line
        Behavior on color { ColorAnimation { duration: Theme.anim.fast } }

        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: win.launch(tile.modelData) }

        ColumnLayout {
            anchors { fill: parent; margins: 14 }
            spacing: 6
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 6
                implicitWidth: 60; implicitHeight: 60
                IconImage { id: ic; anchors.fill: parent; source: tile.src; visible: tile.src !== "" && status === Image.Ready }
                Rectangle {
                    anchors.fill: parent
                    visible: !ic.visible
                    radius: 18
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                    Sym { anchors.centerIn: parent; name: "windows"; size: 30; color: Theme.accent }
                }
            }
            Label {
                text: tile.modelData.title
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.weight: Font.DemiBold
            }
            Label {
                text: tile.modelData.exe ? tile.modelData.exe.split("/").pop() : I18n.tr("Выберите файл запуска")
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                size: "caption"
                tone: tile.modelData.exe ? 3 : 1
                color: tile.modelData.exe ? Theme.fg3 : Theme.accent
            }
            Item { Layout.fillHeight: true }
        }

        // на наведении: сменить файл запуска, удалить из Box. Поставленные
        // установщиком удаляются по ярлыку: их папка в C: и ярлыки
        readonly property string key: own ? modelData.name : modelData.desktop
        Row {
            visible: tile.key !== "" && (hov.hovered || win.removing === tile.key)
            anchors { top: parent.top; right: parent.right; margins: 6 }
            spacing: 2
            Btn { visible: tile.own; icon: "settings"; iconSize: 15; kind: "ghost"; onClicked: win.pick(tile.modelData.name) }
            Btn {
                icon: "trash"
                iconSize: 15
                kind: "danger"
                text: win.removing === tile.key ? I18n.tr("Точно?") : ""
                onClicked: {
                    if (win.removing !== tile.key) { win.removing = tile.key; return; }
                    win.removing = "";
                    win.change(tile.own ? ["delta-box", "--remove", tile.key] : ["delta-box", "--uninstall", tile.key]);
                }
            }
        }
    }

    // плитка «Скачать в Box»: значок, название, что это; щелчок — скачать и поставить
    component GetTile: Rectangle {
        id: gt
        required property var modelData
        readonly property bool busy: win.getting === modelData.id
        readonly property string src: Quickshell.iconPath(modelData.icon, true) || Quickshell.iconPath(modelData.icon2 ?? "", true)
        Layout.fillWidth: true
        implicitHeight: 76
        radius: 18
        color: gtHov.hovered && !win.getting ? Theme.soft2 : Theme.soft
        border.width: 1
        border.color: gt.busy ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6) : Theme.line
        opacity: win.getting && !gt.busy ? 0.55 : 1
        Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
        Behavior on opacity { NumberAnimation { duration: Theme.anim.normal } }

        HoverHandler { id: gtHov; cursorShape: win.getting ? Qt.ArrowCursor : Qt.PointingHandCursor }
        TapHandler { enabled: !win.getting; onTapped: win.getApp(gt.modelData.id) }

        // ход загрузки — заливка снизу карточки
        Rectangle {
            visible: gt.busy
            anchors { left: parent.left; bottom: parent.bottom; margins: 1 }
            height: 3
            radius: 2
            width: (parent.width - 2) * win.getProgress / 100
            color: Theme.accent
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
        RowLayout {
            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
            spacing: 12
            Item {
                implicitWidth: 42; implicitHeight: 42
                IconImage { id: gic; anchors.fill: parent; source: gt.src; visible: gt.src !== "" && status === Image.Ready }
                Rectangle {
                    anchors.fill: parent
                    visible: !gic.visible
                    radius: 13
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                    Sym { anchors.centerIn: parent; name: gt.modelData.sym; size: 22; color: Theme.accent }
                }
            }
            ColumnLayout {
                spacing: 1
                Layout.fillWidth: true
                Label { text: gt.modelData.title; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                Label {
                    text: gt.busy ? (win.getStep || I18n.tr("Подготовка…")) + (win.getProgress > 0 && win.getProgress < 100 ? " · " + win.getProgress + "%" : "")
                                  : I18n.tr(gt.modelData.text)
                    tone: 3; size: "small"; Layout.fillWidth: true; elide: Text.ElideRight
                }
            }
            Sym { visible: !gt.busy; name: "download"; size: 18; color: Theme.accent }
            Sym {
                visible: gt.busy
                name: "refresh"
                size: 18
                color: Theme.accent
                RotationAnimation on rotation { running: gt.busy; from: 0; to: 360; duration: 1200; loops: Animation.Infinite }
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
                    Label { text: "Delta Box"; size: "h1"; Layout.fillWidth: true }
                    Label {
                        text: I18n.tr("Одна система Windows для всех ваших программ: добавьте папку — она скопируется внутрь")
                        tone: 3; size: "small"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                }
                Btn { text: I18n.tr("Открыть файл"); icon: "file"; onClicked: win.chooseFile("file", "", win.db.drive ?? "") }
                Btn {
                    text: I18n.tr("Добавить папку")
                    icon: "plus"
                    kind: "accent"
                    enabled: win.importing === ""
                    onClicked: folderDlg.running = true
                }
            }

            // --- копирование или ошибка ---
            Rectangle {
                visible: win.importing !== "" || win.error !== ""
                Layout.fillWidth: true
                implicitHeight: 52
                radius: 16
                color: win.error ? Qt.rgba(1, 0.42, 0.42, 0.14) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 10 }
                    spacing: 12
                    Sym {
                        name: win.error ? "warning" : "refresh"
                        size: 18
                        color: win.error ? "#ff6b6b" : Theme.accent
                        RotationAnimation on rotation { running: win.importing !== ""; from: 0; to: 360; duration: 1200; loops: Animation.Infinite }
                    }
                    Label {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        text: win.error || I18n.tr("Копирую в Delta Box:") + " " + win.importing.split("/").pop() + " — " + I18n.tr("большие игры — несколько минут")
                    }
                    Btn { visible: win.error !== ""; icon: "close"; kind: "ghost"; onClicked: win.error = "" }
                }
            }

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

                    // --- пусто ---
                    Rectangle {
                        visible: win.loaded && win.db.apps.length === 0 && win.db.others.length === 0
                        Layout.fillWidth: true
                        implicitHeight: emptyCol.implicitHeight + 56
                        radius: 24
                        color: Theme.soft
                        border.width: 1
                        border.color: Theme.line
                        ColumnLayout {
                            id: emptyCol
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 48, 460)
                            spacing: 12
                            Sym { Layout.alignment: Qt.AlignHCenter; name: "folder"; size: 44; color: Theme.accent }
                            Label {
                                text: I18n.tr("Здесь пока пусто")
                                size: "title"
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Label {
                                text: I18n.tr("Выберите папку с программой или игрой для Windows — она скопируется в Delta Box, а вы выберете, какой файл её запускает. Все программы Box живут в одной системе и видят друг друга")
                                tone: 3; size: "small"; wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Btn {
                                Layout.alignment: Qt.AlignHCenter
                                text: I18n.tr("Добавить папку")
                                icon: "plus"
                                kind: "accent"
                                enabled: win.importing === ""
                                onClicked: folderDlg.running = true
                            }
                        }
                    }

                    // --- программы ---
                    Label { visible: win.db.apps.length > 0; text: I18n.tr("Программы"); size: "title"; Layout.fillWidth: true }
                    Flow {
                        visible: win.db.apps.length > 0
                        Layout.fillWidth: true
                        spacing: 12
                        Repeater { model: win.db.apps; delegate: AppTile {} }
                    }

                    Label { visible: win.db.others.length > 0; text: I18n.tr("Поставлены установщиком"); size: "title"; Layout.fillWidth: true; Layout.topMargin: 6 }
                    Flow {
                        visible: win.db.others.length > 0
                        Layout.fillWidth: true
                        spacing: 12
                        Repeater { model: win.db.others; delegate: AppTile {} }
                    }

                    // --- скачать в Box: Steam и Chrome для Windows ---
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        spacing: 10
                        Label { text: I18n.tr("Скачать в Box"); size: "title" }
                        Rectangle {
                            implicitWidth: expLabel.implicitWidth + 22
                            implicitHeight: 26
                            radius: 13
                            color: Qt.rgba(1, 0.69, 0.13, 0.16)
                            border.width: 1
                            border.color: Qt.rgba(1, 0.69, 0.13, 0.45)
                            Label { id: expLabel; anchors.centerIn: parent; text: I18n.tr("Только для опытных пользователей"); size: "caption"; font.weight: Font.DemiBold; color: "#ffb020" }
                        }
                        Item { Layout.fillWidth: true }
                    }
                    Label {
                        text: I18n.tr("Версии для Windows работают через Proton и могут вести себя хуже родных. Обычно лучше Steam для Linux и браузер из магазина Delta — а эти нужны, если программа или игра просит именно их внутри Box")
                        tone: 3; size: "small"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Repeater {
                            model: [
                                { id: "steam", title: "Steam " + I18n.tr("для Windows"), icon: "steam", sym: "gamepad", text: "Для игр, которым нужен Steam внутри Box" },
                                { id: "chrome", title: "Google Chrome " + I18n.tr("для Windows"), icon: "google-chrome", icon2: "chromium", sym: "globe", text: "Для программ, которым нужен браузер внутри Box" }
                            ]
                            delegate: GetTile {}
                        }
                    }

                    // --- система Windows ---
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        implicitHeight: sysCol.implicitHeight + 28
                        radius: 20
                        color: Theme.soft
                        border.width: 1
                        border.color: Theme.line
                        ColumnLayout {
                            id: sysCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                            spacing: 10
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                Sym { name: "windows"; size: 20; color: Theme.accent }
                                ColumnLayout {
                                    spacing: 0
                                    Layout.fillWidth: true
                                    Label { text: I18n.tr("Система Windows"); font.weight: Font.DemiBold; Layout.fillWidth: true }
                                    Label {
                                        text: win.db.ready ? I18n.tr("Занимает") + " " + win.db.size
                                            : I18n.tr("Создастся при первом запуске программы — около минуты")
                                        tone: 3; size: "small"; Layout.fillWidth: true; wrapMode: Text.WordWrap
                                    }
                                }
                                Btn { text: I18n.tr("Установить программу"); icon: "download"; onClicked: win.chooseFile("install", "", "") }
                                Btn { icon: "folder"; kind: "ghost"; onClicked: win.run(["delta-exe", "--folder", "delta-box"]) }
                                Btn { icon: "settings"; kind: "ghost"; onClicked: win.run(["delta-exe", "--winecfg", "delta-box"]) }
                            }
                            Label { text: I18n.tr("Чем запускать"); tone: 2; size: "small" }
                            Chips {
                                Layout.fillWidth: true
                                model: [{ value: "auto", label: I18n.tr("Авто") }]
                                    .concat(win.protons.map(p => ({ value: "proton:" + p.path, label: p.name })))
                                    .concat(win.db.runners?.wine ? [{ value: "wine", label: "Wine" }] : [])
                                current: win.db.runner
                                onPicked: v => { win.change(["delta-exe", "--set-runner", "delta-box", v]); Sounds.play("oobe-select", 60); }
                            }
                            Label {
                                text: I18n.tr("«Авто» — самый свежий Proton CachyOS (скачается сам). Сменить можно в любой момент: программы останутся на месте")
                                tone: 3; size: "small"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        }

        // --- выбор файла запуска ---
        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            visible: win.picking !== null
            color: Qt.rgba(0, 0, 0, 0.45)
            MouseArea { anchors.fill: parent; onClicked: win.picking = null }

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width - 60, 560)
                height: Math.min(parent.height - 60, pickCol.implicitHeight + 40)
                radius: 24
                color: Theme.glass
                border.width: 1
                border.color: Theme.line
                MouseArea { anchors.fill: parent }

                ColumnLayout {
                    id: pickCol
                    anchors { fill: parent; margins: 20 }
                    spacing: 12
                    Label { text: I18n.tr("Чем запускать") + " «" + (win.picking?.name ?? "") + "»"; size: "title"; Layout.fillWidth: true; elide: Text.ElideRight }
                    Label {
                        text: (win.picking?.exes ?? []).length ? I18n.tr("Обычно это самый большой файл с названием программы")
                            : I18n.tr("В папке нет файлов .exe — выберите файл сами")
                        tone: 3; size: "small"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: Math.min(contentHeight, 340)
                        clip: true
                        spacing: 4
                        model: win.picking?.exes ?? []
                        delegate: Rectangle {
                            id: ex
                            required property var modelData
                            width: ListView.view.width
                            height: 48
                            radius: 12
                            color: exHov.hovered ? Theme.soft2 : "transparent"
                            opacity: modelData.junk ? 0.55 : 1
                            HoverHandler { id: exHov; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    const n = win.picking.name;
                                    win.picking = null;
                                    win.change(["delta-box", "--set", n, ex.modelData.path]);
                                }
                            }
                            RowLayout {
                                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                spacing: 12
                                Sym { name: "file"; size: 18; color: ex.modelData.junk ? Theme.fg3 : Theme.accent }
                                ColumnLayout {
                                    spacing: 0
                                    Layout.fillWidth: true
                                    Label { text: ex.modelData.rel.split("/").pop(); elide: Text.ElideRight; Layout.fillWidth: true }
                                    Label { text: ex.modelData.rel; tone: 3; size: "caption"; font.family: Theme.fontMono; elide: Text.ElideMiddle; Layout.fillWidth: true; visible: ex.modelData.rel.indexOf("/") >= 0 }
                                }
                                Label { text: win.sizeText(ex.modelData.size); tone: 3; size: "small" }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Item { Layout.fillWidth: true }
                        Btn { text: I18n.tr("Отмена"); kind: "ghost"; onClicked: win.picking = null }
                        Btn {
                            text: I18n.tr("Другой файл…")
                            icon: "file"
                            onClicked: {
                                const n = win.picking.name;
                                const d = (win.db.apps.find(a => a.name === n) ?? {}).dir ?? "";
                                win.chooseFile("set", n, d);
                            }
                        }
                    }
                }
            }
        }
    }

    // delta-box ipc call box reload|quit|get steam — демо и проверки
    IpcHandler {
        target: "box"
        function reload(): void { win.reload(); }
        function get(id: string): void { win.getApp(id); }
        function quit(): void { Qt.quit(); }
    }

    Shortcut { sequence: "Escape"; onActivated: { if (win.picking) win.picking = null; else Qt.quit(); } }
    Shortcut { sequence: "F5"; onActivated: win.reload() }
}
