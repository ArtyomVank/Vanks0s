pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.settings

// Левая колонка: логотип, поиск, разделы по группам. Поиск фильтрует список
// по названию, группе и словам раздела; Enter открывает первый найденный.
Rectangle {
    id: root

    property alias searchField: search
    readonly property var found: Registry.filtered(Nav.query)

    color: Theme.soft

    // граница с правой частью
    Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: Theme.line }

    ColumnLayout {
        anchors { fill: parent; topMargin: 18; bottomMargin: 12; leftMargin: 12; rightMargin: 13 }
        spacing: 12

        RowLayout {
            spacing: 10
            Layout.leftMargin: 8
            Rectangle {
                implicitWidth: 30
                implicitHeight: 30
                radius: 10
                color: Theme.accent
                Label { anchors.centerIn: parent; text: "V"; color: Theme.onAccent; font.weight: Font.Black; font.pixelSize: 15 }
            }
            Label { text: "Настройки"; font.pixelSize: 16; font.weight: Font.Bold }
        }

        Field {
            id: search
            Layout.fillWidth: true
            icon: "search"
            placeholder: "Поиск настроек"
            clearable: true
            onEdited: Nav.query = text
            onAccepted: if (root.found.length) Nav.open(root.found[0].id)
            Connections {
                target: Nav
                function onQueryChanged() { if (search.text !== Nav.query) search.text = Nav.query; }
            }
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: list
                width: flick.width
                spacing: 2

                Repeater {
                    model: Registry.groups
                    delegate: Column {
                        id: grp
                        required property string modelData
                        required property int index
                        readonly property var items: root.found.filter(s => s.group === modelData)
                        width: list.width
                        visible: items.length > 0
                        spacing: 2

                        Label {
                            text: grp.modelData
                            size: "caption"
                            tone: 3
                            font.weight: Font.DemiBold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 0.6
                            leftPadding: 12
                            topPadding: grp.index === 0 ? 2 : 12
                            bottomPadding: 4
                        }

                        Repeater {
                            model: grp.items
                            delegate: Rectangle {
                                id: item
                                required property var modelData
                                readonly property bool sel: Nav.current === modelData.id
                                width: list.width
                                height: 36
                                radius: 10
                                color: sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28)
                                     : hov.hovered ? Theme.soft2 : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.anim.fast } }

                                RowLayout {
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 10 }
                                    spacing: 10
                                    Sym { name: item.modelData.icon; size: 18; color: item.sel ? Theme.fg : Theme.fg2 }
                                    Label {
                                        text: item.modelData.title
                                        color: item.sel ? Theme.fg : Theme.fg2
                                        font.weight: item.sel ? Font.Medium : Font.Normal
                                        Layout.fillWidth: true
                                    }
                                }
                                HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: Nav.open(item.modelData.id) }
                            }
                        }
                    }
                }

                Label {
                    visible: root.found.length === 0
                    width: list.width
                    topPadding: 20
                    horizontalAlignment: Text.AlignHCenter
                    text: "Ничего не найдено"
                    tone: 3
                }
            }
        }
    }
}
