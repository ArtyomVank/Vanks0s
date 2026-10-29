import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui

// Заголовок быстрого меню: название слева, элементы управления справа.
//     MenuTitle { text: "Wi‑Fi"; Toggle { … } }
RowLayout {
    id: root

    property string text
    default property alias extra: slot.data

    spacing: 8
    Layout.fillWidth: true
    implicitHeight: Math.max(30, slot.implicitHeight)

    Label { text: root.text; size: "title"; font.pixelSize: 15; font.weight: Font.Bold; Layout.fillWidth: true }
    Row { id: slot; spacing: 8; Layout.alignment: Qt.AlignVCenter }
}
