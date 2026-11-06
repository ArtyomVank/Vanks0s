pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.common
import qs.common.ui

// «Android» (delta-android): приложения Android в своих окнах (Waydroid).
// Нет Android — установка в одно нажатие: с Google Play или без. Есть —
// сетка приложений, Google Play, установка APK и регистрация устройства
// в Google (без неё Play пишет «устройство не сертифицировано»). Всё
// настоящее делает delta-android, окно показывает его JSON и этапы.
FloatingWindow {
    id: win

    property var state: ({ installed: false, initialized: false, gapps: false, running: false })
    property bool loaded: false
    property var apps: []
    property bool gapps: true                 // что ставить: с Google Play или без
    property string step: ""                  // этап установки
    property string lastLine: ""
    property bool setupFailed: false
    property string busyPkg: ""
    property var reg: null                    // { id, url, error }
    readonly property bool ready: state.installed && state.initialized

    title: I18n.tr("Android")
    implicitWidth: 900
    implicitHeight: 640
    minimumSize: Qt.size(640, 560)
    color: "transparent"

    onClosed: Qt.quit()

    function refresh() {
        if (!statusProc.running) statusProc.running = true;
        if (!appsProc.running) appsProc.running = true;
    }

    Process {
        id: statusProc
        running: true
        command: ["delta-android", "status"]
        stdout: StdioCollector {
            onStreamFinished: { try { win.state = JSON.parse(text); win.loaded = true; } catch (e) {} }
        }
    }
    Process {
        id: appsProc
        running: true
        command: ["delta-android", "apps"]
        stdout: StdioCollector {
            onStreamFinished: { try { win.apps = JSON.parse(text); } catch (e) {} }
        }
    }
    Timer {
        interval: 4000; repeat: true; running: win.visible && !setup.running
        onTriggered: win.refresh()
    }

    // установка: строки ::step:: — этапы, остальное — вывод pacman и waydroid
    Process {
        id: setup
        command: ["delta-android", "setup", win.gapps ? "gapps" : "vanilla"]
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("::step:: ")) win.step = line.slice(9);
                else if (line.trim()) win.lastLine = line.trim();
            }
        }
        stderr: SplitParser { onRead: line => { if (line.trim()) win.lastLine = line.trim(); } }
        onStarted: { win.setupFailed = false; win.step = I18n.tr("Начинаю…"); win.lastLine = ""; }
        onExited: code => {
            win.setupFailed = code !== 0;
            if (code !== 0 && !win.lastLine) win.lastLine = I18n.tr("Установка отменена или не удалась");
            Sounds.play(code === 0 ? "oobe-select" : "dialog-warning", 60);
            win.refresh();
        }
    }

    // запуск приложения: Android поднимается сам (до минуты)
    Process {
        id: launcher
        onExited: { win.busyPkg = ""; win.refresh(); }
    }
    function launch(pkg) {
        if (launcher.running) return;
        busyPkg = pkg;
        launcher.command = ["delta-android", "launch", pkg];
        launcher.running = true;
    }

    Process {
        id: apkDlg
        command: ["zenity", "--file-selection", "--file-filter=APK | *.apk", "--title=" + I18n.tr("Приложение Android (.apk)")]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim();
                if (f) Quickshell.execDetached(["delta-android", "install", f]);
            }
        }
    }
    Process {
        id: idProc
        command: ["delta-android", "android-id"]
        stdout: StdioCollector { onStreamFinished: { try { win.reg = JSON.parse(text); } catch (e) {} } }
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

            // --- шапка ---
            RowLayout {
                spacing: 14
                Layout.fillWidth: true
                Rectangle {
                    implicitWidth: 52; implicitHeight: 52; radius: 16
                    color: Qt.rgba(0.24, 0.86, 0.52, 0.18)
                    Sym { anchors.centerIn: parent; name: "android"; size: 28; color: "#3DDC84" }
                }
                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true
                    Label { text: I18n.tr("Android"); size: "h1"; Layout.fillWidth: true }
                    Label {
                        text: I18n.tr("Приложения Android в своих окнах, рядом с обычными. Работает на Waydroid.")
                        tone: 3; size: "small"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                }
                Rectangle {
                    visible: win.ready
                    implicitWidth: stRow.implicitWidth + 24; implicitHeight: 32; radius: 16
                    color: win.state.running ? Qt.rgba(0.24, 0.86, 0.52, 0.18) : Theme.soft
                    Row {
                        id: stRow
                        anchors.centerIn: parent
                        spacing: 7
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: win.state.running ? "#3DDC84" : Theme.fg3 }
                        Label { anchors.verticalCenter: parent.verticalCenter; text: win.state.running ? I18n.tr("Android запущен") : I18n.tr("Android выключен"); size: "small"; font.weight: Font.DemiBold }
                    }
                }
            }

            // --- установка ---
            ColumnLayout {
                visible: win.loaded && !win.ready
                Layout.fillWidth: true
                spacing: 12

                Label {
                    text: win.state.installed ? I18n.tr("Осталось скачать сам Android") : I18n.tr("Android ещё не установлен")
                    size: "title"; font.weight: Font.Bold
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Repeater {
                        model: [
                            { gapps: true, icon: "store", title: I18n.tr("С Google Play"), text: I18n.tr("Магазин Google, вход в аккаунт, приложения с покупками и уведомлениями. Рекомендуется.") },
                            { gapps: false, icon: "android", title: I18n.tr("Без Google"), text: I18n.tr("Чистый LineageOS: меньше и тише, приложения — из файлов APK или F-Droid.") }
                        ]
                        delegate: Rectangle {
                            id: opt
                            required property var modelData
                            readonly property bool sel: win.gapps === modelData.gapps
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: optCol.implicitHeight + 28
                            radius: 16
                            color: optHov.hovered ? Theme.soft2 : Theme.soft
                            border.width: 2
                            border.color: sel ? Theme.accent : Theme.line
                            ColumnLayout {
                                id: optCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                                spacing: 6
                                RowLayout {
                                    spacing: 8
                                    Sym { name: opt.modelData.icon; size: 20; color: opt.sel ? Theme.accent : Theme.fg2 }
                                    Label { text: opt.modelData.title; font.weight: Font.Bold; Layout.fillWidth: true }
                                    Sym { visible: opt.sel; name: "check"; size: 16; color: Theme.accent }
                                }
                                Label { text: opt.modelData.text; size: "small"; tone: 3; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                            HoverHandler { id: optHov; cursorShape: Qt.PointingHandCursor }
                            TapHandler { enabled: !setup.running; onTapped: win.gapps = opt.modelData.gapps }
                        }
                    }
                }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    size: "small"; tone: 3
                    text: I18n.tr("Понадобится пароль и около 1,5 ГБ: пакет Waydroid из репозитория и образ Android с серверов проекта.")
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Btn {
                        text: setup.running ? I18n.tr("Устанавливаю…") : I18n.tr("Установить Android")
                        icon: "download"; kind: "accent"
                        enabled: !setup.running
                        onClicked: setup.running = true
                    }
                    ColumnLayout {
                        visible: win.step !== "" || win.lastLine !== ""
                        Layout.fillWidth: true
                        spacing: 0
                        Label { Layout.fillWidth: true; text: win.step; font.weight: Font.DemiBold; elide: Text.ElideRight }
                        Label {
                            Layout.fillWidth: true
                            text: win.lastLine
                            size: "caption"
                            color: win.setupFailed ? "#ff6b6b" : Theme.fg3
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // --- готово: приложения ---
            RowLayout {
                visible: win.ready
                Layout.fillWidth: true
                spacing: 8
                Btn {
                    visible: win.state.gapps
                    text: I18n.tr("Google Play"); icon: "store"; kind: "accent"
                    enabled: win.busyPkg === ""
                    onClicked: win.launch("com.android.vending")
                }
                Btn { text: I18n.tr("Установить APK"); icon: "download"; onClicked: apkDlg.running = true }
                Item { Layout.fillWidth: true }
                Btn {
                    visible: win.state.running
                    text: I18n.tr("Выключить Android"); icon: "power"; kind: "ghost"
                    onClicked: { Quickshell.execDetached(["delta-android", "stop"]); stopRefresh.restart(); }
                }
                Timer { id: stopRefresh; interval: 2500; onTriggered: win.refresh() }
            }

            Flickable {
                visible: win.ready
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: appsCol.implicitHeight
                ColumnLayout {
                    id: appsCol
                    width: parent.width
                    spacing: 14

                    Label {
                        visible: win.apps.length === 0
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        tone: 3
                        text: win.state.gapps ? I18n.tr("Приложений пока нет. Откройте Google Play, войдите в аккаунт Google и поставьте что нужно — они появятся здесь и в меню приложений.")
                                              : I18n.tr("Приложений пока нет. Установите файл APK — оно появится здесь и в меню приложений.")
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: Math.max(3, Math.floor(width / 120))
                        columnSpacing: 8
                        rowSpacing: 8
                        Repeater {
                            model: win.apps
                            delegate: Rectangle {
                                id: app
                                required property var modelData
                                readonly property bool busy: win.busyPkg === modelData.package
                                Layout.fillWidth: true
                                implicitHeight: 112
                                radius: 16
                                color: appHov.hovered ? Theme.soft2 : Theme.soft
                                scale: appTap.pressed ? 0.96 : 1
                                Behavior on scale { NumberAnimation { duration: Theme.anim.fast } }
                                Column {
                                    anchors.centerIn: parent
                                    width: parent.width - 16
                                    spacing: 8
                                    ClippingRectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 52; height: 52; radius: 16
                                        color: Qt.rgba(0.24, 0.86, 0.52, 0.16)
                                        Image {
                                            id: appImg
                                            anchors.fill: parent
                                            source: app.modelData.icon ? "file://" + app.modelData.icon : ""
                                            sourceSize: Qt.size(104, 104)
                                            visible: status === Image.Ready
                                            asynchronous: true
                                        }
                                        Sym {
                                            anchors.centerIn: parent
                                            visible: !appImg.visible
                                            name: app.modelData.package === "com.android.vending" ? "store" : "android"
                                            size: 26
                                            color: "#3DDC84"
                                        }
                                        Rectangle {
                                            anchors.fill: parent
                                            visible: app.busy
                                            color: Qt.rgba(0, 0, 0, 0.45)
                                            Label { anchors.centerIn: parent; text: "…"; color: "#ffffff"; font.weight: Font.Bold }
                                        }
                                    }
                                    Label {
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: app.modelData.name
                                        size: "small"
                                        font.weight: Font.DemiBold
                                    }
                                }
                                HoverHandler { id: appHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler { id: appTap; onTapped: win.launch(app.modelData.package) }
                            }
                        }
                    }

                    // --- Google Play: регистрация устройства ---
                    Rectangle {
                        visible: win.state.gapps
                        Layout.fillWidth: true
                        implicitHeight: regCol.implicitHeight + 28
                        radius: 16
                        color: Theme.soft
                        border.width: 1
                        border.color: Theme.line
                        ColumnLayout {
                            id: regCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                            spacing: 8
                            RowLayout {
                                spacing: 8
                                Sym { name: "shield"; size: 18; color: Theme.accent }
                                Label { text: I18n.tr("Google Play пишет «устройство не сертифицировано»?"); font.weight: Font.Bold; Layout.fillWidth: true }
                            }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                size: "small"; tone: 3
                                text: I18n.tr("Google пускает в Play только зарегистрированные устройства. Получите номер устройства, вставьте его на странице Google (войдите тем же аккаунтом) и через несколько минут выключите и снова откройте Android.")
                            }
                            RowLayout {
                                spacing: 8
                                Btn {
                                    text: idProc.running ? I18n.tr("Узнаю номер…") : I18n.tr("Номер устройства")
                                    icon: "key"
                                    enabled: !idProc.running
                                    onClicked: idProc.running = true
                                }
                                Label {
                                    visible: (win.reg?.id ?? "") !== ""
                                    text: win.reg?.id ?? ""
                                    num: true
                                    font.family: Theme.fontMono
                                    font.weight: Font.Bold
                                }
                                Btn {
                                    visible: (win.reg?.id ?? "") !== ""
                                    text: I18n.tr("Скопировать"); icon: "copy"; kind: "ghost"
                                    onClicked: Quickshell.execDetached(["wl-copy", win.reg.id])
                                }
                                Btn {
                                    text: I18n.tr("Страница регистрации"); icon: "globe"; kind: "ghost"
                                    onClicked: Quickshell.execDetached(["xdg-open", win.reg?.url || "https://www.google.com/android/uncertified"])
                                }
                            }
                            Label {
                                visible: (win.reg?.error ?? "") !== ""
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: win.reg?.error ?? ""
                                size: "small"
                                color: "#ff9f0a"
                            }
                        }
                    }
                }
            }

            Item { visible: !win.ready; Layout.fillHeight: true }
        }
    }
}
