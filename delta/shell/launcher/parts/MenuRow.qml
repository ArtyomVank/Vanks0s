import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui

// Строка быстрого меню (.mrow в концепте): иконка, текст, справа — что угодно.
//     MenuRow { icon: "wifi"; title: "Дом"; subtitle: "Подключено"; onClicked: … ; Sym { name: "check" } }
Rectangle {
    id: root

    property string icon
    property color iconColor: Theme.fg2
    property string title
    property string subtitle
    property bool active: false
    property bool clickable: true
    default property alias extra: slot.data
    signal clicked()

    Layout.fillWidth: true
    implicitWidth: 300
    implicitHeight: Math.max(42, row.implicitHeight + 18)
    radius: 12
    color: active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2)
         : hover.hovered && clickable ? Theme.soft2 : Theme.soft
    border.width: active ? 1.5 : 0
    border.color: Theme.accent
    Behavior on color { ColorAnimation { duration: Theme.anim.fast } }

    RowLayout {
        id: row
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
        spacing: 10

        Sym { visible: root.icon.length > 0; name: root.icon; size: 18; color: root.iconColor }
        ColumnLayout {
            spacing: 1
            Layout.fillWidth: true
            Label { text: root.title; size: "small"; font.weight: Font.DemiBold; Layout.fillWidth: true }
            Label { visible: root.subtitle.length > 0; text: root.subtitle; size: "caption"; tone: 3; Layout.fillWidth: true }
        }
        Row { id: slot; spacing: 8; Layout.alignment: Qt.AlignVCenter }
    }

    HoverHandler { id: hover; cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler { enabled: root.clickable; onTapped: root.clicked() }
}
