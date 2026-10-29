pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.common
import qs.common.ui
import qs.lock
import qs.settings

// Питание: режим (power-profiles-daemon), гашение экрана и сон по простою,
// крышка ноутбука (logind, нужен root), батарея (UPower).
ColumnLayout {
    id: root

    property string title: "Питание"
    property string icon: "power"
    property string keywords: "батарея сон гибернация крышка энергия профиль экономия производительность экран гаснет"
    spacing: 18

    readonly property var bat: UPower.displayDevice
    readonly property bool hasBattery: bat && bat.ready && bat.isLaptopBattery && bat.isPresent
    // в Quickshell 0.3 процент 0…1; на всякий случай понимаем и 0…100
    readonly property int percent: !bat ? 0 : Math.round(bat.percentage > 1 ? bat.percentage : bat.percentage * 100)

    function duration(sec) {
        if (!sec || sec <= 0) return "";
        const h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60);
        return h > 0 ? h + " ч " + m + " мин" : m + " мин";
    }

    readonly property var timeChips: [{ value: 60, label: "1 мин" }, { value: 300, label: "5 мин" }, { value: 600, label: "10 мин" },
        { value: 900, label: "15 мин" }, { value: 1800, label: "30 мин" }, { value: 3600, label: "1 ч" }, { value: 0, label: "Никогда" }]

    Card {
        title: "Режим питания"
        SettingRow {
            icon: "cpu"; title: "Режим"; wide: true
            subtitle: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
                ? "Производительность снижена: " + PerformanceDegradationReason.toString(PowerProfiles.degradationReason)
                : "Режим выбирает служба power-profiles-daemon"
            Chips {
                current: PowerProfiles.profile
                model: [{ value: PowerProfile.PowerSaver, label: "Экономия" }, { value: PowerProfile.Balanced, label: "Баланс" }]
                    .concat(PowerProfiles.hasPerformanceProfile ? [{ value: PowerProfile.Performance, label: "Производительность" }] : [])
                onPicked: v => { if (Exec.dryRun) console.info("[delta-settings] пробный режим: профиль " + v); else PowerProfiles.profile = v; }
            }
        }
    }

    Card {
        title: "Экран и сон"
        SettingRow {
            icon: "monitor"; title: "Гасить экран через"; wide: true
            Chips {
                current: Settings.get("power.screenOffAfter", 600)
                model: root.timeChips
                onPicked: v => Settings.set("power.screenOffAfter", v)
            }
        }
        SettingRow {
            icon: "lock"; title: "На экране блокировки гасить через"; wide: true
            Chips {
                current: Settings.get("power.screenOffLockedAfter", 60)
                model: [{ value: 30, label: "30 с" }, { value: 60, label: "1 мин" }, { value: 120, label: "2 мин" },
                        { value: 300, label: "5 мин" }, { value: 0, label: "Как обычно" }]
                onPicked: v => Settings.set("power.screenOffLockedAfter", v)
            }
        }
        SettingRow {
            icon: "sleep"; title: "Засыпать через"; wide: true
            subtitle: "Видео и программы, которые просят не засыпать, откладывают сон"
            Chips {
                current: Settings.get("power.sleepAfter", 1800)
                model: root.timeChips
                onPicked: v => Settings.set("power.sleepAfter", v)
            }
        }
    }

    Card {
        title: "Крышка ноутбука"
        SettingRow {
            id: lid
            icon: "info"; title: "При закрытии крышки"; wide: true
            subtitle: "Это настройка systemd-logind: она пишется в /etc/systemd/logind.conf.d/ и требует пароля администратора"
            readonly property string value: Settings.get("power.lid", "suspend")
            Chips {
                current: lid.value
                model: [{ value: "suspend", label: "Сон" }]
                    .concat(PowerActions.canHibernate ? [{ value: "hibernate", label: "Гибернация" }] : [])
                    .concat([{ value: "lock", label: "Только блокировка" }, { value: "poweroff", label: "Выключение" }, { value: "ignore", label: "Ничего" }])
                onPicked: v => {
                    // значение из списка — подставлять в команду безопасно
                    if (["suspend", "hibernate", "lock", "poweroff", "ignore"].indexOf(v) === -1) return;
                    Settings.set("power.lid", v);
                    Exec.run(["pkexec", "sh", "-c",
                        "mkdir -p /etc/systemd/logind.conf.d && printf '[Login]\\nHandleLidSwitch=%s\\nHandleLidSwitchExternalPower=%s\\n' \"$1\" \"$1\" " +
                        "> /etc/systemd/logind.conf.d/10-delta-lid.conf && systemctl kill -s HUP systemd-logind", "sh", v],
                        { label: "Крышка: " + v });
                }
            }
        }
    }

    Card {
        title: "Батарея"
        SettingRow {
            visible: !root.hasBattery
            icon: "battery"; title: "Батареи нет"; subtitle: "Компьютер работает от сети"
        }
        SettingRow {
            visible: root.hasBattery
            icon: root.bat && root.bat.state === UPowerDeviceState.Charging ? "battery-charging" : "battery"
            title: "Заряд " + root.percent + " %"
            subtitle: {
                if (!root.bat) return "";
                const s = root.bat.state;
                if (s === UPowerDeviceState.Charging) return "Заряжается" + (root.bat.timeToFull > 0 ? ", до полного " + root.duration(root.bat.timeToFull) : "");
                if (s === UPowerDeviceState.FullyCharged) return "Заряжена полностью";
                if (s === UPowerDeviceState.Discharging) return "От батареи" + (root.bat.timeToEmpty > 0 ? ", осталось " + root.duration(root.bat.timeToEmpty) : "");
                return "Подключено к сети";
            }
            Label {
                readonly property real hp: root.bat && root.bat.healthSupported ? root.bat.healthPercentage : 0
                text: hp > 0 ? "износ " + Math.round(100 - (hp > 1 ? hp : hp * 100)) + " %" : ""
                tone: 3
            }
        }
    }
}
