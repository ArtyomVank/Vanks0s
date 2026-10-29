import QtQuick
import Quickshell.Services.UPower
import qs.common
import qs.common.ui
import qs.widgets.parts

// Батарея (UPower). Без батареи виджет не предлагается и не показывается.
Base {
    id: root

    readonly property var dev: UPower.displayDevice
    readonly property bool ok: dev !== null && dev.isLaptopBattery && dev.isPresent
    // в разных версиях UPower процент приходит как 0–1 или 0–100
    readonly property real value: ok ? (dev.percentage > 1 ? dev.percentage : dev.percentage * 100) : -1
    readonly property bool charging: ok && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.PendingCharge)
    readonly property bool full: ok && dev.state === UPowerDeviceState.FullyCharged

    function hours(sec) {
        if (!(sec > 0)) return "";
        const h = Math.floor(sec / 3600), m = Math.round(sec % 3600 / 60);
        return h > 0 ? h + " ч" + (m > 0 && h < 10 ? " " + m + " мин" : "") : m + " мин";
    }
    readonly property string note: !ok ? "нет данных"
        : full ? "Заряжена"
        : charging ? (hours(dev.timeToFull) ? "до полной " + hours(dev.timeToFull) : "Заряжается")
        : hours(dev.timeToEmpty) ? "до " + hours(dev.timeToEmpty) : "От батареи"
    readonly property string valueText: ok ? Math.round(value) + "%" : "—"
    readonly property color tone: ok && value <= 15 && !charging ? Theme.accents[5] : Theme.accent

    // ---- рабочий стол ----
    Item {
        anchors.fill: parent
        visible: !root.lock
        WCaption { id: cap; cm: root.cm; text: "Батарея"; color: root.pal.c2; width: parent.width }
        Ring {
            id: ring
            anchors { horizontalCenter: parent.horizontalCenter; top: cap.bottom; topMargin: 2 * root.cm; bottom: note.top; bottomMargin: 2 * root.cm }
            width: height
            value: Math.max(0, root.value)
            color: root.tone
            track: root.pal.track
            Sym {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -parent.height * 0.12
                visible: root.charging
                name: "battery-charging"
                size: Math.round(parent.height * 0.22)
                color: root.pal.c1
            }
            WText {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: root.charging ? parent.height * 0.12 : 0
                text: root.valueText
                px: 13 * root.cm
                display: true
                color: root.pal.c1
            }
        }
        WText { id: note; anchors.bottom: parent.bottom; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.note; px: 7.5 * root.cm; color: root.pal.c3 }
    }

    // ---- экран блокировки ----
    Item {
        anchors.fill: parent
        visible: root.lock

        // «Число»: процент и состояние
        Row {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.mode !== "ring"
            spacing: 6 * root.cm
            WText { anchors.verticalCenter: parent.verticalCenter; text: root.valueText; px: Math.min(34 * root.ch, 15 * root.cw); font.weight: Font.ExtraBold; color: root.pal.c1 }
            WText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Батарея\n" + root.note
                maximumLineCount: 2
                lineHeight: 1.1
                px: Math.min(15 * root.ch, 6.5 * root.cw)
                color: root.pal.c1
                opacity: 0.85
            }
        }

        // «Кольцо»: заряд по кругу и подпись снизу
        Item {
            anchors.fill: parent
            visible: root.mode === "ring"

            WText {
                id: lockRingCap
                width: parent.width
                text: "Батарея"
                px: Math.min(10 * root.ch, 4 * root.cw)
                font.weight: Font.ExtraBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.6
                color: root.pal.c1
                opacity: 0.8
            }
            Ring {
                anchors { horizontalCenter: parent.horizontalCenter; top: lockRingCap.bottom; bottom: lockRingNote.top; bottomMargin: 2 * root.ch }
                width: Math.min(height, parent.width)
                value: Math.max(0, root.value)
                color: root.pal.c1
                track: root.pal.track
                WText { anchors.centerIn: parent; text: root.valueText; px: Math.min(17 * root.ch, 6.5 * root.cw); display: true; color: root.pal.c1 }
            }
            WText {
                id: lockRingNote
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                horizontalAlignment: Text.AlignHCenter
                text: root.note
                px: Math.min(11 * root.ch, 4.4 * root.cw)
                color: root.pal.c1
                opacity: 0.8
            }
        }
    }
}
