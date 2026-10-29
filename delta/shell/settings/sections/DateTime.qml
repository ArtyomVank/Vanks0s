pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.settings
import qs.settings.parts

// Дата и время: часовой пояс и NTP — через timedatectl (timedated спросит
// пароль через polkit; в проверках — только журнал), формат часов — clock.hours24.
ColumnLayout {
    id: root

    property string title: I18n.tr("Дата и время")
    property string icon: "clock"
    property string keywords: "часовой пояс время дата ntp синхронизация 24 часа формат"
    spacing: 18

    property var td: ({})
    property var zones: []
    property date now: new Date()
    readonly property bool h24: Settings.get("clock.hours24", true)

    // города, которые чаще ищут по-русски
    readonly property var ruCities: ({
        "Europe/Moscow": "Москва", "Europe/Kaliningrad": "Калининград", "Europe/Samara": "Самара", "Europe/Volgograd": "Волгоград",
        "Asia/Yekaterinburg": "Екатеринбург", "Asia/Omsk": "Омск", "Asia/Novosibirsk": "Новосибирск", "Asia/Krasnoyarsk": "Красноярск",
        "Asia/Irkutsk": "Иркутск", "Asia/Yakutsk": "Якутск", "Asia/Vladivostok": "Владивосток", "Asia/Magadan": "Магадан",
        "Asia/Kamchatka": "Камчатка", "Asia/Sakhalin": "Сахалин", "Europe/Kiev": "Киев", "Europe/Kyiv": "Киев", "Europe/Minsk": "Минск",
        "Asia/Almaty": "Алматы", "Asia/Tashkent": "Ташкент", "Asia/Tbilisi": "Тбилиси", "Asia/Yerevan": "Ереван", "Asia/Baku": "Баку",
        "Europe/London": "Лондон", "Europe/Berlin": "Берлин", "Europe/Paris": "Париж", "America/New_York": "Нью-Йорк",
        "Asia/Tokyo": "Токио", "Asia/Shanghai": "Шанхай", "Europe/Istanbul": "Стамбул", "Asia/Dubai": "Дубай", "UTC": "UTC"
    })
    function zoneLabel(z) {
        if (ruCities[z]) return ruCities[z];
        return String(z).split("/").pop().replace(/_/g, " ");
    }

    function refresh() {
        Exec.read(["timedatectl", "show"], (code, out) => {
            const o = {};
            for (const l of out.split("\n")) { const i = l.indexOf("="); if (i > 0) o[l.slice(0, i)] = l.slice(i + 1); }
            root.td = o;
        });
    }
    Component.onCompleted: {
        refresh();
        Exec.read(["timedatectl", "list-timezones"], (code, out) => {
            root.zones = out.split("\n").filter(z => z.length).map(z => ({ value: z, label: root.zoneLabel(z), sub: z, keywords: root.ruCities[z] || "" }));
        });
    }
    Timer { interval: 1000; repeat: true; running: Nav.current === "datetime"; onTriggered: root.now = new Date() }

    // --- крупные часы ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 120
        radius: Theme.radius - 2
        color: Theme.soft
        border.color: Theme.line
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 2
            Label {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatTime(root.now, root.h24 ? "HH:mm:ss" : "h:mm:ss AP")
                font.family: Theme.fontDisplay
                font.pixelSize: 44
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
            Label {
                Layout.alignment: Qt.AlignHCenter
                text: root.now.toLocaleDateString(Qt.locale("ru_RU"), "dddd, d MMMM yyyy") + (root.td.Timezone ? " · " + root.zoneLabel(root.td.Timezone) : "")
                tone: 2
            }
        }
    }

    Card {
        title: I18n.tr("Время")
        SettingRow {
            icon: "refresh"
            title: I18n.tr("Устанавливать время автоматически")
            subtitle: root.td.CanNTP === "no" ? "Служба синхронизации времени не установлена"
                    : root.td.NTPSynchronized === "yes" ? "Синхронизировано по сети (NTP)" : "Синхронизация по сети (NTP)"
            Toggle {
                checked: root.td.NTP === "yes"
                enabled: root.td.CanNTP !== "no"
                onToggled: v => Exec.run(["timedatectl", "set-ntp", v ? "true" : "false"], {
                    label: I18n.tr("синхронизация времени: ") + (v ? "вкл" : "выкл"),
                    done: code => { if (code === 0 && !Exec.dryRun) root.refresh(); }
                })
            }
        }
        SettingRow {
            icon: "globe"
            title: I18n.tr("Часовой пояс")
            subtitle: root.td.Timezone || ""
            Select { text: root.td.Timezone ? root.zoneLabel(root.td.Timezone) : "…"; onClicked: tzPicker.openWith() }
        }
    }

    Card {
        title: I18n.tr("Формат")
        SettingRow {
            icon: "clock"
            title: I18n.tr("24-часовой формат")
            subtitle: root.h24 ? "Сейчас " + Qt.formatTime(root.now, "HH:mm") : "Сейчас " + Qt.formatTime(root.now, "h:mm AP")
            Toggle { checked: root.h24; onToggled: v => Settings.set("clock.hours24", v) }
        }
    }

    Picker {
        id: tzPicker
        title: I18n.tr("Часовой пояс")
        searchHint: "Город или регион: Москва, Europe/Berlin"
        model: root.zones
        current: root.td.Timezone
        onPicked: v => Exec.run(["timedatectl", "set-timezone", v], {
            label: I18n.tr("часовой пояс ") + v,
            done: code => { if (code === 0 && !Exec.dryRun) root.refresh(); }
        })
    }

    Connections {
        target: Nav
        function onAction(name, arg) {
            if (name === "datetime.zone") tzPicker.openWith(arg);
        }
    }
}
