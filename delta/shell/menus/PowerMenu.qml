import QtQuick
import qs.lock

// Меню модуля «Питание и уведомления» верхнего дока (CONTRACTS.md §5).
// Фон и анимацию рисует док; содержимое общее с окном Super+Escape.
Item {
    id: root

    implicitWidth: 360
    implicitHeight: panel.implicitHeight
    signal close()

    PowerPanel {
        id: panel
        anchors { left: parent.left; right: parent.right; top: parent.top }
        onClose: root.close()
    }
}
