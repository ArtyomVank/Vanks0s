pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.settings

// Левая колонка: логотип, поиск, «Все настройки» и папки с разделами
// (сворачиваются). Поиск фильтрует список
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
            Label { text: I18n.tr("Настройки"); font.pixelSize: 16; font.weight: Font.Bold }
        }

        Field {
            id: search
            Layout.fillWidth: true
            icon: "search"
            placeholder: I18n.tr("Поиск настроек")
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

                // главная: все папки карточками
                Row {
                    id: homeRow
                    readonly property bool sel: Nav.current === "home"
                    visible: Nav.query.length === 0
                    width: list.width
                    bottomPadding: 6
                    Rectangle {
                        width: list.width
                        height: 36
                        radius: 10
                        color: homeRow.sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28)
                             : homeHov.hovered ? Theme.soft2 : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
                        RowLayout {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 10 }
                            spacing: 10
                            Sym { name: "grid"; size: 18; color: homeRow.sel ? Theme.fg : Theme.fg2 }
                            Label { text: I18n.tr("Все настройки"); color: homeRow.sel ? Theme.fg : Theme.fg2; Layout.fillWidth: true }
                        }
                        HoverHandler { id: homeHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Nav.open("home") }
                    }
                }

                // папки: раскрыта та, где открытый раздел, и те, что раскрыли
                // вручную; при поиске раскрыты все с найденным
                Repeater {
                    model: Registry.folders
                    delegate: Column {
                        id: grp
                        required property var modelData
                        readonly property var items: root.found.filter(s => s.group === modelData.id)
                        readonly property bool hasCurrent: items.some(s => s.id === Nav.current)
                        readonly property bool open: Nav.query.length > 0 || Nav.openFolders[modelData.id] === true
                        width: list.width
                        visible: items.length > 0
                        spacing: 2

                        // папка открытого раздела раскрывается сама
                        onHasCurrentChanged: if (hasCurrent) Nav.setFolder(modelData.id, true)
                        Component.onCompleted: if (hasCurrent) Nav.setFolder(modelData.id, true)

                        Rectangle {
                            width: list.width
                            height: 34
                            radius: 10
                            color: headHov.hovered ? Theme.soft2 : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
                            RowLayout {
                                anchors { fill: parent; leftMargin: 12; rightMargin: 10 }
                                spacing: 10
                                Sym { name: grp.modelData.icon; size: 16; color: grp.hasCurrent ? Theme.accent : Theme.fg3 }
                                Label {
                                    text: grp.modelData.title
                                    size: "small"
                                    tone: grp.hasCurrent ? 1 : 3
                                    font.weight: Font.DemiBold
                                    Layout.fillWidth: true
                                }
                                Sym {
                                    name: "chevron-down"
                                    size: 14
                                    color: Theme.fg3
                                    rotation: grp.open ? 0 : -90
                                    Behavior on rotation { NumberAnimation { duration: Theme.anim.fast } }
                                }
                            }
                            HoverHandler { id: headHov; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: Nav.setFolder(grp.modelData.id, !grp.open) }
                        }

                        Item {
                            width: list.width
                            height: grp.open ? inner.implicitHeight : 0
                            clip: true
                            visible: height > 0
                            Behavior on height { NumberAnimation { duration: Theme.anim.normal; easing.type: Theme.anim.outCurve } }

                            Column {
                                id: inner
                                width: parent.width
                                spacing: 2
                                bottomPadding: 6

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
                                            anchors { fill: parent; leftMargin: 22; rightMargin: 10 }
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
                    }
                }

                Label {
                    visible: root.found.length === 0
                    width: list.width
                    topPadding: 20
                    horizontalAlignment: Text.AlignHCenter
                    text: I18n.tr("Ничего не найдено")
                    tone: 3
                }
            }
        }
    }
}
