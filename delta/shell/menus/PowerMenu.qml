import QtQuick
import qs.common
import qs.lock

// Меню модуля «Питание и уведомления» верхнего дока (CONTRACTS.md §5).
// Фон и анимацию рисует док. В стиле Delta содержимое общее с окном
// Super+Escape (PowerPanel), в стиле «Акрил» — центр управления
// (ControlCenter: музыка, свет, звук, быстрые кнопки, VPN; блоки правятся).
Item {
    id: root
    implicitWidth: Theme.round ? 400 : 360
    implicitHeight: Theme.round ? cc.implicitHeight : panel.implicitHeight
    property var screen: null
    signal close()

    PowerPanel {
        id: panel
        visible: !Theme.round
        anchors { left: parent.left; right: parent.right; top: parent.top }
        onClose: root.close()
    }
    Loader {
        id: ccLoader
        active: Theme.round
        anchors { left: parent.left; right: parent.right; top: parent.top }
        sourceComponent: ControlCenter { screen: root.screen; onClose: root.close() }
    }
    readonly property Item cc: ccLoader.item ?? dummy
    Item { id: dummy; implicitWidth: 400; implicitHeight: 0 }
}
