pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.common
import qs.common.ui
import qs.launcher.parts

// Меню батареи: заряд, сколько осталось, режим питания. Без батареи
// (настольный ПК) остаётся только режим питания; без power-profiles-daemon —
// только заряд.
Item {
    id: root

    implicitWidth: 320
    implicitHeight: col.implicitHeight
    signal close()

    readonly property UPowerDevice dev: UPower.displayDevice
    readonly property bool hasBattery: dev !== null && dev.ready && dev.isLaptopBattery && dev.isPresent
    readonly property real percent: !dev ? 0 : dev.percentage > 1 ? dev.percentage : dev.percentage * 100
    readonly property bool charging: dev?.state === UPowerDeviceState.Charging || dev?.state === UPowerDeviceState.PendingCharge
    readonly property bool full: dev?.state === UPowerDeviceState.FullyCharged

    function duration(sec) {
        if (!(sec > 0)) return "";
        const m = Math.round(sec / 60);
        const h = Math.floor(m / 60);
        return h > 0 ? h + " ч " + (m % 60) + " мин" : m + " мин";
    }
    readonly property string stateText: {
        if (full) return "Заряжена";
        if (charging) {
            const t = duration(dev.timeToFull);
            return t ? "Заряжается · до полной " + t : "Заряжается";
        }
        if (UPower.onBattery) {
            const t = duration(dev.timeToEmpty);
            return t ? "От батареи · осталось " + t : "От батареи";
        }
        return "Подключено к сети";
    }

    // power-profiles-daemon может отсутствовать — тогда выбор режима не показываем
    property bool profilesAvailable: false
    Process {
        running: true
        command: ["sh", "-c", "busctl --system --no-pager status net.hadess.PowerProfiles >/dev/null 2>&1 || busctl --system --no-pager status org.freedesktop.UPower.PowerProfiles >/dev/null 2>&1"]
        onExited: code => root.profilesAvailable = code === 0
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 10

        MenuTitle { text: root.hasBattery ? "Батарея" : "Питание" }

        // заряд
        Rectangle {
            visible: root.hasBattery
            Layout.fillWidth: true
            implicitHeight: bat.implicitHeight + 24
            radius: 12
            color: Theme.soft

            ColumnLayout {
                id: bat
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                spacing: 8
                RowLayout {
                    spacing: 10
                    Sym { name: root.charging ? "battery-charging" : "battery"; size: 22; color: root.percent < 15 && !root.charging ? "#ff6b6b" : Theme.fg2 }
                    ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true
                        Label { text: I18n.tr("Заряд"); size: "small"; font.weight: Font.DemiBold }
                        Label { text: root.stateText; size: "caption"; tone: 3; Layout.fillWidth: true }
                    }
                    Label { text: Math.round(root.percent) + "%"; size: "title"; font.weight: Font.Bold }
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 8
                    radius: 4
                    color: Theme.soft2
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, root.percent / 100))
                        height: parent.height
                        radius: parent.radius
                        color: root.percent < 15 && !root.charging ? "#E5484D" : Theme.accent
                        Behavior on width { NumberAnimation { duration: Theme.anim.slow } }
                    }
                }
                Label {
                    visible: root.dev?.healthSupported ?? false
                    text: I18n.tr("Износ: состояние ") + Math.round(root.dev?.healthPercentage ?? 0) + "%"
                    size: "caption"; tone: 3
                }
            }
        }

        MenuRow {
            visible: !root.hasBattery
            clickable: false
            icon: "power"
            title: I18n.tr("Питание от сети")
            subtitle: I18n.tr("Батарея не найдена")
        }

        // режим питания
        Label {
            visible: root.profilesAvailable
            text: I18n.tr("Режим питания"); size: "small"; tone: 3
            Layout.topMargin: 2
        }
        Chips {
            visible: root.profilesAvailable
            Layout.fillWidth: true
            current: PowerProfiles.profile
            model: [{ value: PowerProfile.PowerSaver, label: I18n.tr("Экономия") }, { value: PowerProfile.Balanced, label: I18n.tr("Баланс") }]
                .concat(PowerProfiles.hasPerformanceProfile ? [{ value: PowerProfile.Performance, label: I18n.tr("Производительность") }] : [])
            onPicked: v => PowerProfiles.profile = v
        }
        Label {
            visible: root.profilesAvailable && PowerProfiles.degradationReason !== PerformanceDegradationReason.None
            text: PowerProfiles.degradationReason === PerformanceDegradationReason.HighTemperature
                ? "Производительность снижена: перегрев" : "Производительность снижена: ноутбук на коленях"
            size: "caption"; tone: 3
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Btn {
            Layout.alignment: Qt.AlignLeft
            kind: "ghost"
            icon: "settings"
            text: I18n.tr("Настройки питания…")
            implicitHeight: 32
            onClicked: { ShellState.openSettings("power", null); root.close(); }
        }
    }
}
