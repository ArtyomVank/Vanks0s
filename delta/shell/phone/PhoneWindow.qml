pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.common
import qs.common.ui

// «Телефон» (delta-phone): Android по проводу, быстрая отправка по Wi-Fi и
// Bluetooth. На телефон ничего ставить не нужно: Wi-Fi — страница в браузере
// по QR-коду. Всё настоящее делает delta-phone, окно показывает его строки JSON.
FloatingWindow {
    id: win

    property string tab: Quickshell.env("DELTA_PHONE_TAB") || "usb"   // usb · wifi · bt
    property var state: ({ adb: [], mtp: [], bt: [], btPowered: false, ip: "", tools: {} })
    property var files: []               // что отправляем
    // отправка: { name, index, total, percent } или null
    property var sending: null
    property string result: ""
    property bool resultBad: false
    // Wi-Fi
    property string url: ""
    property string qr: ""
    property string folder: ""
    property string wifiError: ""
    property var received: []
    // наушники и колонки файлы не принимают; неизвестные устройства оставляем,
    // если телефона среди сопряжённых не нашлось
    readonly property var btPhones: {
        const phones = state.bt.filter(d => d.phone);
        return phones.length ? phones : state.bt;
    }

    title: I18n.tr("Телефон")
    implicitWidth: 900
    implicitHeight: 640
    minimumSize: Qt.size(640, 600)
    color: "transparent"

    onClosed: Qt.quit()

    // на вкладке Wi-Fi снизу QR-код: список файлов короче
    readonly property int filesShown: tab === "wifi" ? 2 : 4

    function baseName(p) { return p.slice(p.lastIndexOf("/") + 1); }
    function open(cmd) { Quickshell.execDetached(cmd); }

    Process {
        id: statusProc
        running: true
        command: ["delta-phone", "status"]
        stdout: StdioCollector {
            onStreamFinished: { try { win.state = JSON.parse(text); } catch (e) {} }
        }
    }
    Timer {
        interval: 3000; repeat: true; running: win.visible
        onTriggered: if (!statusProc.running) statusProc.running = true
    }

    // выбор файлов
    Process {
        id: fileDlg
        command: ["zenity", "--file-selection", "--multiple", "--separator=\n", "--title=" + I18n.tr("Файлы для телефона")]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.split("\n").filter(x => x);
                if (!list.length) return;
                win.files = win.files.concat(list.filter(f => win.files.indexOf(f) === -1));
            }
        }
    }
    function removeFile(path) { files = files.filter(f => f !== path); }
    onFilesChanged: if (server.running) server.write(JSON.stringify({ files: files }) + "\n")

    // отправка по проводу или Bluetooth: события — строками JSON
    Process {
        id: sender
        stdout: SplitParser {
            onRead: line => {
                let e;
                try { e = JSON.parse(line); } catch (err) { return; }
                if (e.event === "file") win.sending = { name: e.name, index: e.index, total: e.total, percent: -1 };
                else if (e.event === "progress" && win.sending) win.sending = Object.assign({}, win.sending, { percent: e.percent });
                else if (e.event === "done") {
                    win.result = e.ok ? I18n.tr("Отправлено: файлы на телефоне") : I18n.tr("Отправить не получилось. Проверьте, что телефон подключён и разрешил передачу.");
                    win.resultBad = !e.ok;
                }
            }
        }
        onExited: {
            win.sending = null;
            Sounds.play(win.resultBad ? "dialog-warning" : "oobe-select", 60);
        }
    }
    function send(cmd, target) {
        if (sender.running || !files.length) return;
        result = "";
        sending = { name: "", index: 0, total: files.length, percent: -1 };
        sender.command = ["delta-phone", cmd, target].concat(files);
        sender.running = true;
    }

    // Wi-Fi: страница живёт, пока открыта вкладка; конец stdin — выход сервера
    Process {
        id: server
        running: win.tab === "wifi"
        command: ["delta-phone", "serve"]
        stdinEnabled: true
        onStarted: write(JSON.stringify({ files: win.files }) + "\n")
        stdout: SplitParser {
            onRead: line => {
                let e;
                try { e = JSON.parse(line); } catch (err) { return; }
                if (e.event === "ready") { win.url = e.url; win.qr = e.qr; win.folder = e.folder; win.wifiError = ""; }
                else if (e.event === "error") win.wifiError = e.error;
                else if (e.event === "received") {
                    win.received = [e.name].concat(win.received).slice(0, 20);
                    Sounds.play("oobe-select", 60);
                }
            }
        }
        onExited: { win.url = ""; win.qr = ""; }
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

            RowLayout {
                spacing: 14
                Layout.fillWidth: true
                Rectangle {
                    implicitWidth: 52; implicitHeight: 52; radius: 16
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2)
                    Sym { anchors.centerIn: parent; name: "send"; size: 26; color: Theme.accent }
                }
                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true
                    Label { text: I18n.tr("Телефон"); size: "h1"; Layout.fillWidth: true }
                    Label {
                        text: I18n.tr("Android по проводу и быстрая отправка файлов. На телефон ничего ставить не нужно.")
                        tone: 3; size: "small"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                }
            }

            Chips {
                Layout.fillWidth: true
                model: [{ value: "usb", label: I18n.tr("Провод") }, { value: "wifi", label: "Wi-Fi" }, { value: "bt", label: "Bluetooth" }]
                current: win.tab
                onPicked: v => { win.tab = v; win.result = ""; }
            }

            // --- файлы ---
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: filesCol.implicitHeight + 24
                radius: 16
                color: Theme.soft
                border.width: 1
                border.color: Theme.line
                ColumnLayout {
                    id: filesCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            Layout.fillWidth: true
                            text: win.files.length ? I18n.tr("Файлов для отправки: ") + win.files.length : I18n.tr("Файлы для отправки ещё не выбраны")
                            tone: 2
                        }
                        Btn { visible: win.files.length > 0; text: I18n.tr("Очистить"); kind: "ghost"; onClicked: win.files = [] }
                        Btn { text: I18n.tr("Выбрать файлы"); icon: "file"; kind: "accent"; onClicked: fileDlg.running = true }
                    }
                    Repeater {
                        model: win.files.slice(0, win.filesShown)
                        delegate: RowLayout {
                            id: fileRow
                            required property string modelData
                            Layout.fillWidth: true
                            Sym { name: "file"; size: 16; color: Theme.fg3 }
                            Label { Layout.fillWidth: true; text: win.baseName(fileRow.modelData); elide: Text.ElideMiddle; size: "small" }
                            Btn { icon: "close"; iconSize: 14; kind: "ghost"; onClicked: win.removeFile(fileRow.modelData) }
                        }
                    }
                    Label { visible: win.files.length > win.filesShown; text: I18n.tr("и ещё: ") + (win.files.length - win.filesShown); size: "small"; tone: 3 }
                }
            }

            // --- ход отправки и итог ---
            Label {
                visible: win.sending !== null || win.result !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: win.resultBad && !win.sending ? "#ff6b6b" : Theme.fg
                text: win.sending
                    ? I18n.tr("Отправляю") + (win.sending.name ? " " + win.sending.name + " (" + win.sending.index + "/" + win.sending.total + ")" : "…")
                      + (win.sending.percent >= 0 ? " — " + win.sending.percent + " %" : "")
                    : win.result
            }

            // --- провод ---
            Flickable {
                visible: win.tab === "usb"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: usbCol.implicitHeight
                ColumnLayout {
                    id: usbCol
                    width: parent.width
                    spacing: 8
                    ColumnLayout {
                        visible: !win.state.adb.length && !win.state.mtp.length
                        Layout.fillWidth: true
                        spacing: 6
                        Label { text: I18n.tr("Телефон не найден"); font.weight: Font.DemiBold }
                        Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            tone: 2; size: "small"
                            text: I18n.tr("Подключите телефон кабелем и в его уведомлении выберите «Передача файлов». Чтобы показывать экран телефона здесь, включите на нём «Отладку по USB» в настройках для разработчиков.")
                        }
                    }
                    Repeater {
                        model: win.state.adb
                        delegate: Rectangle {
                            id: adbRow
                            required property var modelData
                            readonly property bool ready: modelData.state === "device"
                            Layout.fillWidth: true
                            implicitHeight: 64
                            radius: 14
                            color: Theme.soft
                            RowLayout {
                                anchors { fill: parent; leftMargin: 14; rightMargin: 10 }
                                spacing: 10
                                Sym { name: "link"; size: 20; color: Theme.accent }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Label { text: adbRow.modelData.name; Layout.fillWidth: true; elide: Text.ElideRight }
                                    Label {
                                        text: adbRow.ready ? I18n.tr("Подключён, отладка по USB") : I18n.tr("Подтвердите отладку на экране телефона")
                                        size: "small"; tone: 3
                                    }
                                }
                                Btn {
                                    text: I18n.tr("Экран телефона"); icon: "monitor"
                                    enabled: adbRow.ready && win.state.tools.scrcpy === true
                                    onClicked: win.open(["delta-phone", "screen", adbRow.modelData.serial])
                                }
                                Btn {
                                    text: I18n.tr("Отправить"); icon: "send"; kind: "accent"
                                    enabled: adbRow.ready && win.files.length > 0 && !win.sending
                                    onClicked: win.send("adb-send", adbRow.modelData.serial)
                                }
                            }
                        }
                    }
                    Repeater {
                        model: win.state.mtp
                        delegate: Rectangle {
                            id: mtpRow
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 64
                            radius: 14
                            color: Theme.soft
                            RowLayout {
                                anchors { fill: parent; leftMargin: 14; rightMargin: 10 }
                                spacing: 10
                                Sym { name: "folder"; size: 20; color: Theme.accent }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Label { text: mtpRow.modelData.name; Layout.fillWidth: true; elide: Text.ElideRight }
                                    Label { text: I18n.tr("Передача файлов"); size: "small"; tone: 3 }
                                }
                                Btn {
                                    text: I18n.tr("Открыть память"); icon: "folder"
                                    onClicked: win.open(["delta-phone", "mtp-open", mtpRow.modelData.uri])
                                }
                                Btn {
                                    text: I18n.tr("Отправить"); icon: "send"; kind: "accent"
                                    enabled: win.files.length > 0 && !win.sending
                                    onClicked: win.send("mtp-send", mtpRow.modelData.uri)
                                }
                            }
                        }
                    }
                }
            }

            // --- Wi-Fi ---
            RowLayout {
                visible: win.tab === "wifi"
                Layout.fillWidth: true
                spacing: 20

                Rectangle {
                    visible: win.qr !== ""
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 240; implicitHeight: 240
                    radius: 16
                    color: "#ffffff"
                    Image {
                        anchors { fill: parent; margins: 8 }
                        source: win.qr ? "file://" + win.qr : ""
                        smooth: false
                        fillMode: Image.PreserveAspectFit
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 8
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.weight: Font.DemiBold
                        text: win.wifiError ? I18n.tr("Компьютер не подключён к домашней сети") : I18n.tr("Наведите камеру телефона на код")
                    }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        tone: 2; size: "small"
                        text: win.wifiError
                            ? I18n.tr("Подключите компьютер и телефон к одной сети Wi-Fi или роутеру и откройте эту вкладку снова.")
                            : I18n.tr("Телефон и компьютер должны быть в одной сети. На открывшейся странице можно скачать выбранные здесь файлы и отправить файлы с телефона на компьютер. Страница работает, пока открыта эта вкладка.")
                    }
                    Label { visible: win.url !== ""; Layout.fillWidth: true; text: win.url; size: "small"; tone: 3; elide: Text.ElideMiddle }
                    Btn {
                        visible: win.url !== ""
                        text: I18n.tr("Папка с полученными"); icon: "folder"
                        onClicked: win.open(["xdg-open", win.folder])
                    }
                    Label { visible: win.received.length > 0; text: I18n.tr("Получено:"); font.weight: Font.DemiBold; Layout.topMargin: 6 }
                    Repeater {
                        model: win.received.slice(0, 6)
                        delegate: Label {
                            required property string modelData
                            Layout.fillWidth: true
                            text: "✓ " + modelData
                            elide: Text.ElideMiddle
                            size: "small"
                        }
                    }
                }
            }

            Item { visible: win.tab === "wifi"; Layout.fillHeight: true }

            // --- Bluetooth ---
            Flickable {
                visible: win.tab === "bt"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: btCol.implicitHeight
                ColumnLayout {
                    id: btCol
                    width: parent.width
                    spacing: 8
                    ColumnLayout {
                        visible: !win.state.btPowered || !win.state.bt.length
                        Layout.fillWidth: true
                        spacing: 6
                        Label {
                            text: !win.state.btPowered ? I18n.tr("Bluetooth выключен") : I18n.tr("Нет сопряжённых телефонов")
                            font.weight: Font.DemiBold
                        }
                        Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            tone: 2; size: "small"
                            text: I18n.tr("Включите Bluetooth и сопрягите телефон в настройках, затем он появится здесь.")
                        }
                        Btn { text: I18n.tr("Настройки Bluetooth"); icon: "bluetooth"; onClicked: win.open(["delta-settings", "bluetooth"]) }
                    }
                    Repeater {
                        model: win.state.btPowered ? win.btPhones : []
                        delegate: Rectangle {
                            id: btRow
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 64
                            radius: 14
                            color: Theme.soft
                            RowLayout {
                                anchors { fill: parent; leftMargin: 14; rightMargin: 10 }
                                spacing: 10
                                Sym { name: "bluetooth"; size: 20; color: Theme.accent }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Label { text: btRow.modelData.name; Layout.fillWidth: true; elide: Text.ElideRight }
                                    Label {
                                        text: btRow.modelData.connected ? I18n.tr("Подключён") : I18n.tr("Сопряжён")
                                        size: "small"; tone: 3
                                    }
                                }
                                Btn {
                                    text: I18n.tr("Отправить"); icon: "send"; kind: "accent"
                                    enabled: win.files.length > 0 && !win.sending
                                    onClicked: win.send("bt-send", btRow.modelData.addr)
                                }
                            }
                        }
                    }
                    Label {
                        visible: win.state.btPowered && win.state.bt.length > 0
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        tone: 3; size: "small"
                        text: I18n.tr("После нажатия примите файл на экране телефона. Bluetooth медленный: для больших файлов удобнее Wi-Fi.")
                    }
                }
            }
        }
    }
}
