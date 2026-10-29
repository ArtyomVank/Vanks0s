pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.services
import qs.widgets.parts

// Меню «ПК» верхнего дока: все показатели и маленькие графики.
// Пока меню открыто, SystemStats опрашивает датчики (включая видеокарту и диск).
Item {
    id: root

    implicitWidth: 360
    implicitHeight: column.implicitHeight
    signal close()

    StatsUser { active: root.visible; gpu: true; disk: true }

    function pct(v) { return v >= 0 ? Math.round(v) + "%" : "—"; }
    function deg(v) { return v >= 0 ? Math.round(v) + "°" : ""; }

    // одна строка: иконка, название, значение, подробности, график или полоса
    component Stat: ColumnLayout {
        id: st
        property string icon
        property string title
        property string value
        property string details
        property string extra
        property var hist: null
        property real level: -1
        Layout.fillWidth: true
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Rectangle {
                implicitWidth: 32; implicitHeight: 32; radius: 10
                color: Theme.soft2
                Sym { anchors.centerIn: parent; name: st.icon; size: 18; color: Theme.fg2 }
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                Label { text: st.title; font.weight: Font.DemiBold; Layout.fillWidth: true }
                Label { visible: st.details.length > 0; text: st.details; size: "caption"; tone: 3; Layout.fillWidth: true }
            }
            Label { visible: st.extra.length > 0; text: st.extra; size: "small"; tone: 2; color: Theme.accents[4] }
            Label { text: st.value; size: "title"; font.family: Theme.fontDisplay }
        }
        Wave {
            visible: st.hist !== null
            Layout.fillWidth: true
            implicitHeight: 34
            values: st.hist || []
            step: 8
            lineWidth: 1.8
        }
        Meter {
            visible: st.hist === null
            Layout.fillWidth: true
            implicitHeight: 6
            value: Math.max(0, st.level)
        }
    }

    ColumnLayout {
        id: column
        anchors { left: parent.left; right: parent.right }
        spacing: 14

        Label { text: I18n.tr("Показатели ПК"); size: "title" }

        Stat {
            icon: "cpu"
            title: I18n.tr("Процессор")
            details: SystemStats.cpuName
            value: root.pct(SystemStats.cpu)
            extra: root.deg(SystemStats.cpuTemp)
            hist: SystemStats.cpuHist
        }
        Stat {
            visible: SystemStats.gpuVendor.length > 0
            icon: "gpu"
            title: I18n.tr("Видеокарта")
            details: SystemStats.gpuName + (SystemStats.vramTotal > 0 ? (SystemStats.gpuName ? " · " : "") + "память " + SystemStats.pair(SystemStats.vramUsed, SystemStats.vramTotal) : "")
            value: SystemStats.hasGpuLoad ? root.pct(SystemStats.gpu) : SystemStats.hasGpuTemp ? "" : "нет данных"
            extra: root.deg(SystemStats.gpuTemp)
            hist: SystemStats.hasGpuLoad ? SystemStats.gpuHist : null
            level: -1
        }
        Stat {
            icon: "memory"
            title: I18n.tr("Оперативная память")
            details: SystemStats.ramTotal > 0
                ? SystemStats.pair(SystemStats.ramUsed, SystemStats.ramTotal)
                  + (SystemStats.swapTotal > 0 ? " · подкачка " + SystemStats.bytes(SystemStats.swapUsed) : "")
                : "нет данных"
            value: root.pct(SystemStats.ram)
            hist: SystemStats.ramHist
        }
        Stat {
            icon: "disk"
            title: I18n.tr("Диск /")
            details: SystemStats.diskTotal > 0
                ? SystemStats.pair(SystemStats.diskUsed, SystemStats.diskTotal)
                  + " · свободно " + SystemStats.bytes(SystemStats.diskTotal - SystemStats.diskUsed)
                : "нет данных"
            value: root.pct(SystemStats.disk)
            level: SystemStats.disk
        }
    }
}
