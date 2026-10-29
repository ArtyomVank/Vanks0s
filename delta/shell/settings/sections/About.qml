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

    property string title: "О системе"
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
                implicitWidth: 76; implicitHeight: 76; radius: 22
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.2) }
                    GradientStop { position: 1; color: Qt.darker(Theme.accent, 1.3) }
                }
                Label { anchors.centerIn: parent; text: "V"; color: Theme.onAccent; font.pixelSize: 40; font.weight: Font.Black }
            }
            ColumnLayout {
                spacing: 4
                Layout.fillWidth: true
                Label { text: (root.info.os || "Vanks OS") + (root.info.version ? " " + root.info.version : ""); size: "h1"; Layout.fillWidth: true }
                Label { text: "Окружение Delta " + (root.info.delta || ""); tone: 2 }
                Label { text: root.info.hostname ? "Компьютер «" + (root.info.prettyHostname || root.info.hostname) + "»" : ""; tone: 3; size: "small" }
            }
            Btn { text: "Скопировать сведения"; icon: "copy"; enabled: root.loaded; onClicked: root.copy() }
        }
    }

    Card {
        title: "Компьютер"
        Rows {
            SettingRow {
                icon: "monitor"
                title: "Имя компьютера"
                subtitle: "Так компьютер виден в сети и в терминале"
                RowLayout {
                    spacing: 8
                    Label { text: root.info.hostname || "—"; font.weight: Font.DemiBold }
                    Btn { text: "Переименовать"; onClicked: renameDlg.openDlg() }
                }
            }
            SettingRow { icon: "cpu"; title: "Процессор"; subtitle: root.info.threads ? root.plural(root.info.threads, "поток", "потока", "потоков") + " · " + (root.info.arch || "") : ""
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
            SettingRow { icon: "memory"; title: "Память"; subtitle: root.info.memFree ? "Свободно " + root.bytes(root.info.memFree) : ""
                         Label { text: root.bytes(root.info.mem); tone: 2 } }
            Repeater {
                model: root.screens
                delegate: SettingRow {
                    id: scr
                    required property var modelData
                    icon: "monitor"
                    title: "Экран " + modelData.name
                    subtitle: modelData.model
                    Label { text: scr.modelData.text; tone: 2 }
                }
            }
        }
    }

    Card {
        title: "Система"
        SettingRow { icon: "settings"; title: "Ядро Linux"; Label { text: root.info.kernel || "—"; tone: 2 } }
        SettingRow { icon: "clock"; title: "Время работы"; Label { text: root.info.uptime !== undefined ? root.uptime(root.info.uptime) : "—"; tone: 2 } }
        SettingRow { icon: "palette"; title: "Окружение"; Label { text: "Delta " + (root.info.delta || "") + " · Hyprland · Quickshell"; tone: 2 } }
    }

    Card {
        title: "Диски"
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
                            text: "свободно " + root.bytes(disk.modelData.avail) + " из " + root.bytes(disk.modelData.size)
                            size: "small"; tone: 2
                        }
                    }
                }
            }
        }
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
        title: "Имя компьютера"
        subtitle: "Латиница, цифры и дефис, до 63 символов. Понадобится пароль администратора."
        property string error: ""
        function openDlg() { error = ""; hostF.text = root.info.hostname || ""; open(); hostF.focusInput(); }
        readonly property bool valid: /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/.test(hostF.text)

        Field { id: hostF; Layout.fillWidth: true; icon: "monitor"; maxLength: 63; error: text.length > 0 && !renameDlg.valid; onAccepted: if (renameDlg.valid) root.rename(text) }
        Label { visible: renameDlg.error.length > 0; text: renameDlg.error; color: "#ff6b6b"; size: "small"; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        buttons: [
            Btn { text: "Отмена"; onClicked: renameDlg.close() },
            Btn { text: "Переименовать"; kind: "accent"; enabled: renameDlg.valid && hostF.text !== root.info.hostname && !renameDlg.busy; onClicked: root.rename(hostF.text) }
        ]
    }
    function rename(name) {
        renameDlg.busy = true;
        Exec.run(["hostnamectl", "set-hostname", name], {
            label: "имя компьютера: " + name,
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
        }
    }
}
