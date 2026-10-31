import QtQuick
import Quickshell
import qs.common
import qs.common.ui
import qs.display
import qs.widgets.parts

// Солнце: дуга от восхода до заката, солнце ползёт по ней, по краям — время
// восхода и заката, снизу — сколько осталось. Ночью дуга гаснет, а солнце
// уступает место луне. Место — то же, что у ночного света (по часовому поясу
// или из настроек).
Base {
    id: root

    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property var sun: NightLight.sunToday
    readonly property int nowMin: clock.date.getHours() * 60 + clock.date.getMinutes()
    readonly property bool day: sun !== null && nowMin >= sun.sunrise && nowMin < sun.sunset
    readonly property real progress: !sun ? 0 : day ? (nowMin - sun.sunrise) / Math.max(1, sun.sunset - sun.sunrise) : nowMin < sun.sunrise ? 0 : 1

    function span(min) {
        const h = Math.floor(min / 60), m = min % 60;
        const ch = I18n.tr("ч"), mn = I18n.tr("мин");
        return h > 0 ? h + " " + ch + (m > 0 ? " " + m + " " + mn : "") : m + " " + mn;
    }
    readonly property string note: !sun ? I18n.tr("Место не известно")
        : day ? I18n.tr("До заката") + " " + span(sun.sunset - nowMin)
        : I18n.tr("До восхода") + " " + span((sun.sunrise - nowMin + 1440) % 1440)

    WCaption { id: cap; cm: root.cm; text: I18n.tr("Солнце"); color: root.pal.c2; width: parent.width }

    Item {
        id: arcBox
        anchors { left: parent.left; right: parent.right; top: cap.bottom; topMargin: 4 * root.ch; bottom: ends.top; bottomMargin: 1 * root.ch }

        Ring {
            id: arc
            width: Math.min(parent.width, 2 * parent.height)
            height: width / 2
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            span: 180
            thickness: 0.035
            value: root.progress * 100
            color: root.day ? Theme.accents[4] : root.pal.c3
            track: root.pal.track
        }
        // горизонт
        Rectangle {
            anchors { left: arc.left; right: arc.right; bottom: parent.bottom }
            anchors.leftMargin: -2 * root.cw; anchors.rightMargin: -2 * root.cw
            height: Math.max(1, root.cm * 0.4)
            color: root.pal.c3
            opacity: 0.5
        }

        // солнце (или луна) на дуге
        Item {
            id: body
            readonly property real r: (arc.width - arc.stroke) / 2
            readonly property real a: Math.PI * (1 - (root.day ? root.progress : 0.5))
            readonly property real cx: arc.x + arc.width / 2 + Math.cos(a) * r
            readonly property real cy: arc.y + arc.height - arc.stroke / 2 - Math.sin(a) * r * (root.day ? 1 : 0.55)
            width: Math.max(14, arc.width * 0.14); height: width
            x: cx - width / 2; y: cy - height / 2
            Behavior on x { NumberAnimation { duration: 900 * Theme.anim.k; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 900 * Theme.anim.k; easing.type: Easing.OutCubic } }

            // мягкое свечение, дышит
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 1.9; height: width
                radius: width / 2
                color: root.day ? Theme.accents[4] : root.pal.c2
                opacity: 0.18
                SequentialAnimation on scale {
                    loops: Animation.Infinite
                    running: root.visible
                    NumberAnimation { from: 0.85; to: 1.1; duration: 1800 * Theme.anim.k; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1.1; to: 0.85; duration: 1800 * Theme.anim.k; easing.type: Easing.InOutSine }
                }
            }
            Sym {
                anchors.centerIn: parent
                name: root.day ? "sun" : "moon"
                size: Math.round(parent.width)
                color: root.day ? Theme.accents[4] : root.pal.c1
            }
        }
    }

    Item {
        id: ends
        anchors { left: parent.left; right: parent.right; bottom: noteLine.top; bottomMargin: 1 * root.ch }
        height: rise.height
        WText { id: rise; x: arc.x; text: root.sun ? NightLight.fmt(root.sun.sunrise) : "—"; px: 8 * root.cm; display: true; color: root.pal.c1 }
        WText { anchors.right: parent.right; anchors.rightMargin: parent.width - arc.x - arc.width; text: root.sun ? NightLight.fmt(root.sun.sunset) : "—"; px: 8 * root.cm; display: true; color: root.pal.c1 }
    }
    WText {
        id: noteLine
        anchors.bottom: parent.bottom
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.note
        px: 7 * root.cm
        color: root.pal.c3
        elide: Text.ElideRight
    }
}
