pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import qs.common
import qs.common.ui

// Выпадающий список (в common/ui такого нет — кандидат на перенос).
//     Dropdown { model: [{ value: "1920x1080", label: "1920 × 1080", hint: "16:9" }]
//                current: "1920x1080"; onPicked: v => … }
Rectangle {
    id: root

    property var model: []
    property var current
    signal picked(var value)

    readonly property var sel: model.find(m => m.value === current) || null

    implicitWidth: Math.max(180, lbl.implicitWidth + 56)
    implicitHeight: 36
    radius: height / 2
    color: Theme.soft2
    border.width: popup.opened ? 1 : 0
    border.color: Theme.accent
    opacity: enabled ? 1 : 0.45

    Label {
        id: lbl
        anchors { left: parent.left; leftMargin: 16; right: chev.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
        text: root.sel ? root.sel.label : "—"
        font.weight: Font.Medium
    }
    Sym {
        id: chev
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        name: "chevron-down"
        size: 16
        color: Theme.fg2
        rotation: popup.opened ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: Theme.anim.fast } }
    }

    HoverHandler { cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler { enabled: root.enabled; onTapped: popup.opened ? popup.close() : popup.open() }

    function open() { popup.open(); }
    function close() { popup.close(); }

    QQC.Popup {
        id: popup
        x: root.width - width
        y: root.height + 6
        width: Math.max(root.width, 220)
        padding: 6
        closePolicy: QQC.Popup.CloseOnEscape | QQC.Popup.CloseOnPressOutside

        background: Glass { strong: true; radius: 14 }

        contentItem: ListView {
            id: list
            implicitHeight: Math.min(contentHeight, 300)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.model
            delegate: Rectangle {
                id: item
                required property var modelData
                readonly property bool cur: modelData.value === root.current
                width: list.width
                height: 34
                radius: 10
                color: cur ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22) : hov.hovered ? Theme.soft2 : "transparent"

                Label {
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    text: item.modelData.label
                    font.weight: item.cur ? Font.DemiBold : Font.Normal
                }
                Label {
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    text: item.modelData.hint || ""
                    size: "small"
                    tone: 3
                }
                HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        popup.close();
                        root.picked(item.modelData.value);
                    }
                }
            }
        }
    }
}
