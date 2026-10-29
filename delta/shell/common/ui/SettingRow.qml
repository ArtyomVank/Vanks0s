import QtQuick
import QtQuick.Layouts
import qs.common

// Строка настроек: иконка, заголовок, пояснение слева — элемент управления справа.
//     SettingRow { icon: "bell-off"; title: "Не беспокоить"; subtitle: "Скрывать всплывающие уведомления"
//                  Toggle { … } }
// Если элемент широкий (ползунок, чипы), wide: true кладёт его под заголовок.
Item {
    id: root

    property string icon
    property string title
    property string subtitle
    property bool wide: false
    default property alias control: slot.data

    implicitHeight: Math.max(48, layout.implicitHeight + 18)
    Layout.fillWidth: true

    GridLayout {
        id: layout
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 14 }
        columns: root.wide ? 2 : 3
        columnSpacing: 12
        rowSpacing: 8

        Sym {
            visible: root.icon.length > 0
            name: root.icon
            size: 20
            color: Theme.fg2
            Layout.alignment: Qt.AlignVCenter
        }
        ColumnLayout {
            spacing: 2
            Layout.fillWidth: true
            Label { text: root.title; Layout.fillWidth: true }
            Label { visible: root.subtitle.length > 0; text: root.subtitle; size: "small"; tone: 3; wrapMode: Text.WordWrap; Layout.fillWidth: true }
        }
        Item {
            id: slot
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
            Layout.columnSpan: root.wide ? 2 : 1
            Layout.fillWidth: root.wide
            Layout.leftMargin: root.wide && root.icon.length > 0 ? 32 : 0
            Layout.alignment: Qt.AlignVCenter | (root.wide ? Qt.AlignLeft : Qt.AlignRight)
            // широкий элемент растягиваем на всю строку
            onWidthChanged: if (root.wide) for (let i = 0; i < children.length; i++) children[i].width = width
        }
    }
}
