import QtQuick
import QtQuick.Layouts

// Строка Card, которая может прятаться. Card рисует разделители по всем детям,
// а у невидимого элемента ColumnLayout не обновляет y — линия остаётся висеть
// посреди соседней строки. Обёртка всегда видима, но схлопывается в 0 по высоте.
//     Maybe { show: hdrSupported; SettingRow { … } }
Item {
    id: root

    property bool show: true
    default property alias content: holder.data

    Layout.fillWidth: true
    implicitHeight: show ? holder.implicitHeight : 0

    ColumnLayout {
        id: holder
        width: root.width
        spacing: 0
        visible: root.show
    }
}
