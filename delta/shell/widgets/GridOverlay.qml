import QtQuick

// Сетка редактора: точки в углах клеток и пунктирная рамка (.grid-ov в концепте).
// Рисуется один раз на размер, а не каждый кадр.
Canvas {
    id: root

    property real cell: 80
    property real unit: 1
    property bool shown: false

    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 300 } }

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onCellChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const r = 18 * unit, lw = 1.5;
        // пунктирная рамка со скруглением
        ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.25);
        ctx.lineWidth = lw;
        ctx.setLineDash([4, 4]);
        ctx.beginPath();
        ctx.roundedRect(lw / 2, lw / 2, width - lw, height - lw, r, r);
        ctx.stroke();
        // точки во внутренних углах клеток
        ctx.fillStyle = Qt.rgba(1, 1, 1, 0.4);
        const dot = Math.max(1.2, 1.5 * unit);
        for (let y = cell; y < height - 1; y += cell)
            for (let x = cell; x < width - 1; x += cell) {
                ctx.beginPath();
                ctx.arc(x, y, dot, 0, Math.PI * 2);
                ctx.fill();
            }
    }
}
