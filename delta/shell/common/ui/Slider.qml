import QtQuick
import QtQuick.Effects
import qs.common

// Ползунок. `moved` приходит при перетаскивании (живое значение),
// `released` — когда отпустили (для дорогих действий: запись, применение).
// В стиле «Акрил» (Theme.round) — толстая капсула: значок внутри, у края
// заливки — риска вместо ручки. У акрилового стекла заливка светится.
//     Slider { from: 0; to: 1; value: vol; icon: "volume"; onMoved: v => sink.volume = v }
Item {
    id: root

    property real from: 0
    property real to: 1
    property real value: 0
    property real step: 0
    property string icon
    property bool enabled: true
    signal moved(real value)
    signal released(real value)

    implicitWidth: 220
    readonly property bool capsule: Theme.round
    implicitHeight: capsule ? 34 : 30
    opacity: enabled ? 1 : 0.45

    readonly property real ratio: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0
    property real dragRatio: -1
    readonly property real shown: dragRatio >= 0 ? dragRatio : ratio

    function valueAt(x) {
        const r = Math.max(0, Math.min(1, (x - track.x) / track.width));
        let v = from + r * (to - from);
        if (step > 0) v = Math.round(v / step) * step;
        return Math.max(from, Math.min(to, v));
    }

    Sym {
        id: sym
        anchors.verticalCenter: parent.verticalCenter
        visible: root.icon.length > 0 && !root.capsule
        name: root.icon
        size: 18
        color: Theme.fg2
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        x: sym.visible ? sym.width + 10 : 0
        width: root.width - x
        // акриловое стекло: заливка светится и гаснет к началу
        height: root.capsule ? 30 : Theme.acrylic ? 12 : 8
        radius: height / 2
        color: Theme.soft2

        RectangularShadow {
            anchors.fill: fill
            visible: Theme.acrylic
            radius: fill.radius
            blur: 14
            spread: 1
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.light ? 0.30 : 0.50)
        }
        Rectangle {
            id: fill
            width: Math.max(root.capsule ? 44 : height, parent.width * root.shown)
            height: parent.height
            radius: parent.radius
            color: Theme.accent
            gradient: Theme.acrylic ? glowFill : null
            Gradient {
                id: glowFill
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) }
                GradientStop { position: 0.8; color: Theme.accent }
                GradientStop { position: 1; color: Qt.lighter(Theme.accent, 1.35) }
            }
        }
        // капсула: значок на заливке и риска у её края
        Sym {
            visible: root.capsule && root.icon.length > 0
            anchors.verticalCenter: parent.verticalCenter
            x: 11
            name: root.icon
            size: 16
            color: Theme.onAccent
        }
        Rectangle {
            visible: root.capsule
            anchors.verticalCenter: parent.verticalCenter
            x: fill.width - 10
            width: 3; height: 12; radius: 1.5
            color: Theme.onAccent
            opacity: 0.6
        }
        Rectangle {
            visible: !root.capsule
            width: 18
            height: 18
            radius: 9
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width * root.shown - width / 2
            color: Theme.accentLight ? Theme.onAccent : "#ffffff"
            scale: drag.pressed ? 1.15 : 1
            Behavior on scale { NumberAnimation { duration: Theme.anim.fast } }
        }
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        function update(mx) {
            const v = root.valueAt(mx);
            root.dragRatio = root.to > root.from ? (v - root.from) / (root.to - root.from) : 0;
            root.moved(v);
        }
        onPressed: m => update(m.x)
        onPositionChanged: m => { if (pressed) update(m.x); }
        onReleased: m => {
            const v = root.valueAt(m.x);
            root.dragRatio = -1;
            root.released(v);
        }
        onWheel: w => {
            const d = (root.step > 0 ? root.step : (root.to - root.from) / 20) * (w.angleDelta.y > 0 ? 1 : -1);
            const v = Math.max(root.from, Math.min(root.to, root.value + d));
            root.moved(v);
            root.released(v);
        }
    }
}
