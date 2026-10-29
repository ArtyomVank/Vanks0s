pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.common
import qs.common.ui
import qs.walls
import "../../wallpaper/media.js" as Media

// Раздел «Обои»: папка, заполнение, видеообои, смена по таймеру.
ColumnLayout {
    id: root

    property string title: I18n.tr("Обои")
    property string icon: "image"
    property string keywords: "фон картинка видеообои папка заполнение таймер смена"
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
                onClicked: { Settings.set("wallpaper.video", false); Settings.set("wallpaper.path", ""); }
            }
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
