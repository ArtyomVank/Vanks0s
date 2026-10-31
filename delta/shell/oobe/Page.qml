import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui

// Шаг первой настройки: значок, заголовок, пояснение и содержимое. Когда шаг
// становится текущим, всё въезжает по очереди (shown → appear): значок
// выпрыгивает с искрами, заголовок печатается по буквам со щелчками.
Item {
    id: root

    property string icon
    property string title
    property string subtitle
    property bool shown: false
    default property alias content: body.data

    onShownChanged: if (shown) {
        head.y = 26; head.opacity = 0; body.opacity = 0; bodyShift.y = 34; badge.scale = 0.5;
        typer.play(260);
        appear.restart();
    }

    Typewriter { id: typer; full: root.title }

    ColumnLayout {
        anchors { fill: parent; leftMargin: 48; rightMargin: 48; topMargin: 40; bottomMargin: 12 }
        spacing: 22

        Item {
            Layout.fillWidth: true
            implicitHeight: headCol.implicitHeight
            ColumnLayout {
                id: headCol
                width: parent.width
                spacing: 8
                Rectangle {
                    id: badge
                    implicitWidth: 52; implicitHeight: 52; radius: 17
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2)
                    Sym { anchors.centerIn: parent; name: root.icon; size: 26; color: Theme.accent }
                    Sparkles { id: spark; anchors.centerIn: parent; width: 150; height: 150 }
                }
                Label { text: typer.text; size: "h1"; font.pixelSize: 30; Layout.fillWidth: true; Layout.topMargin: 6 }
                Label { text: root.subtitle; tone: 2; wrapMode: Text.WordWrap; Layout.fillWidth: true; visible: text.length > 0 }
            }
            QtObject { id: head; property real y: 0; property real opacity: 1 }
            transform: Translate { y: head.y }
            opacity: head.opacity
        }

        Item {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
            opacity: 1
            transform: Translate { id: bodyShift; y: 0 }
        }
    }

    SequentialAnimation {
        id: appear
        PauseAnimation { duration: 90 * Theme.anim.k }
        ParallelAnimation {
            SequentialAnimation {
                PauseAnimation { duration: 120 * Theme.anim.k }
                ScriptAction { script: { spark.burst(); Sounds.play("sparkle", 0); } }
                NumberAnimation { target: badge; property: "scale"; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
            }
            NumberAnimation { target: head; property: "y"; to: 0; duration: 620; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
            NumberAnimation { target: head; property: "opacity"; to: 1; duration: 380; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: 110 * Theme.anim.k }
                ParallelAnimation {
                    NumberAnimation { target: bodyShift; property: "y"; to: 0; duration: 680; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                    NumberAnimation { target: body; property: "opacity"; to: 1; duration: 420; easing.type: Easing.OutCubic }
                }
            }
        }
    }
}
