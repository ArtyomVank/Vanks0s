import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.welcome

// Пункт помощника: значок, название, зачем это нужно — справа переключатель
// или отметка «Установлено». Нажатие по всей строке включает и выключает.
Rectangle {
    id: root

    required property var item
    property int index: 0
    property bool busy: false

    readonly property bool done: Catalog.isInstalled(item)
    readonly property bool on: { void Catalog.picked; void Catalog.installed; return Catalog.isOn(item); }

    implicitHeight: Math.max(72, col.implicitHeight + 28)
    radius: 18
    color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, tap.containsMouse ? 0.16 : 0.11)
         : tap.containsMouse && !done ? Theme.soft2 : Theme.soft
    border.width: 1
    border.color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : Theme.line
    Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
    Behavior on border.color { ColorAnimation { duration: Theme.anim.fast } }

    // строки въезжают по очереди при открытии раздела
    opacity: 0
    transform: Translate { id: shift; y: 14 }
    Component.onCompleted: appear.start()
    SequentialAnimation {
        id: appear
        PauseAnimation { duration: 30 * root.index }
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 1; duration: Theme.anim.normal; easing.type: Easing.OutCubic }
            NumberAnimation { target: shift; property: "y"; to: 0; duration: Theme.anim.slow; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
        }
    }

    scale: tap.pressed && !done ? 0.985 : 1
    Behavior on scale { NumberAnimation { duration: Theme.anim.fast; easing.type: Easing.OutCubic } }

    RowLayout {
        anchors { fill: parent; leftMargin: 16; rightMargin: 18 }
        spacing: 14

        Rectangle {
            implicitWidth: 44; implicitHeight: 44; radius: 14
            color: root.on || root.done ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22) : Theme.soft2
            Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
            Sym { anchors.centerIn: parent; name: root.item.icon; size: 22; color: root.on || root.done ? Theme.accent : Theme.fg2 }
        }

        ColumnLayout {
            id: col
            Layout.fillWidth: true
            spacing: 3
            Label { text: root.item.title; font.weight: Font.DemiBold; Layout.fillWidth: true }
            Label { text: root.item.text; tone: 2; size: "small"; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            Label {
                text: (root.item.pkgs || []).concat(root.item.aur ? root.item.aur.map(a => a + " (AUR)") : []).join(" · ")
                tone: 3; size: "caption"; font.family: Theme.fontMono
                Layout.fillWidth: true
                visible: text.length > 0
            }
        }

        // уже стоит
        Rectangle {
            visible: root.done
            implicitWidth: doneRow.implicitWidth + 20
            implicitHeight: 28
            radius: 14
            color: Qt.rgba(0.25, 0.7, 0.48, 0.16)
            Row {
                id: doneRow
                anchors.centerIn: parent
                spacing: 6
                Sym { name: "check"; size: 14; color: "#3FB37A"; anchors.verticalCenter: parent.verticalCenter }
                Label { text: "Установлено"; size: "small"; color: "#3FB37A"; anchors.verticalCenter: parent.verticalCenter }
            }
        }
        Toggle {
            visible: !root.done
            checked: root.on
            enabled: !root.busy
            onToggled: Catalog.toggle(root.item)
        }
    }

    MouseArea {
        id: tap
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        enabled: !root.done && !root.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: Catalog.toggle(root.item)
    }
}
