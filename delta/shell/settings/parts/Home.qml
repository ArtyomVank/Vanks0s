pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.settings

// Главная «Настроек»: папки (Registry.folders) карточками — значок, название
// и разделы внутри; нажатие на раздел открывает его, на шапку карточки —
// первый раздел папки.
GridLayout {
    id: root

    columns: width > 620 ? 2 : 1
    columnSpacing: 14
    rowSpacing: 14

    Repeater {
        model: Registry.folders
        delegate: Rectangle {
            id: card
            required property var modelData
            readonly property var items: Registry.sections.filter(s => s.group === modelData.id)

            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            implicitHeight: col.implicitHeight + 28
            radius: 18
            color: Theme.soft
            border.width: 1
            border.color: Theme.line

            ColumnLayout {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 6

                RowLayout {
                    spacing: 12
                    Layout.bottomMargin: 4
                    Rectangle {
                        implicitWidth: 40
                        implicitHeight: 40
                        radius: 13
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                        Sym { anchors.centerIn: parent; name: card.modelData.icon; size: 20; color: Theme.accent }
                    }
                    Label { text: card.modelData.title; font.pixelSize: 16; font.weight: Font.Bold; Layout.fillWidth: true }
                }

                Repeater {
                    model: card.items
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: 11
                        color: hov.hovered ? Theme.soft2 : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
                        RowLayout {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
                            spacing: 10
                            Sym { name: row.modelData.icon; size: 18; color: Theme.fg2 }
                            Label { text: row.modelData.title; Layout.fillWidth: true }
                            Sym { name: "chevron-right"; size: 14; color: Theme.fg3 }
                        }
                        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Nav.open(row.modelData.id) }
                    }
                }
            }
        }
    }
}
