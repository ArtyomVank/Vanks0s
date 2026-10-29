import QtQuick
import qs.common
import qs.launcher.parts

// Меню музыки (пилюля плеера в верхнем доке): только плеер, крупно.
Item {
    id: root

    implicitWidth: 460
    implicitHeight: player.implicitHeight
    signal close()

    // подставной уровень визуализатора для проверки (dev-launcher), -1 — настоящий
    property real vizDemo: -1

    Player {
        id: player
        width: parent.width
        wide: true
        vizDemo: root.vizDemo
    }
}
