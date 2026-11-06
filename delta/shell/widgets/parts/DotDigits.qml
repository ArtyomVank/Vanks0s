import QtQuick

// Точечные цифры, как часы в Nothing OS: каждая цифра — сетка 5×7 круглых
// точек. Рисуются сами, без шрифта: вид не зависит от установленных шрифтов.
//     DotDigits { text: "15:03"; digitHeight: 140; color: "white" }
// ghost — непогашенные точки сетки (0 — их не видно).
Canvas {
    id: root

    property string text: "00:00"
    property real digitHeight: 100
    property color color: "#ffffff"
    property real ghost: 0

    readonly property real pitch: digitHeight / 7
    // ширина строки в клетках: цифра — 5, двоеточие — 1, между знаками — 1
    readonly property int cells: {
        let n = 0;
        for (let i = 0; i < text.length; i++) n += (text[i] === ":" ? 1 : 5) + (i > 0 ? 1 : 0);
        return n;
    }
    implicitWidth: Math.ceil(cells * pitch)
    implicitHeight: Math.ceil(digitHeight)
    width: implicitWidth
    height: implicitHeight

    readonly property var glyphs: ({
        "0": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        ":": ["0", "0", "1", "0", "1", "0", "0"]
    })

    onTextChanged: requestPaint()
    onColorChanged: requestPaint()
    onGhostChanged: requestPaint()
    onDigitHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const p = pitch, r = p * 0.42;
        let x0 = 0;
        for (let i = 0; i < text.length; i++) {
            const g = glyphs[text[i]];
            if (!g) continue;
            for (let row = 0; row < 7; row++) {
                for (let col = 0; col < g[row].length; col++) {
                    const on = g[row][col] === "1";
                    if (!on && ghost <= 0) continue;
                    ctx.fillStyle = on ? color : Qt.rgba(color.r, color.g, color.b, color.a * ghost);
                    ctx.beginPath();
                    ctx.arc(x0 + (col + 0.5) * p, (row + 0.5) * p, r, 0, Math.PI * 2);
                    ctx.fill();
                }
            }
            x0 += (g[0].length + 1) * p;
        }
    }
}
