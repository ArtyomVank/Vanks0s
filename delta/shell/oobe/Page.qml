import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui

// Шаг первой настройки: значок, заголовок, пояснение и содержимое — всё по
// центру, без плашек. Когда шаг становится текущим, всё въезжает по очереди
// (shown → appear): значок выпрыгивает с искрами, заголовок печатается по
// буквам со щелчками. Содержимое не шире 820 px — на широком экране оно не
// расползается по краям.
Item {
    id: root

    property string icon
    property string title
    property string subtitle
    property bool shown: false
    default property alias content: body.data

    onShownChanged: if (shown) {
        head.y = 22; head.opacity = 0; body.opacity = 0; bodyShift.y = 30; glyph.scale = 0.4;
        typer.play(240);
        appear.restart();
    }

    Typewriter { id: typer; full: root.title }

    ColumnLayout {
        anchors { fill: parent; leftMargin: 40; rightMargin: 40; topMargin: 44; bottomMargin: 8 }
        spacing: 28

        Item {
            Layout.fillWidth: true
            implicitHeight: headCol.implicitHeight
            Column {
                id: headCol
                width: parent.width
                spacing: 10
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 40; height: 40
                    Sym { id: glyph; anchors.centerIn: parent; name: root.icon; size: 32; color: Theme.accent }
                    Sparkles { id: spark; anchors.centerIn: parent; width: 150; height: 150 }
                }
                Label {
                    width: parent.width
                    // место под весь заголовок сразу: строки ниже не прыгают, пока он печатается
                    height: Math.max(implicitHeight, 44)
                    text: typer.text
                    size: "h1"
                    font.pixelSize: 34
                    horizontalAlignment: Text.AlignHCenter
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, 600)
                    text: root.subtitle
                    tone: 3
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    visible: text.length > 0
                }
            }
            QtObject { id: head; property real y: 0; property real opacity: 1 }
            transform: Translate { y: head.y }
            opacity: head.opacity
        }

        Item {
            id: body
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(parent.width, 820)
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
                NumberAnimation { target: glyph; property: "scale"; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
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
