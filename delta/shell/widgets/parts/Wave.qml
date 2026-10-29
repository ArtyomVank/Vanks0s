import QtQuick
import qs.common

// График «волна»: сглаженная линия по истории (0–100) и заливка под ней.
// Число точек зависит от ширины, чтобы на маленьком виджете волна не рябила.
//     Wave { values: SystemStats.cpuHist }
Canvas {
    id: root

    property var values: []
    property color color: Theme.accent
    // сколько пикселей на точку
    property real step: 14
    property real lineWidth: Math.max(1.5, height * 0.03)

    readonly property var shown: {
        const n = Math.max(8, Math.min(values.length, Math.round(width / step)));
        return values.slice(-n);
    }

    onShownChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onColorChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const v = shown, n = v.length;
        if (n < 2) return;
        const W = width, H = height, pad = lineWidth;
        const pt = i => [i * W / (n - 1), H - pad - (Math.max(0, Math.min(100, v[i])) / 100) * (H - pad * 2)];
        const path = () => {
            let p = pt(0);
            ctx.moveTo(p[0], p[1]);
            for (let i = 1; i < n; i++) {
                const a = pt(i - 1), b = pt(i), mx = (a[0] + b[0]) / 2;
                ctx.bezierCurveTo(mx, a[1], mx, b[1], b[0], b[1]);
            }
        };
        const g = ctx.createLinearGradient(0, 0, 0, H);
        g.addColorStop(0, Qt.rgba(root.color.r, root.color.g, root.color.b, 0.6));
        g.addColorStop(1, Qt.rgba(root.color.r, root.color.g, root.color.b, 0));
        ctx.beginPath();
        path();
        ctx.lineTo(W, H);
        ctx.lineTo(0, H);
        ctx.closePath();
        ctx.fillStyle = g;
        ctx.fill();
        ctx.beginPath();
        path();
        ctx.lineWidth = lineWidth;
        ctx.lineCap = "round";
        ctx.strokeStyle = root.color;
        ctx.stroke();
    }
}
