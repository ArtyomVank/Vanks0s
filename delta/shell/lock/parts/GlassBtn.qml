import QtQuick
import qs.common
import qs.common.ui

// Круглая кнопка поверх обоев (экран блокировки и входа): светлое стекло,
// белая иконка, подпись при наведении. Цвета не из темы намеренно — фон тут
// всегда тёмные размытые обои, а не стекло темы.
//     GlassBtn { icon: "power"; label: "Выключение"; onClicked: … }
Item {
    id: root

    property string icon
    property string label
    property string text           // если задан — кнопка-«пилюля» с текстом
    property bool active: false
    property int size: 44
    signal clicked()

    implicitWidth: text.length ? row.implicitWidth + 28 : size
    implicitHeight: text.length ? 34 : size

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: height / 2
        color: root.active ? Theme.accent : Qt.rgba(1, 1, 1, hover.hovered ? 0.24 : 0.14)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)
        scale: tap.pressed ? 0.92 : 1
        Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
        Behavior on scale { NumberAnimation { duration: Theme.anim.fast; easing.type: Theme.anim.outCurve } }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 6
            Sym {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.icon.length > 0
                name: root.icon
                size: root.text.length ? 16 : Math.round(root.size * 0.45)
                color: "#ffffff"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.text.length > 0
                text: root.text
                color: "#ffffff"
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
        }
    }

    // подпись снизу, как подсказка
    Text {
        anchors { top: bg.bottom; topMargin: 6; horizontalCenter: bg.horizontalCenter }
        visible: root.label.length > 0
        opacity: hover.hovered ? 0.9 : 0
        text: root.label
        color: "#ffffff"
        font.family: Theme.font
        font.pixelSize: 12
        Behavior on opacity { NumberAnimation { duration: Theme.anim.fast } }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; onTapped: root.clicked() }
}
