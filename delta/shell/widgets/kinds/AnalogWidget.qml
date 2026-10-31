import QtQuick
import QtQuick.Shapes
import Quickshell
import qs.common
import qs.widgets.parts

// Часы со стрелками: циферблат из рисок, часовая и минутная стрелки и тонкая
// секундная акцентного цвета — она «перещёлкивает» с лёгкой отдачей.
// Режим «Число» добавляет снизу день недели и дату.
Base {
    id: root

    SystemClock { id: clock; precision: SystemClock.Seconds }
    readonly property date now: clock.date
    readonly property real sec: now.getSeconds()
    readonly property real min: now.getMinutes() + sec / 60
    readonly property real hour: now.getHours() % 12 + min / 60

    readonly property bool dated: root.mode === "date"
    readonly property real d: Math.min(width, height - (dated ? dateLine.height + 2 * ch : 0))

    Item {
        id: face
        width: root.d; height: width
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.dated ? 0 : (root.height - height) / 2
        readonly property real r: width / 2

        // ободок
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: Math.max(1, face.r * 0.025)
            border.color: root.pal.track
        }

        // риски: у часов — длиннее и толще
        Repeater {
            model: 60
            delegate: Rectangle {
                required property int index
                readonly property bool major: index % 5 === 0
                width: Math.max(1, face.r * (major ? 0.045 : 0.018))
                height: face.r * (major ? 0.13 : 0.06)
                radius: width / 2
                color: major ? root.pal.c1 : root.pal.c3
                opacity: major ? 0.95 : 0.55
                x: face.r - width / 2
                y: face.r * 0.07
                transform: Rotation { origin.x: width / 2; origin.y: face.r - face.r * 0.07; angle: index * 6 }
            }
        }

        // цифры 12, 3, 6, 9 — только на крупном циферблате
        Repeater {
            model: root.d > 150 ? [12, 3, 6, 9] : []
            delegate: WText {
                required property int modelData
                required property int index
                readonly property real a: index * Math.PI / 2
                text: modelData
                px: face.r * 0.17
                display: true
                color: root.pal.c1
                x: face.r + Math.sin(a) * face.r * 0.66 - width / 2
                y: face.r - Math.cos(a) * face.r * 0.66 - height / 2
            }
        }

        component Hand: Rectangle {
            id: hand
            property real angle: 0
            property real len: 0.5
            property real back: 0.12
            width: Math.max(2, face.r * 0.06)
            height: face.r * (len + back)
            radius: width / 2
            x: face.r - width / 2
            y: face.r - face.r * len
            antialiasing: true
            transform: Rotation { origin.x: hand.width / 2; origin.y: face.r * hand.len; angle: hand.angle }
        }

        Hand { angle: root.hour * 30; len: 0.5; width: Math.max(3, face.r * 0.075); color: root.pal.c1 }
        Hand { angle: root.min * 6; len: 0.74; width: Math.max(2, face.r * 0.05); color: root.pal.c1 }
        Hand {
            id: secHand
            len: 0.82; back: 0.18
            width: Math.max(1, face.r * 0.022)
            color: Theme.accent
            // секундная идёт рывком: перескок с отдачей, через 60 — без отката назад
            property real target: root.sec * 6
            onTargetChanged: {
                if (target < angle - 180) angle -= 360;
                anim.to = target;
                anim.restart();
            }
            Component.onCompleted: angle = target
            NumberAnimation on angle { id: anim; running: false; duration: 260 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
        }
        Rectangle {
            width: face.r * 0.11; height: width; radius: width / 2
            anchors.centerIn: parent
            color: Theme.accent
            border.width: Math.max(1, width * 0.25)
            border.color: root.pal.c1
        }
    }

    WText {
        id: dateLine
        visible: root.dated
        anchors { top: face.bottom; topMargin: 2 * root.ch; horizontalCenter: parent.horizontalCenter }
        text: Qt.locale(I18n.locale).toString(root.now, "ddd, d MMMM")
        px: Math.max(8, 9 * root.cm)
        font.weight: Font.DemiBold
        color: root.pal.c2
    }
}
