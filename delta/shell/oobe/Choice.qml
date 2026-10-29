import QtQuick
import qs.common
import qs.common.ui

// Плитка выбора первой настройки: пружинит под курсором, выбранная — с рамкой
// акцента и галочкой. Содержимое кладётся внутрь.
//     Choice { selected: …; onPicked: …; Label { … } }
Rectangle {
    id: root

    property bool selected: false
    signal picked()
    default property alias content: inner.data

    radius: 22
    color: selected ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : tap.containsMouse ? Theme.soft2 : Theme.soft
    border.width: selected ? 2 : 1
    border.color: selected ? Theme.accent : Theme.line
    Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
    Behavior on border.color { ColorAnimation { duration: Theme.anim.fast } }

    scale: tap.pressed ? 0.95 : tap.containsMouse ? 1.03 : 1
    Behavior on scale { NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }

    // выбор — короткий «вдох»
    onSelectedChanged: if (selected) pulse.restart()
    SequentialAnimation {
        id: pulse
        NumberAnimation { target: inner; property: "scale"; to: 1.06; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: inner; property: "scale"; to: 1; duration: 420; easing.type: Easing.OutElastic }
    }

    Item {
        id: inner
        anchors.fill: parent
    }

    Rectangle {
        anchors { top: parent.top; right: parent.right; margins: 10 }
        width: 24; height: 24; radius: 12
        color: Theme.accent
        scale: root.selected ? 1 : 0
        Behavior on scale { NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }
        Sym { anchors.centerIn: parent; name: "check"; size: 14; color: Theme.onAccent }
    }

    MouseArea {
        id: tap
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            Sounds.play("oobe-select", 60);
            root.picked();
        }
    }
}
