pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.common
import qs.common.ui
import qs.settings
import qs.settings.parts

// Обновления «по воздуху»: delta-update check проверяет пакеты Arch и новую
// версию Delta из релизов GitHub (систему не меняет). «Обновить» запускает
// pkexec delta-update apply — пароль спрашивает окно polkit, терминал не нужен,
// ход установки виден здесь же. Фоновая проверка с уведомлением — в оболочке
// (services/UpdateCheck.qml). В проверках (пробный режим) установка не идёт.
ColumnLayout {
    id: root

    property string title: "Обновления"
    property string icon: "download"
    property string keywords: "pacman пакеты обновить система checkupdates delta по воздуху автоматически"
    spacing: 18

    property var updates: []          // [{ name, from, to }]
    property bool checking: false
    property string error: ""
    readonly property string lastCheck: Settings.get("updates.lastCheck", "")
    property string deltaVersion: ""

    // установка
    property bool installing: false
    property string stage: ""         // текущий этап (::step::)
    property string lastLine: ""      // последняя строка pacman
    property bool needReboot: false
    property bool done: false

    readonly property var deltaUpdate: updates.find(u => u.name === "delta") || null

    function plural(n) {
        const a = n % 10, b = n % 100;
        return n + " " + (a === 1 && b !== 11 ? "пакет" : a >= 2 && a <= 4 && (b < 12 || b > 14) ? "пакета" : "пакетов");
    }
    function when(iso) {
        if (!iso) return "ещё не проверялось";
        const d = new Date(iso), now = new Date();
        const same = d.toDateString() === now.toDateString();
        return (same ? "сегодня в " : d.toLocaleDateString(Qt.locale("ru_RU"), "d MMMM") + " в ") + Qt.formatTime(d, "HH:mm");
    }

    function check() {
        if (checking || installing) return;
        checking = true;
        error = "";
        // 0 — есть обновления, 2 — нет, 1 — нет связи
        Exec.read(["delta-update", "check"], (code, out, err) => {
            checking = false;
            if (code === 127) { error = "Нет delta-update — переустановите пакет delta"; return; }
            if (code !== 0 && code !== 2) { error = "Не удалось проверить: " + (err.trim().split("\n").pop() || "нет интернета?"); return; }
            const list = [];
            for (const l of out.split("\n")) {
                const m = l.match(/^(\S+)\s+(\S+)\s+->\s+(\S+)/);
                if (m) list.push({ name: m[1], from: m[2], to: m[3] });
            }
            updates = list;
            Settings.set("updates.lastCheck", new Date().toISOString());
            Settings.set("updates.available", list.length);
        });
        Exec.read(["sh", "-c", "pacman -Q delta 2>/dev/null | cut -d' ' -f2"], (code, out) => deltaVersion = out.trim());
    }
    Component.onCompleted: check()

    function install() {
        if (installing) return;
        installing = true;
        done = false;
        needReboot = false;
        error = "";
        stage = "Ждём пароль администратора";
        lastLine = "";
        if (Exec.dryRun) {
            // пробный режим: путь интерфейса без установки
            Exec.run(["pkexec", "delta-update", "apply"], { label: "установка обновлений", done: () => finish(0, "") });
            return;
        }
        apply.running = true;
    }
    function finish(code, err) {
        installing = false;
        if (code === 0) {
            done = true;
            stage = "Готово";
            updates = [];
            Settings.set("updates.available", 0);
            Nav.toast(needReboot ? "Обновления установлены — перезагрузите компьютер" : "Обновления установлены");
        } else if (code === 126 || code === 127) {
            stage = "";
            Nav.toast("Установка отменена");
        } else {
            stage = "";
            error = err || "Установка не удалась";
        }
    }

    Process {
        id: apply
        command: ["pkexec", "delta-update", "apply"]
        property string errText: ""
        onStarted: errText = ""
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("::step:: ")) root.stage = line.slice(9);
                else if (line === "::reboot::") root.needReboot = true;
                else if (line.trim().length) root.lastLine = line.trim();
            }
        }
        stderr: SplitParser { onRead: line => { if (line.trim().length) apply.errText = line.trim(); } }
        onExited: code => root.finish(code, apply.errText)
    }

    // --- состояние ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: col.implicitHeight + 40
        radius: Theme.radius - 2
        color: Theme.soft
        border.color: Theme.line
        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 22; rightMargin: 22 }
            spacing: 14
            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                Rectangle {
                    readonly property color c: root.error ? "#E5484D" : root.installing || root.updates.length ? Theme.accent : "#3FB37A"
                    implicitWidth: 48; implicitHeight: 48; radius: 24
                    color: Qt.rgba(c.r, c.g, c.b, 0.2)
                    Sym {
                        anchors.centerIn: parent
                        name: root.checking || root.installing ? "refresh" : root.error ? "warning" : root.updates.length ? "download" : "check"
                        size: 24
                        color: parent.c
                        RotationAnimation on rotation { running: root.checking || root.installing; from: 0; to: 360; duration: 1200; loops: Animation.Infinite; alwaysRunToEnd: true }
                        rotation: 0
                    }
                }
                ColumnLayout {
                    spacing: 3
                    Layout.fillWidth: true
                    Label {
                        text: root.installing ? root.stage
                            : root.checking ? "Проверяем обновления…"
                            : root.error ? "Не получилось"
                            : root.done && root.needReboot ? "Обновлено — нужна перезагрузка"
                            : root.updates.length ? "Доступно обновлений: " + root.plural(root.updates.length)
                            : "Система обновлена"
                        size: "title"
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Label {
                        text: root.installing ? (root.lastLine || "Не выключайте компьютер")
                            : root.error || (root.deltaUpdate ? "Вышла Delta " + root.deltaUpdate.to + " · " : "")
                                + "Последняя проверка: " + root.when(root.lastCheck)
                        tone: 3; size: "small"; Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
                Btn { text: "Проверить"; icon: "refresh"; visible: !root.installing && !(root.done && root.needReboot); enabled: !root.checking; onClicked: root.check() }
                Btn { text: "Обновить"; kind: "accent"; visible: root.updates.length > 0 && !root.installing; enabled: !root.checking; onClicked: root.install() }
                Btn { text: "Перезагрузить"; kind: "accent"; visible: root.done && root.needReboot; onClicked: Exec.run(["systemctl", "reboot"], { label: "перезагрузка" }) }
            }
            // бегущая полоса, пока идёт установка
            Rectangle {
                visible: root.installing
                Layout.fillWidth: true
                implicitHeight: 4
                radius: 2
                color: Theme.soft2
                clip: true
                Rectangle {
                    width: parent.width * 0.3
                    height: parent.height
                    radius: 2
                    color: Theme.accent
                    NumberAnimation on x {
                        running: root.installing
                        from: -parent.width * 0.3; to: parent.width
                        duration: 1400; loops: Animation.Infinite
                        easing.type: Easing.InOutSine
                    }
                }
            }
        }
    }

    Card {
        title: "Пакеты"
        visible: root.updates.length > 0
        Rows {
            Repeater {
                model: root.updates.slice(0, 200)
                delegate: SettingRow {
                    id: up
                    required property var modelData
                    icon: up.modelData.name === "delta" ? "dock" : ""
                    title: up.modelData.name === "delta" ? "Delta (рабочий стол)" : up.modelData.name
                    RowLayout {
                        spacing: 6
                        Label { text: up.modelData.from; tone: 3; size: "small" }
                        Sym { name: "chevron-right"; size: 12; color: Theme.fg3 }
                        Label { text: up.modelData.to; size: "small"; font.weight: Font.DemiBold }
                    }
                }
            }
        }
    }

    Card {
        title: "Автоматически"
        SettingRow {
            icon: "bell"
            title: "Проверять обновления"
            subtitle: "Система сама сообщит, когда выйдет что-то новое"
            Toggle { checked: Settings.get("updates.auto", true) !== false; onToggled: v => Settings.set("updates.auto", v) }
        }
        SettingRow {
            icon: "info"
            title: "Как это работает"
            subtitle: "Обновляются программы Arch и сама Delta" + (root.deltaVersion ? " (сейчас " + root.deltaVersion + ")" : "")
                + ". Нужен только пароль администратора. После обновления ядра, драйвера или Hyprland компьютер попросит перезагрузку."
        }
    }

    Connections {
        target: Nav
        function onAction(name, arg) {
            if (name === "updates.check") root.check();
            else if (name === "updates.install") root.install();
            else if (name === "updates.fake") root.updates = [{ name: "linux", from: "6.17.1", to: "6.17.2" }, { name: "delta", from: "0.1.0-1", to: "0.3.0-1" }, { name: "firefox", from: "144.0", to: "144.0.1" }];
        }
    }
}
