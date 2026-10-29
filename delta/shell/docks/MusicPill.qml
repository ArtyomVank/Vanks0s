import QtQuick
import qs.common
import qs.common.ui
import qs.docks.parts

// Верхний док в режиме музыки: обложка, «трек · исполнитель», эквалайзер.
Item {
    id: root

    property bool vertical: false

    width: vertical ? 44 : 340
    height: vertical ? 200 : 44

    Row {
        visible: !root.vertical
        anchors { left: parent.left; leftMargin: 7; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        spacing: 12

        Cover { anchors.verticalCenter: parent.verticalCenter; size: 30; source: DockService.art }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 30 - eq.width - 24
            elide: Text.ElideRight
            textFormat: Text.StyledText
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Bold
            color: Theme.fg
            text: root.esc(DockService.title || "Музыка")
                + (DockService.artist ? " <font color='" + Theme.fg3 + "'><span style='font-weight:500'>· " + root.esc(DockService.artist) + "</span></font>" : "")
        }
        Eq { id: eq; anchors.verticalCenter: parent.verticalCenter; playing: DockService.playing }
    }

    // сбоку экрана — столбик: обложка и эквалайзер
    Column {
        visible: root.vertical
        anchors.centerIn: parent
        spacing: 14
        Cover { anchors.horizontalCenter: parent.horizontalCenter; size: 30; source: DockService.art }
        Eq { anchors.horizontalCenter: parent.horizontalCenter; playing: DockService.playing }
    }

    function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
}
