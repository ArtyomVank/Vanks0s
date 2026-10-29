import QtQuick
import QtQuick.Shapes
import qs.common

// Кольцо-индикатор (0–100). Толщина — доля диаметра, поэтому кольцо
// масштабируется вместе с виджетом.
//     Ring { width: 80; height: 80; value: 42 }
Item {
    id: root

    property real value: 0
    property color color: Theme.accent
    property color track: Theme.soft2
    // толщина относительно диаметра (концепт: 9 из 84)
    property real thickness: 0.107
    // дуга вместо полного круга: 360 — кольцо, 180 — шкала-полукруг
    property real span: 360

    readonly property bool half: span < 360
    readonly property real d: half ? Math.min(width, 2 * height) : Math.min(width, height)
    readonly property real stroke: Math.max(2, d * thickness)
    // у полукруга концы с круглыми колпачками должны влезть снизу
    readonly property real r: half ? Math.min(width / 2, height - stroke / 2) - stroke / 2 : (d - stroke) / 2
    property real shown: Math.max(0, Math.min(100, value))
    Behavior on shown { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.track
            strokeWidth: root.stroke
            fillColor: "transparent"
            capStyle: root.span < 360 ? ShapePath.RoundCap : ShapePath.FlatCap
            PathAngleArc {
                centerX: root.width / 2; centerY: root.span < 360 ? root.height - root.stroke / 2 : root.height / 2
                radiusX: root.r; radiusY: root.r
                startAngle: root.span < 360 ? 180 : -90
                sweepAngle: root.span
            }
        }
        ShapePath {
            strokeColor: root.shown > 0.5 ? root.color : "transparent"
            strokeWidth: root.stroke
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2; centerY: root.span < 360 ? root.height - root.stroke / 2 : root.height / 2
                radiusX: root.r; radiusY: root.r
                startAngle: root.span < 360 ? 180 : -90
                sweepAngle: root.span * root.shown / 100
            }
        }
    }
}
