import QtQuick
import QtQuick.Shapes
import qs.common
import qs.common.ui

// Кольцо-показатель для нагрузки и температуры: значок сверху, число в
// центре, подпись снизу. Два вида: прямое кольцо и волнистое — по дуге
// бежит волна (как индикаторы Material 3). Остаток круга — тонкая дорожка.
//     Gauge { value: 62; wavy: true; icon: "memory"; text: "8,9 ГБ"; label: "ОЗУ" }
Item {
    id: root

    property real value: 0          // 0–100
    property bool wavy: true
    property string icon
    property string text
    property string label
    property color color: "#ffffff"
    property color track: Qt.rgba(1, 1, 1, 0.2)
    property color textColor: "#ffffff"
    property color labelColor: Qt.rgba(1, 1, 1, 0.78)
    // волна бежит, только пока виджет виден
    property bool animated: visible

    readonly property real d: Math.min(width, height)
    readonly property real stroke: Math.max(2.5, d * 0.05)
    readonly property real amp: wavy ? stroke * 0.6 : 0
    // радиус по середине линии; волне нужен запас по краю
    readonly property real r: d / 2 - stroke / 2 - amp
    readonly property real cx: width / 2
    readonly property real cy: height / 2
    // волн по кругу — длина волны около пяти толщин линии
    readonly property int waves: Math.max(8, Math.round(2 * Math.PI * r / (stroke * 5)))

    property real shown: Math.max(0, Math.min(100, value))
    Behavior on shown { NumberAnimation { duration: 800 * Theme.anim.k; easing.type: Easing.OutCubic } }

    property real phase: 0
    NumberAnimation on phase {
        running: root.wavy && root.animated
        from: 0; to: 2 * Math.PI
        duration: 2600
        loops: Animation.Infinite
    }

    // зазор между концом показателя и дорожкой (в градусах)
    readonly property real gapDeg: Math.min(14, (stroke * 2.2) / Math.max(1, r) * 180 / Math.PI)
    readonly property real sweep: 360 * shown / 100

    // точки волнистой дуги от верха по часовой стрелке
    readonly property var wavePoints: {
        if (!wavy || sweep < 0.5) return [];
        const pts = [];
        const steps = Math.max(12, Math.round(sweep * 1.4));
        const total = sweep * Math.PI / 180;
        const taper = Math.min(0.35, total / 2);
        for (let i = 0; i <= steps; i++) {
            const t = total * i / steps;
            // у концов волна сходит на нет — концы линии ровные
            const k = Math.min(1, t / taper, (total - t) / taper);
            const a = -Math.PI / 2 + t;
            const rr = r + amp * k * Math.sin(waves * t - phase);
            pts.push(Qt.point(cx + rr * Math.cos(a), cy + rr * Math.sin(a)));
        }
        return pts;
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        // дорожка — остаток круга
        ShapePath {
            strokeColor: root.sweep < 359 ? root.track : "transparent"
            strokeWidth: root.stroke * 0.55
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.cx; centerY: root.cy
                radiusX: root.r; radiusY: root.r
                startAngle: -90 + root.sweep + (root.sweep > 0.5 ? root.gapDeg : 0)
                sweepAngle: Math.max(0, 360 - root.sweep - (root.sweep > 0.5 ? 2 * root.gapDeg : 0))
            }
        }
        // показатель: прямой
        ShapePath {
            strokeColor: !root.wavy && root.sweep > 0.5 ? root.color : "transparent"
            strokeWidth: root.stroke
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.cx; centerY: root.cy
                radiusX: root.r; radiusY: root.r
                startAngle: -90
                sweepAngle: root.wavy ? 0 : root.sweep
            }
        }
        // показатель: волна
        ShapePath {
            strokeColor: root.wavy && root.wavePoints.length > 1 ? root.color : "transparent"
            strokeWidth: root.stroke
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.wavePoints }
        }
    }

    // значок · число · подпись
    Sym {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: num.top; bottomMargin: root.d * 0.02 }
        visible: root.icon.length > 0
        name: root.icon
        size: Math.round(root.d * 0.13)
        color: root.labelColor
    }
    WText {
        id: num
        anchors.centerIn: parent
        text: root.text
        px: root.d * (root.text.length > 4 ? 0.17 : 0.21)
        display: true
        color: root.textColor
        font.features: { "tnum": 1 }
    }
    WText {
        anchors { horizontalCenter: parent.horizontalCenter; top: num.bottom; topMargin: root.d * 0.01 }
        text: root.label
        px: root.d * 0.095
        color: root.labelColor
    }
}
