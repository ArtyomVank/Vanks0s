pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.common
import qs.common.ui
import qs.lock.parts
import qs.widgets
import qs.walls

// Экран блокировки: виджеты, часы, уведомления, блокировка при входе и по простою.
// «Настройки» — отдельный процесс, поэтому в оболочку — через IPC (delta-shell ipc call lock …).
ColumnLayout {
    id: root

    property string title: I18n.tr("Экран блокировки")
    property string icon: "lock"
    property string keywords: "блокировка вход часы виджеты уведомления пароль простой автовход экран входа обои фон картинка"
    spacing: 18

    // Часы экрана блокировки: значение — у виджета «Часы» его сетки, если он
    // там стоит (его меняет и редактор виджетов), иначе lock.clock.*, иначе
    // общее clock.*. Пишем и туда, и туда — настройки и редактор совпадают.
    readonly property var lockClock: (Settings.get("widgets.lock", []) || []).find(x => x && x.id === "clock") || null
    function clockGet(key, def) { return WidgetTypes.clockValue(root.lockClock, key, Settings.get("lock.clock." + key, Settings.get("clock." + key, def))); }
    readonly property string clockStyle: clockGet("style", "ios")
    readonly property real tallWidth: Number(clockGet("tallWidth", 0.62)) || 0.62
    readonly property string clockColor: clockGet("color", "white")
    readonly property string tallKind: clockGet("tallKind", "line")
    readonly property real tallThick: Number(clockGet("tallThick", 1)) || 1

    function setClock(key, value) {
        Settings.set("lock.clock." + key, value);
        const list = Settings.get("widgets.lock", []);
        if (!Array.isArray(list) || !list.some(w => w && w.id === "clock")) return;
        Settings.set("widgets.lock", list.map(w => {
            if (!w || w.id !== "clock") return w;
            const c = Object.assign({}, w);
            c[key] = value;
            return c;
        }));
    }

    // вид уведомлений: и для своих уведомлений экрана блокировки, и для
    // виджета «Уведомления» на его сетке, если он там стоит
    readonly property string notifView: {
        const w = (Settings.get("widgets.lock", []) || []).find(x => x && x.id === "notifs");
        return (w && w.mode) || Settings.get("notifications.lockView", "stack");
    }
    function setNotifView(v) {
        Settings.set("notifications.lockView", v);
        const list = Settings.get("widgets.lock", []);
        if (!Array.isArray(list) || !list.some(w => w && w.id === "notifs")) return;
        Settings.set("widgets.lock", list.map(w => w && w.id === "notifs" ? Object.assign({}, w, { mode: v }) : w));
    }

    function shell(args) { Quickshell.execDetached(["delta-shell", "ipc", "call", "lock"].concat(args)); }

    // ---------- обои экрана блокировки ----------
    // lock.wallpaper: "" — как на рабочем столе, иначе путь к картинке
    readonly property string lockWall: Settings.get("lock.wallpaper", "") || ""
    readonly property var folderWalls: WallStore.items.filter(it => !it.video).slice(0, 24).map(it => it.path)
    property var systemWalls: []
    Component.onCompleted: { WallStore.scan(); sysProc.running = true; }

    // системные обои (пакеты кладут их в /usr/share/backgrounds)
    Process {
        id: sysProc
        command: ["sh", "-c", "find -L /usr/share/backgrounds /usr/share/wallpapers -maxdepth 4 -type f " +
            "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) 2>/dev/null | sort | head -n 48"]
        stdout: StdioCollector { onStreamFinished: root.systemWalls = text.split("\n").filter(l => l.length > 0) }
    }
    // свой файл — через zenity
    property bool noPicker: false
    Process {
        id: pickProc
        command: ["sh", "-c", "command -v zenity >/dev/null || exit 3; zenity --file-selection --title='Обои экрана блокировки' " +
            "--file-filter='Изображения | *.png *.jpg *.jpeg *.webp *.avif *.jxl *.bmp *.PNG *.JPG *.JPEG'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim();
                if (f.length) Settings.set("lock.wallpaper", f);
            }
        }
        onExited: code => root.noPicker = code === 3
    }

    component WallTile: Rectangle {
        id: tile
        property string path: ""
        property string label: ""
        readonly property bool sel: root.lockWall === path
        width: 132
        height: 82
        radius: 12
        color: Theme.soft2
        border.width: sel ? 2.5 : 1
        border.color: sel ? Theme.accent : Theme.line
        Image {
            anchors { fill: parent; margins: tile.border.width }
            visible: tile.path.length > 0
            source: tile.path ? "file://" + tile.path : ""
            sourceSize: Qt.size(264, 164)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
        }
        Rectangle {
            visible: tile.label.length > 0
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 6 }
            height: 22
            radius: 8
            color: Qt.rgba(0, 0, 0, 0.45)
            Label { anchors.centerIn: parent; text: tile.label; size: "caption"; color: "#ffffff"; font.weight: Font.DemiBold }
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: Settings.set("lock.wallpaper", tile.path) }
    }

    Card {
        title: I18n.tr("Вид")

        // предпросмотр часов на обоях
        Item {
            Layout.fillWidth: true
            implicitHeight: 200
            Rectangle {
                anchors { fill: parent; margins: 12 }
                radius: Theme.radius - 6
                clip: true
                color: Theme.base
                LockBackground { anchors.fill: parent }
                BigClock {
                    anchors.centerIn: parent
                    style: root.clockStyle
                    tint: root.clockColor
                    tallWidth: root.tallWidth
                    tallKind: root.tallKind
                    tallThick: root.tallThick
                    size: 96
                }
            }
        }
        SettingRow {
            icon: "clock"; title: I18n.tr("Стиль часов"); wide: true
            Chips {
                current: root.clockStyle
                model: [{ value: "ios", label: "iOS" }, { value: "thin", label: I18n.tr("Тонкие") }, { value: "mono", label: I18n.tr("Моно") },
                        { value: "neon", label: I18n.tr("Неон") }, { value: "stack", label: I18n.tr("Столбиком") },
                        { value: "serif", label: I18n.tr("С засечками") }, { value: "wide", label: I18n.tr("Разрядка") },
                        { value: "outline", label: I18n.tr("Контур") }, { value: "minimal", label: I18n.tr("Минимум") },
                        { value: "tall", label: I18n.tr("Длинные") }]
                onPicked: v => root.setClock("style", v)
            }
        }
        TallClockRows {
            visible: root.clockStyle === "tall"
            kind: root.tallKind
            widthRatio: root.tallWidth
            thick: root.tallThick
            onPicked: (key, v) => root.setClock(key, v)
        }
        SettingRow {
            icon: "palette"; title: I18n.tr("Цвет часов"); wide: true
            Chips {
                current: root.clockColor
                model: [{ value: "white", label: I18n.tr("Белые") }, { value: "accent", label: I18n.tr("Акцент") },
                        { value: "gradient", label: I18n.tr("Градиент") }, { value: "glass", label: I18n.tr("Стекло") }]
                onPicked: v => root.setClock("color", v)
            }
        }
        SettingRow {
            icon: "widgets"; title: I18n.tr("Виджеты экрана блокировки")
            subtitle: I18n.tr("Погода, календарь, музыка — расставляются как на рабочем столе")
            Btn { text: I18n.tr("Изменить"); icon: "edit"; onClicked: root.shell(["edit"]) }
        }
        SettingRow {
            icon: "lock"; title: I18n.tr("Посмотреть экран блокировки"); subtitle: I18n.tr("Заблокировать сейчас")
            Btn { text: I18n.tr("Показать"); onClicked: root.shell(["lock"]) }
        }
    }

    Card {
        title: I18n.tr("Обои")
        SettingRow {
            icon: "image"; title: I18n.tr("Обои экрана блокировки"); wide: true
            subtitle: I18n.tr("Можно поставить отдельную картинку. Для видеообоев покажем их кадр")
            Flow {
                Layout.fillWidth: true
                spacing: 8
                WallTile { path: ""; label: I18n.tr("Как на столе"); color: Theme.accent }
                // свой файл, которого нет в списках ниже
                WallTile {
                    visible: root.lockWall.length > 0 && root.systemWalls.indexOf(root.lockWall) === -1 && root.folderWalls.indexOf(root.lockWall) === -1
                    path: root.lockWall
                    label: I18n.tr("Свой")
                }
                Repeater { model: root.systemWalls; delegate: WallTile { required property string modelData; path: modelData; label: I18n.tr("Системные") } }
                Repeater { model: root.folderWalls; delegate: WallTile { required property string modelData; path: modelData } }
                Rectangle {
                    width: 132
                    height: 82
                    radius: 12
                    color: Theme.soft
                    border.width: 1
                    border.color: Theme.line
                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        Sym { anchors.horizontalCenter: parent.horizontalCenter; name: "folder"; size: 20; color: Theme.fg2 }
                        Label { anchors.horizontalCenter: parent.horizontalCenter; text: root.noPicker ? "Нет zenity" : "Свой файл…"; size: "caption"; tone: 2 }
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: if (!pickProc.running) pickProc.running = true }
                }
            }
        }
    }

    Card {
        title: I18n.tr("Уведомления")
        SettingRow {
            icon: "bell"; title: I18n.tr("Показывать на экране блокировки")
            subtitle: I18n.tr("Последние сообщения видно без пароля")
            Toggle { checked: Settings.get("notifications.onLock", true); onToggled: v => Settings.set("notifications.onLock", v) }
        }
        SettingRow {
            visible: Settings.get("notifications.onLock", true) !== false
            icon: "layers"; title: I18n.tr("Вид уведомлений"); wide: true
            subtitle: I18n.tr("Стопкой — раскрываются по нажатию, списком — друг под другом, числом — только сколько пришло")
            Chips {
                current: root.notifView
                model: [{ value: "stack", label: I18n.tr("Стопкой") }, { value: "list", label: I18n.tr("Списком") },
                        { value: "count", label: I18n.tr("Числом") }]
                onPicked: v => root.setNotifView(v)
            }
        }
    }

    Card {
        title: I18n.tr("Блокировка")
        SettingRow {
            icon: "clock"; title: I18n.tr("Блокировать после простоя"); wide: true
            Chips {
                current: Settings.get("power.lockAfter", 300)
                model: [{ value: 60, label: I18n.tr("1 мин") }, { value: 120, label: I18n.tr("2 мин") }, { value: 300, label: I18n.tr("5 мин") },
                        { value: 600, label: I18n.tr("10 мин") }, { value: 1800, label: I18n.tr("30 мин") }, { value: 0, label: I18n.tr("Никогда") }]
                onPicked: v => Settings.set("power.lockAfter", v)
            }
        }
        SettingRow {
            icon: "sleep"; title: I18n.tr("Блокировать перед сном")
            subtitle: I18n.tr("Проснувшись, компьютер попросит пароль")
            Toggle { checked: Settings.get("power.lockBeforeSleep", true); onToggled: v => Settings.set("power.lockBeforeSleep", v) }
        }
        SettingRow {
            icon: "unlock"; title: I18n.tr("Блокировать сразу после входа")
            subtitle: I18n.tr("Компьютер включается сразу на экран блокировки — удобно при входе без пароля")
            Toggle { checked: Settings.get("lock.onStart", false); onToggled: v => Settings.set("lock.onStart", v) }
        }
        SettingRow {
            icon: "eye"; title: I18n.tr("Плавный переход к рабочему столу")
            subtitle: I18n.tr("Рабочий стол плавно проступает, когда вы входите")
            Toggle { checked: Settings.get("lock.smoothTransitions", true); onToggled: v => Settings.set("lock.smoothTransitions", v) }
        }
    }

    Card {
        title: I18n.tr("Экран входа")
        SettingRow {
            icon: "image"; title: I18n.tr("Мои обои и тема на экране входа")
            subtitle: I18n.tr("Их увидит любой, кто включит компьютер")
            Toggle { checked: Settings.get("greeter.sync", true); onToggled: v => Settings.set("greeter.sync", v) }
        }
        SettingRow {
            icon: "widgets"; title: I18n.tr("Виджеты на экране входа")
            subtitle: I18n.tr("Часы, погода и календарь ещё до входа")
            Toggle { checked: Settings.get("greeter.widgets", true); onToggled: v => Settings.set("greeter.widgets", v) }
        }
    }
}
