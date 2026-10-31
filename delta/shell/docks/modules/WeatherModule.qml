import QtQuick
import Quickshell
import qs.common
import qs.common.ui
import qs.services
import qs.docks

// Погода: значок и температура из services/Weather (прогноз раз в 20 мин).
// Без города или без сети — только значок, подробности в WeatherMenu.
Item {
    id: root

    property bool vertical: false
    property bool full: true
    property ShellScreen screen
    property bool hidden: false

    WeatherUser { active: root.visible }

    readonly property var cur: Weather.hasData ? Weather.current : null

    implicitWidth: vertical ? 20 : row.implicitWidth
    implicitHeight: 20

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Sym {
            anchors.verticalCenter: parent.verticalCenter
            name: root.cur?.icon || "cloud-sun"
            size: 18
            color: Theme.fg2
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.vertical && root.cur !== null && DockService.opt("weatherTemp", true) !== false
            text: root.cur ? Weather.temp(root.cur.temp) : ""
            size: "small"
            color: Theme.fg
            font.weight: Font.Bold
        }
    }
}
