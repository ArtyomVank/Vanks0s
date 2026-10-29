pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common
import qs.common.ui
import qs.settings
import qs.settings.parts

// О системе: версии, железо, диски, экраны, имя компьютера.
// Сведения собирает helpers/sysinfo (только чтение), переименование —
// hostnamectl (hostnamed спросит пароль через polkit; в проверках — журнал).
ColumnLayout {
    id: root

    property string title: I18n.tr("О системе")
    property string icon: "info"
    property string keywords: "система версия процессор видеокарта память диск имя компьютера ядро время работы экран"
    spacing: 18

    property var info: ({})
    property var monitors: []
    property bool loaded: false

    function bytes(n) {
        if (!n) return "—";
        const u = ["Б", "КБ", "МБ", "ГБ", "ТБ"];
        let i = 0, v = n;
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
        return (v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)).toString().replace(".", ",") + " " + u[i];
    }
    function plural(n, one, few, many) {
        const a = n % 10, b = n % 100;
        return n + " " + (a === 1 && b !== 11 ? one : a >= 2 && a <= 4 && (b < 12 || b > 14) ? few : many);
    }
    function uptime(s) {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        const p = [];
        if (d) p.push(plural(d, "день", "дня", "дней"));
        if (h) p.push(plural(h, "час", "часа", "часов"));
        if (!d) p.push(plural(m, "минута", "минуты", "минут"));
        return p.join(" ");
    }
    readonly property var screens: monitors.length
        ? monitors.map(m => ({ name: m.name, text: m.width + "×" + m.height + " · " + Math.round(m.refreshRate) + " Гц" + (m.scale !== 1 ? " · " + Math.round(m.scale * 100) + " %" : ""), model: (m.make + " " + m.model).trim() }))
        : Quickshell.screens.map(s => ({ name: s.name, text: Math.round(s.width * s.devicePixelRatio) + "×" + Math.round(s.height * s.devicePixelRatio), model: s.model || "" }))

    function refresh() {
        Exec.read(["bash", Exec.helper("sysinfo")], (code, out) => {
            try { root.info = JSON.parse(out); root.loaded = true; } catch (e) { console.warn("[delta-settings] sysinfo: " + e); }
        });
        Exec.read(["hyprctl", "monitors", "-j"], (code, out) => {
            try { root.monitors = JSON.parse(out); } catch (e) { root.monitors = []; }
        });
    }
    Component.onCompleted: refresh()
    // время работы идёт — обновляем, пока раздел открыт
    Timer { interval: 60000; repeat: true; running: Nav.current === "about"; onTriggered: root.refresh() }

    // --- шапка ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 128
        radius: Theme.radius - 2
        color: Theme.soft
        border.color: Theme.line
        RowLayout {
            anchors { fill: parent; margins: 22 }
            spacing: 20
            Rectangle {
                id: logo
                implicitWidth: 76; implicitHeight: 76; radius: 22
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.2) }
                    GradientStop { position: 1; color: Qt.darker(Theme.accent, 1.3) }
                }
                Label { anchors.centerIn: parent; text: "V"; color: Theme.onAccent; font.pixelSize: 40; font.weight: Font.Black }

                // пасхалка: пять щелчков подряд по значку
                property int taps: 0
                scale: logoTap.pressed ? 0.88 : 1
                Behavior on scale { NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.OutBack; easing.overshoot: 3 } }
                Timer { id: tapReset; interval: 1200; onTriggered: logo.taps = 0 }
                RotationAnimation { id: spin; target: logo; from: 0; to: 360; duration: 900; easing.type: Easing.OutBack }
                MouseArea {
                    id: logoTap
                    anchors.fill: parent
                    onClicked: {
                        logo.taps++;
                        tapReset.restart();
                        Sounds.play(logo.taps >= 5 ? "oobe-done" : "pop", 0);
                        if (logo.taps < 5) return;
                        logo.taps = 0;
                        spin.restart();
                        const p = logo.mapToItem(boom, logo.width / 2, logo.height / 2);
                        boom.burst(p.x, p.y);
                        Nav.toast(I18n.tr("Спасибо, что вы с Vanks OS!"));
                    }
                }
            }
            ColumnLayout {
                spacing: 4
                Layout.fillWidth: true
                Label { text: (root.info.os || "Vanks OS") + (root.info.version ? " " + root.info.version : ""); size: "h1"; Layout.fillWidth: true }
                Label { text: I18n.tr("Окружение Delta ") + (root.info.delta || ""); tone: 2 }
                Label { text: root.info.hostname ? "Компьютер «" + (root.info.prettyHostname || root.info.hostname) + "»" : ""; tone: 3; size: "small" }
            }
            Btn { text: I18n.tr("Скопировать сведения"); icon: "copy"; enabled: root.loaded; onClicked: root.copy() }
        }
    }

    Card {
        title: I18n.tr("Компьютер")
        Rows {
            SettingRow {
                icon: "monitor"
                title: I18n.tr("Имя компьютера")
                subtitle: I18n.tr("Так компьютер называется в сети")
                RowLayout {
                    spacing: 8
                    Label { text: root.info.hostname || "—"; font.weight: Font.DemiBold }
                    Btn { text: I18n.tr("Переименовать"); onClicked: renameDlg.openDlg() }
                }
            }
            SettingRow { icon: "cpu"; title: I18n.tr("Процессор"); subtitle: root.info.threads ? root.plural(root.info.threads, "поток", "потока", "потоков") + " · " + (root.info.arch || "") : ""
                         Label { text: root.info.cpu || "—"; tone: 2; width: Math.min(implicitWidth, 400) } }
            Repeater {
                model: (root.info.gpus && root.info.gpus.length) ? root.info.gpus : ["—"]
                delegate: SettingRow {
                    id: gpu
                    required property string modelData
                    required property int index
                    icon: "gpu"
                    title: index === 0 ? "Видеокарта" : "Видеокарта " + (index + 1)
                    Label { text: gpu.modelData; tone: 2 }
                }
            }
            SettingRow { icon: "memory"; title: I18n.tr("Память"); subtitle: root.info.memFree ? "Свободно " + root.bytes(root.info.memFree) : ""
                         Label { text: root.bytes(root.info.mem); tone: 2 } }
            Repeater {
                model: root.screens
                delegate: SettingRow {
                    id: scr
                    required property var modelData
                    icon: "monitor"
                    title: I18n.tr("Экран ") + modelData.name
                    subtitle: modelData.model
                    Label { text: scr.modelData.text; tone: 2 }
                }
            }
        }
    }

    Card {
        title: I18n.tr("Система")
        SettingRow { icon: "settings"; title: I18n.tr("Ядро Linux"); Label { text: root.info.kernel || "—"; tone: 2 } }
        SettingRow { icon: "clock"; title: I18n.tr("Время работы"); Label { text: root.info.uptime !== undefined ? root.uptime(root.info.uptime) : "—"; tone: 2 } }
        SettingRow { icon: "palette"; title: I18n.tr("Окружение"); Label { text: "Delta " + (root.info.delta || "") + " · Hyprland · Quickshell"; tone: 2 } }
    }

    Card {
        title: I18n.tr("Диски")
        Rows {
            Repeater {
                model: root.info.disks || []
                delegate: SettingRow {
                    id: disk
                    required property var modelData
                    readonly property real used: modelData.size ? modelData.used / modelData.size : 0
                    icon: "disk"
                    title: modelData.target === "/" ? "Система (/)" : modelData.target
                    subtitle: (modelData.model ? modelData.model + " · " : "") + modelData.source
                    wide: true
                    RowLayout {
                        spacing: 12
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 8
                            radius: 4
                            color: Theme.soft2
                            Rectangle {
                                width: parent.width * disk.used
                                height: parent.height
                                radius: 4
                                color: disk.used > 0.9 ? "#E5484D" : Theme.accent
                            }
                        }
                        Label {
                            text: I18n.tr("свободно ") + root.bytes(disk.modelData.avail) + " из " + root.bytes(disk.modelData.size)
                            size: "small"; tone: 2
                        }
                    }
                }
            }
        }
    }

    Card {
        title: I18n.tr("Начать заново")
        Rows {
            SettingRow {
                icon: "rocket"
                title: I18n.tr("Начальная настройка")
                subtitle: I18n.tr("Язык, тема, обои и доки — как при первом включении")
                Btn { text: I18n.tr("Запустить"); onClicked: root.startSetup() }
            }
            SettingRow {
                icon: "restart"
                title: I18n.tr("Сбросить настройки")
                subtitle: I18n.tr("Оформление, доки, виджеты и обои вернутся к исходным. Файлы и программы останутся")
                Btn { text: I18n.tr("Сбросить"); kind: "danger"; onClicked: resetDlg.open() }
            }
        }
    }

    // первая настройка живёт в оболочке: просим её показаться и закрываемся
    function startSetup() {
        Quickshell.execDetached(["delta-shell", "ipc", "call", "oobe", "start"]);
        Nav.closeRequested();
    }

    Dialog {
        id: resetDlg
        title: I18n.tr("Сбросить все настройки?")
        subtitle: I18n.tr("Тема, обои, доки, виджеты, сочетания клавиш и экран блокировки станут как после установки. Мониторы, их масштаб и раскладка останутся как есть. Копия нынешних настроек сохранится рядом — settings.json.bak.")
        buttons: [
            Btn { text: I18n.tr("Отмена"); onClicked: resetDlg.close() },
            Btn { text: I18n.tr("Сбросить"); kind: "danger"; icon: "restart"; onClicked: root.resetAll() }
        ]
    }
    function resetAll() {
        Exec.run(["cp", "-f", Settings.path, Settings.path + ".bak"], {
            label: I18n.tr("копия настроек"), home: true, toast: false,
            done: () => {
                // пройденная настройка и помощник не должны встречать снова
                // мониторы не сбрасываем: масштаб «auto» на HiDPI или во вложенной
                // сессии раздувает всё вдвое, а раскладка экранов — свойство компьютера
                Settings.reset(["oobe.done", "welcome.done", "language.ui", "monitors", "display"]);
                Settings.flush();
                resetDlg.close();
                Nav.toast("Настройки сброшены");
            }
        });
    }

    function report() {
        const i = info;
        const lines = [
            (i.os || "Vanks OS") + " " + (i.version || ""),
            "Delta: " + (i.delta || ""),
            "Ядро: " + (i.kernel || "") + " (" + (i.arch || "") + ")",
            "Процессор: " + (i.cpu || "") + ", " + (i.threads || 0) + " потоков",
            "Видеокарта: " + (i.gpus || []).join("; "),
            "Память: " + bytes(i.mem),
            "Экраны: " + screens.map(s => s.name + " " + s.text).join("; "),
            "Диски: " + (i.disks || []).map(d => d.target + " " + bytes(d.size) + " (свободно " + bytes(d.avail) + ")").join("; "),
            "Имя компьютера: " + (i.hostname || ""),
            "Время работы: " + uptime(i.uptime || 0)
        ];
        return lines.join("\n");
    }
    function copy() {
        Quickshell.clipboardText = report();
        Nav.toast("Сведения скопированы");
    }

    Dialog {
        id: renameDlg
        title: I18n.tr("Имя компьютера")
        subtitle: I18n.tr("Латинские буквы, цифры и дефис. Понадобится пароль.")
        property string error: ""
        function openDlg() { error = ""; hostF.text = root.info.hostname || ""; open(); hostF.focusInput(); }
        readonly property bool valid: /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/.test(hostF.text)

        Field { id: hostF; Layout.fillWidth: true; icon: "monitor"; maxLength: 63; error: text.length > 0 && !renameDlg.valid; onAccepted: if (renameDlg.valid) root.rename(text) }
        Label { visible: renameDlg.error.length > 0; text: renameDlg.error; color: "#ff6b6b"; size: "small"; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        buttons: [
            Btn { text: I18n.tr("Отмена"); onClicked: renameDlg.close() },
            Btn { text: I18n.tr("Переименовать"); kind: "accent"; enabled: renameDlg.valid && hostF.text !== root.info.hostname && !renameDlg.busy; onClicked: root.rename(hostF.text) }
        ]
    }
    function rename(name) {
        renameDlg.busy = true;
        Exec.run(["hostnamectl", "set-hostname", name], {
            label: I18n.tr("имя компьютера: ") + name,
            done: (code, out, err) => {
                renameDlg.busy = false;
                if (code !== 0) { renameDlg.error = /not authorized|denied|dismissed/i.test(err) ? "Нет прав или пароль не введён" : "Не получилось: " + err.trim(); return; }
                renameDlg.close();
                if (!Exec.dryRun) refresh();
            }
        });
    }

    Connections {
        target: Nav
        function onAction(name, arg) {
            if (name === "about.rename") { renameDlg.openDlg(); if (arg) hostF.text = arg; }
            else if (name === "about.rename.apply") root.rename(hostF.text);
            else if (name === "about.copy") root.copy();
            else if (name === "about.reset") resetDlg.open();
            else if (name === "about.setup") root.startSetup();
        }
    }

    Confetti { id: boom; parent: root.Window.contentItem; anchors.fill: parent; z: 1000 }
}
