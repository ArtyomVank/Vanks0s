pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.common
import qs.common.ui
import qs.walls
import qs.wallpaper
import "../../wallpaper/media.js" as Media

// Раздел «Обои»: папка, заполнение, видеообои, смена по таймеру.
ColumnLayout {
    id: root

    property string title: I18n.tr("Обои")
    property string icon: "image"
    property string keywords: "фон картинка видеообои папка заполнение таймер смена супер живые чёрная дыра луна"
    spacing: 18

    readonly property string current: Settings.get("wallpaper.path", "")
    Component.onCompleted: WallStore.scan()

    // выбор папки через zenity (если есть)
    Process {
        id: chooser
        command: ["sh", "-c", "zenity --file-selection --directory --title='Папка с обоями' --filename=\"$1/\"", "sh", WallStore.folder]
        stdout: StdioCollector { id: chosen }
        onExited: code => { if (code === 0 && chosen.text.trim()) Settings.set("wallpaper.folder", chosen.text.trim()); }
    }
    property bool hasZenity: false
    Process {
        running: true
        command: ["sh", "-c", "command -v zenity"]
        onExited: code => root.hasZenity = code === 0
    }

    Card {
        title: I18n.tr("Сейчас")
        SettingRow {
            icon: root.current && Media.isVideo(root.current) ? "video" : "image"
            title: root.current ? Media.baseName(root.current) : "Градиент темы"
            subtitle: root.current ? WallStore.pretty(root.current) : "Файл не выбран — фон рисуется из цвета темы и акцента"
            Btn {
                visible: root.current.length > 0
                text: I18n.tr("Убрать")
                kind: "ghost"
                onClicked: { Settings.set("wallpaper.super", ""); Settings.set("wallpaper.video", false); Settings.set("wallpaper.path", ""); }
            }
        }
        SettingRow {
            icon: "plus"
            title: I18n.tr("Добавить свои обои")
            subtitle: I18n.tr("Картинки и видео копируются в папку с обоями, первый файл сразу ставится на стол")
            Btn { text: I18n.tr("Выбрать файлы"); icon: "image"; kind: "soft"; enabled: root.hasZenity; onClicked: WallStore.addFiles() }
        }
        SettingRow {
            icon: "keyboard"
            title: I18n.tr("Быстрый выбор обоев")
            subtitle: I18n.tr("Все обои с поиском и подборкой по цвету")
            Row {
                spacing: 6
                Repeater {
                    model: ["Super", "S"]
                    delegate: Rectangle {
                        required property string modelData
                        width: k.implicitWidth + 14; height: 24; radius: 6
                        color: Theme.soft2
                        Label { id: k; anchors.centerIn: parent; text: parent.modelData; size: "caption"; tone: 2; font.weight: Font.DemiBold }
                    }
                }
            }
        }
    }

    // плитка супер или живых обоев: снимок сцены, название, выбрана ли
    component SuperTile: Rectangle {
        id: tile
        required property var wall
        readonly property bool sel: SuperWalls.currentId === wall.id
        width: 150
        height: 92
        radius: 12
        color: Theme.soft2
        border.width: sel ? 2.5 : 1
        border.color: sel ? Theme.accent : Theme.line
        Image {
            anchors { fill: parent; margins: tile.border.width }
            source: Media.fileUrl(SuperWalls.still(tile.wall))
            sourceSize: Qt.size(300, 184)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 6 }
            height: 22
            radius: 8
            color: Qt.rgba(0, 0, 0, 0.5)
            Label {
                anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                text: tile.wall.id.startsWith("user:") ? tile.wall.title : I18n.tr(tile.wall.title)
                size: "caption"
                color: "#ffffff"
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: SuperWalls.apply(tile.wall) }
    }

    // свои супер обои: окна выбора файлов и ffmpeg — в delta-superwall
    property string creating: ""
    property string createError: ""
    Process {
        id: creator
        stdout: StdioCollector { id: created }
        stderr: StdioCollector { id: createdErr }
        onExited: code => {
            root.creating = "";
            root.createError = code === 0 || code === 3 ? "" : (createdErr.text.trim() || I18n.tr("Не получилось"));
            if (code !== 0) return;
            try { SuperWalls.apply(JSON.parse(created.text)); } catch (e) {}
            SuperWalls.reload();
        }
    }
    function create(kind) {
        if (creator.running) return;
        creating = kind;
        createError = "";
        creator.command = ["delta-superwall", "new", kind];
        creator.running = true;
    }

    Card {
        title: I18n.tr("Супер обои")
        Label {
            Layout.fillWidth: true
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            text: I18n.tr("На экране блокировки они видны издалека, а при входе на рабочий стол камера летит к ним.")
            size: "small"
            tone: 2
            wrapMode: Text.WordWrap
        }
        Flow {
            Layout.fillWidth: true
            Layout.margins: 12
            spacing: 10
            Repeater {
                model: SuperWalls.builtin.concat(SuperWalls.user)
                delegate: SuperTile {
                    required property var modelData
                    wall: modelData
                }
            }
        }
        SettingRow {
            icon: "play"
            title: I18n.tr("Анимация на рабочем столе")
            subtitle: I18n.tr("Обои движутся всё время, а не только при входе. Постоянно занимает видеокарту, поэтому в окне на весь экран анимация останавливается")
            Toggle { checked: SuperWalls.animated; onToggled: v => Settings.set("wallpaper.superAnimated", v) }
        }
        SettingRow {
            icon: "plus"
            title: I18n.tr("Сделать свои")
            subtitle: root.createError || (root.creating === "video" || root.creating === "live" ? I18n.tr("Готовлю видео, это займёт несколько секунд")
                : I18n.tr("Два фото: первое на блокировке, второе на столе. Видео: начало на блокировке, конец на столе. Анимированные: ролик до 30 секунд крутится по кругу"))
            Row {
                spacing: 8
                Btn { text: I18n.tr("Из двух фото"); icon: "image"; kind: "soft"; enabled: root.hasZenity && root.creating === ""; onClicked: root.create("photos") }
                Btn { text: I18n.tr("Из видео"); icon: "video"; kind: "soft"; enabled: root.hasZenity && root.creating === ""; onClicked: root.create("video") }
                Btn { text: I18n.tr("Анимированные"); icon: "play"; kind: "soft"; enabled: root.hasZenity && root.creating === ""; onClicked: root.create("live") }
            }
        }
        SettingRow {
            readonly property var mine: SuperWalls.current && SuperWalls.current.id.startsWith("user:") ? SuperWalls.current : null
            visible: mine !== null
            icon: "trash"
            title: I18n.tr("Удалить выбранные свои обои")
            subtitle: mine ? mine.title : ""
            Btn { text: I18n.tr("Удалить"); kind: "ghost"; onClicked: SuperWalls.removeUser(parent.mine) }
        }
    }

    Card {
        title: I18n.tr("Живые обои")
        Label {
            Layout.fillWidth: true
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            text: I18n.tr("Оживают, когда вы входите на рабочий стол: после включения компьютера и после каждой разблокировки. Потом замирают и не нагружают видеокарту.")
            size: "small"
            tone: 2
            wrapMode: Text.WordWrap
        }
        Repeater {
            model: SuperWalls.groups
            delegate: ColumnLayout {
                id: family
                required property var modelData
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                Layout.topMargin: 6
                spacing: 8
                Label { text: I18n.tr(family.modelData.title); font.weight: Font.DemiBold; size: "small" }
                Flow {
                    Layout.fillWidth: true
                    spacing: 10
                    Repeater {
                        model: SuperWalls.flows.filter(w => w.group === family.modelData.id)
                        delegate: SuperTile {
                            required property var modelData
                            wall: modelData
                        }
                    }
                }
            }
        }
        Item { Layout.preferredHeight: 4 }
        SettingRow {
            visible: SuperWalls.current !== null && SuperWalls.current.kind === "flow"
            icon: "refresh"
            title: I18n.tr("Показать ещё раз")
            Btn { text: I18n.tr("Показать"); kind: "soft"; onClicked: SuperWalls.playIntro() }
        }
    }

    Card {
        title: I18n.tr("Папка")
        SettingRow {
            icon: "folder"
            title: WallStore.pretty(WallStore.folder) || "—"
            readonly property var own: WallStore.items.filter(i => !i.system)
            subtitle: WallStore.folderMissing ? "Папка не найдена"
                : own.length ? "Файлов: " + own.length + " · фото " + own.filter(i => !i.video).length + ", видео " + own.filter(i => i.video).length
                : "Картинки и видео из папки и вложенных папок"
            Row {
                spacing: 8
                Btn { visible: root.hasZenity; text: I18n.tr("Выбрать папку…"); onClicked: chooser.running = true }
                Btn {
                    text: I18n.tr("Мои обои")
                    kind: "ghost"
                    onClicked: Settings.set("wallpaper.folder", "~/Pictures/Wallpapers")
                }
                Btn {
                    visible: String(Settings.get("wallpaper.folder", "")).length > 0
                    text: I18n.tr("По умолчанию")
                    kind: "ghost"
                    onClicked: Settings.set("wallpaper.folder", "")
                }
            }
        }
        SettingRow {
            icon: "image"
            title: I18n.tr("Обои Vanks OS")
            readonly property int count: WallStore.items.filter(i => i.system).length
            subtitle: count ? "Ещё " + count + " обоев рядом с вашими" : "Набор обоев, который идёт с системой"
            Toggle {
                checked: WallStore.showSystem
                onToggled: v => Settings.set("wallpaper.system", v)
            }
        }
        SettingRow {
            title: I18n.tr("Путь")
            subtitle: I18n.tr("Впишите путь и нажмите Enter")
            wide: true
            Rectangle {
                implicitHeight: 38
                radius: 10
                color: Theme.soft2
                border.width: 1
                border.color: path.activeFocus ? Theme.accent : Theme.line
                TextInput {
                    id: path
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 14
                    clip: true
                    selectByMouse: true
                    text: WallStore.folder
                    onAccepted: if (text.trim()) Settings.set("wallpaper.folder", text.trim())
                }
            }
        }
    }

    // несколько последних файлов из папки — кликом можно поставить
    Card {
        title: I18n.tr("Из папки")
        visible: WallStore.items.length > 0
        Item {
            Layout.fillWidth: true
            implicitHeight: strip.height + 24
            Flow {
                id: strip
                x: 12; y: 12
                width: parent.width - 24
                spacing: 10
                Repeater {
                    model: WallStore.items.slice(0, 8)
                    delegate: ClippingRectangle {
                        id: th
                        required property var modelData
                        width: (strip.width - 30) / 4
                        height: width * 9 / 16
                        radius: 12
                        color: Theme.soft2
                        border.width: 2
                        border.color: modelData.path === root.current ? Theme.accent : Theme.line
                        contentUnderBorder: true
                        Image {
                            anchors.fill: parent
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(384, 216)
                            source: WallStore.thumbs[th.modelData.key] ? Media.fileUrl(th.modelData.thumb) : ""
                        }
                        Sym {
                            visible: th.modelData.video
                            x: 8; y: 8
                            name: "video"; size: 16; color: "#ffffff"
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: WallStore.apply(th.modelData) }
                    }
                }
            }
        }
    }

    Card {
        title: I18n.tr("Отображение")
        SettingRow {
            icon: "scale"
            title: I18n.tr("Заполнение")
            subtitle: I18n.tr("Обрезать края или показать картинку целиком")
            Chips {
                current: Settings.get("wallpaper.fill", "cover")
                model: [{ value: "cover", label: I18n.tr("Заполнить") }, { value: "contain", label: I18n.tr("Вписать") }]
                onPicked: v => Settings.set("wallpaper.fill", v)
            }
        }
        SettingRow {
            icon: "video"
            title: I18n.tr("Видеообои")
            subtitle: I18n.tr("Если выключить, останется неподвижный кадр")
            Toggle {
                checked: Settings.get("wallpaper.allowVideo", true) !== false
                onToggled: v => Settings.set("wallpaper.allowVideo", v)
            }
        }
        SettingRow {
            icon: "battery"
            title: I18n.tr("Пауза видео от батареи")
            subtitle: I18n.tr("Бережёт батарею ноутбука")
            Toggle {
                checked: Settings.get("wallpaper.pauseOnBattery", true) !== false
                onToggled: v => Settings.set("wallpaper.pauseOnBattery", v)
            }
        }
    }

    Card {
        title: I18n.tr("Смена обоев")
        SettingRow {
            icon: "clock"
            title: I18n.tr("Менять по таймеру")
            subtitle: I18n.tr("Обои сменятся сами через выбранное время")
            wide: true
            Chips {
                current: Number(Settings.get("wallpaper.rotate", 0)) || 0
                model: [{ value: 0, label: I18n.tr("Не менять") }, { value: 15, label: I18n.tr("15 минут") }, { value: 30, label: I18n.tr("30 минут") },
                        { value: 60, label: I18n.tr("1 час") }, { value: 180, label: I18n.tr("3 часа") }, { value: 1440, label: I18n.tr("Раз в день") }]
                onPicked: v => Settings.set("wallpaper.rotate", v)
            }
        }
    }
}
