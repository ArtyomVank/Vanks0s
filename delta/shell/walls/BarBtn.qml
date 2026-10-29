import QtQuick
import qs.common
import qs.common.ui

// Круглая кнопка панели выбора обоев с подсказкой под ней.
//     BarBtn { icon: "clock"; hint: "Сначала новые"; on: true; onClicked: … }
Rectangle {
    id: b

    property string icon
    property string hint
    property bool on: false
    signal clicked()

    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    width: 34; height: 34; radius: 17
    color: on ? Theme.accent : hover.hovered ? Theme.soft2 : Theme.soft
    Behavior on color { ColorAnimation { duration: Theme.anim.fast } }

    Sym { anchors.centerIn: parent; name: b.icon; size: 16; color: b.on ? Theme.onAccent : Theme.fg }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: b.clicked() }

    // подсказка
    Rectangle {
        visible: opacity > 0
        opacity: hover.hovered && b.hint.length ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.anim.fast } }
        y: b.height + 8
        x: (b.width - width) / 2
        width: tip.implicitWidth + 16
        height: 24
        radius: 8
        color: Theme.glass2
        border.width: 1
        border.color: Theme.line
        Label { id: tip; anchors.centerIn: parent; text: b.hint; size: "caption" }
    }
}
