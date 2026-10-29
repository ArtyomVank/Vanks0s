import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.settings

// Модальный диалог поверх всего окна «Настроек». Объявляется прямо в разделе,
// а показывается в Nav.overlay — так его не обрезает прокрутка раздела.
//     Dialog { id: dlg; title: "Сменить пароль"; Field { … }
//              buttons: [Btn { text: "Отмена"; onClicked: dlg.close() }] }
Item {
    id: root

    property string title
    property string subtitle
    property int cardWidth: 440
    property bool shown: false
    // закрывается по клику мимо и Esc, если не идёт работа
    property bool busy: false
    default property alias content: body.data
    property alias buttons: btnRow.data
    signal closed()

    function open() { z = 100 + (++Nav.dialogSerial); shown = true; card.forceActiveFocus(); }
    function close() { if (shown) { shown = false; closed(); } }

    // перешли в другой раздел — диалог прошлого раздела закрываем
    Connections {
        target: Nav
        function onCurrentChanged() { if (!root.busy) root.close(); }
    }

    parent: Nav.overlay
    anchors.fill: parent
    z: 100
    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.anim.fast } }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, Theme.light ? 0.25 : 0.45)
        TapHandler { onTapped: if (!root.busy) root.close() }
    }

    Glass {
        id: card
        strong: true
        anchors.centerIn: parent
        width: root.cardWidth
        height: col.implicitHeight + 44
        radius: Theme.radius + 4
        color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.97)
        scale: root.shown ? 1 : 0.94
        Behavior on scale { NumberAnimation { duration: Theme.anim.normal; easing.type: Theme.anim.springCurve } }
        focus: root.shown
        Keys.onEscapePressed: if (!root.busy) root.close()
        // клик по карточке не закрывает диалог
        TapHandler {}

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 }
            spacing: 14

            ColumnLayout {
                spacing: 4
                Layout.fillWidth: true
                Label { text: root.title; size: "title"; Layout.fillWidth: true; visible: text.length > 0 }
                Label { text: root.subtitle; tone: 3; size: "small"; wrapMode: Text.WordWrap; Layout.fillWidth: true; visible: text.length > 0 }
            }
            ColumnLayout {
                id: body
                spacing: 10
                Layout.fillWidth: true
            }
            RowLayout {
                id: btnRow
                spacing: 8
                Layout.alignment: Qt.AlignRight
                visible: children.length > 0
            }
        }
    }
}
