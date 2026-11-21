pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common
import qs.common.ui
import qs.settings
import qs.settings.parts

// Delta Link: компьютер и телефон с Vanks Launcher по домашней сети —
// уведомления и звонки, общий буфер обмена, файлы, заряд, «Найти телефон».
// Службу запускает оболочка (services/Link), пока link.enabled; отсюда
// говорим с ней через delta-link status/pair/send/… — «Настройки» отдельный
// процесс.
//   link.enabled        служба работает
//   link.notifications  уведомления телефона на компьютере
//   link.calls          звонки — островом в верхнем доке
//   link.clipboard      общий буфер обмена
ColumnLayout {
    id: root

    property string title: "Delta Link"
    property string icon: "phone"
    property string keywords: "телефон android смартфон vanks launcher уведомления звонки буфер обмена файлы отправить батарея найти привязать код"
    spacing: 18

    readonly property bool enabled: Settings.get("link.enabled", false) === true
    property var status: null            // { running, name, devices, pair }
    property real now: Date.now() / 1000
    readonly property var pair: status?.pair && status.pair.until > now ? status.pair : null
    property string busy: ""             // id телефона, которому сейчас шлём

    function refresh() {
        Exec.read(["delta-link", "status"], (code, out) => {
            let s = null;
            try { s = code === 0 ? JSON.parse(out) : null; } catch (e) {}
            root.status = s;
        });
    }
    function cmd(args, then) { Exec.read(["delta-link"].concat(args), () => { root.refresh(); if (then) then(); }); }
    function sendFiles(id) {
        Exec.read(["zenity", "--file-selection", "--multiple", "--separator=\n", "--title=" + I18n.tr("Файлы для телефона")], (code, out) => {
            const files = out.split("\n").filter(x => x);
            if (code !== 0 || !files.length) return;
            root.busy = id;
            root.cmd(["send", "--to", id].concat(files), () => {
                root.busy = "";
                Nav.toast(I18n.tr("Файлы отправлены — телефон скачает их в «Загрузки»"));
            });
        });
    }
    function batteryText(d) {
        if (d.battery < 0) return "";
        return d.battery + " %" + (d.charging ? " · " + I18n.tr("заряжается") : "");
    }

    Component.onCompleted: refresh()
    onEnabledChanged: refresh()
    Timer {
        interval: 2000; running: root.visible && root.enabled; repeat: true
        onTriggered: { root.now = Date.now() / 1000; root.refresh(); }
    }

    Card {
        title: "Delta Link"
        SettingRow {
            icon: "phone"
            title: I18n.tr("Связь с телефоном")
            subtitle: !root.enabled ? I18n.tr("Уведомления, звонки, буфер обмена и файлы с телефона на Vanks Launcher")
                : root.status?.running ? I18n.tr("Работает — телефон найдёт «%1» в домашней сети").arg(root.status.name)
                : I18n.tr("Запускается…")
            Toggle { checked: root.enabled; onToggled: v => Settings.set("link.enabled", v) }
        }
    }

    Card {
        visible: root.enabled
        title: I18n.tr("Телефоны")

        Repeater {
            model: root.status?.devices || []
            delegate: SettingRow {
                id: dev
                required property var modelData
                icon: "phone"
                title: modelData.name || I18n.tr("Телефон")
                subtitle: [modelData.online ? I18n.tr("в сети") : I18n.tr("не в сети"), root.batteryText(modelData)].filter(x => x).join(" · ")
                RowLayout {
                    spacing: 6
                    Btn {
                        enabled: dev.modelData.online
                        // звонит, даже если на телефоне выключен звук
                        text: I18n.tr("Найти"); icon: "bell"; kind: "ghost"
                        onClicked: root.cmd(["ring", dev.modelData.id], () => Nav.toast(I18n.tr("Телефон звонит")))
                    }
                    Btn {
                        enabled: dev.modelData.online
                        text: I18n.tr("Буфер"); icon: "copy"; kind: "ghost"
                        onClicked: root.cmd(["clip", dev.modelData.id], () => Nav.toast(I18n.tr("Буфер обмена на телефоне")))
                    }
                    Btn {
                        enabled: dev.modelData.online && root.busy === ""
                        text: I18n.tr("Файлы"); icon: "send"; kind: "soft"
                        onClicked: root.sendFiles(dev.modelData.id)
                    }
                    Btn {
                        // отвязать
                        icon: "trash"; kind: "ghost"
                        onClicked: root.cmd(["unpair", dev.modelData.id])
                    }
                }
            }
        }

        // привязка: шестизначный код на две минуты
        SettingRow {
            icon: "plus"
            title: I18n.tr("Привязать телефон")
            subtitle: root.pair
                ? I18n.tr("Введите код на телефоне: Vanks Launcher → Настройки → Delta Link. Ещё %1 с").arg(Math.max(0, Math.round(root.pair.until - root.now)))
                : I18n.tr("Телефон и компьютер — в одной сети Wi-Fi")
            RowLayout {
                spacing: 14
                Label {
                    visible: root.pair !== null
                    text: root.pair ? root.pair.code.slice(0, 3) + " " + root.pair.code.slice(3) : ""
                    size: "h1"
                    num: true
                    color: Theme.accent
                    font.letterSpacing: 3
                }
                Btn {
                    enabled: root.status?.running === true
                    text: root.pair ? I18n.tr("Новый код") : I18n.tr("Показать код")
                    kind: root.pair ? "ghost" : "accent"
                    onClicked: root.cmd(["pair"])
                }
            }
        }
    }

    Card {
        visible: root.enabled
        title: I18n.tr("Что передавать")
        SettingRow {
            icon: "bell"
            title: I18n.tr("Уведомления телефона")
            subtitle: I18n.tr("Сообщения и уведомления приложений приходят на компьютер")
            Toggle { checked: Settings.get("link.notifications", true) !== false; onToggled: v => Settings.set("link.notifications", v) }
        }
        SettingRow {
            icon: "phone-call"
            title: I18n.tr("Звонки")
            subtitle: I18n.tr("Кто звонит — островом в верхнем доке")
            Toggle { checked: Settings.get("link.calls", true) !== false; onToggled: v => Settings.set("link.calls", v) }
        }
        SettingRow {
            icon: "copy"
            title: I18n.tr("Общий буфер обмена")
            subtitle: I18n.tr("Скопировали на одном — вставляйте на другом. Пароли из менеджеров паролей не передаются")
            Toggle { checked: Settings.get("link.clipboard", true) !== false; onToggled: v => Settings.set("link.clipboard", v) }
        }
        SettingRow {
            icon: "download"
            title: I18n.tr("Файлы с телефона")
            subtitle: I18n.tr("«Поделиться → Delta Link» на телефоне — файл в «Загрузках» компьютера")
        }
        SettingRow {
            icon: "monitor"
            title: I18n.tr("Экран телефона")
            subtitle: I18n.tr("Показать и управлять телефоном в окне — по проводу, в «Телефоне»")
            Btn { text: I18n.tr("Открыть"); kind: "soft"; icon: "arrow-right"; onClicked: Quickshell.execDetached(["delta-phone"]) }
        }
    }
}
