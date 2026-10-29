import QtQuick
import QtQuick.Shapes

// Цифры «Длинных» часов, как на экране блокировки iOS 26: тонкие высокие
// цифры из прямых и полукругов со скруглёнными концами. Рисуются линиями,
// а не шрифтом — вид не зависит от установленных шрифтов, и высоту можно
// тянуть как угодно, толщина линии при этом не меняется.
//     TallDigits { text: "15:03"; digitHeight: 160; color: "white" }
Item {
    id: root

    property string text: "00:00"
    property real digitHeight: 100
    property color color: "#ffffff"
    // ширина цифры — доля высоты (ползунок «ширина цифр»)
    property real widthRatio: 0.62
    // толщина линии — доля высоты цифры
    property real weight: 0.055

    readonly property real h: digitHeight
    readonly property real w: h * widthRatio
    readonly property real s: Math.max(1.5, h * weight)
    readonly property real gap: h * 0.14

    // ширина строки t при высоте цифр 1 — чтобы вписать часы в место
    function ratioFor(t) {
        let x = 0;
        for (let i = 0; i < t.length; i++) x += (i > 0 ? 0.14 : 0) + (t[i] === ":" ? 0.2 : t[i] === "1" ? widthRatio * 0.6 : widthRatio);
        return Math.max(0.1, x);
    }
    function glyphW(c) { return c === ":" ? h * 0.2 : c === "1" ? w * 0.6 : w; }
    readonly property var layout: {
        const out = [];
        let x = 0;
        for (let i = 0; i < text.length; i++) {
            if (i > 0) x += gap;
            out.push({ c: text[i], x: x });
            x += glyphW(text[i]);
        }
        return { items: out, width: x };
    }

    implicitWidth: layout.width + s
    implicitHeight: h + s

    // Дуги — полуэллипсы: по ширине во всю цифру, по высоте не больше
    // четверти цифры, поэтому широкие цифры остаются высокими и прямыми.
    readonly property real rx: w / 2
    readonly property real ry: Math.min(rx, h * 0.24)
    function arc(rx, ry, x, y, sweep) { return " A " + rx + " " + ry + " 0 0 " + sweep + " " + x + " " + y; }
    function stadium(x0, y0, x1, y1) {
        const a = (x1 - x0) / 2, b = Math.min(a, (y1 - y0) / 2, h * 0.24);
        return "M " + x0 + " " + (y0 + b) + arc(a, b, x1, y0 + b, 1)
             + " L " + x1 + " " + (y1 - b) + arc(a, b, x0, y1 - b, 1) + " Z";
    }
    // контур цифры c в рамке w×h
    function glyph(c) {
        const a = rx, b = ry, q = Math.min(ry, h * 0.17);
        const A = (x, y, sweep) => arc(a, b, x, y, sweep);
        const L = (x, y) => " L " + x + " " + y;
        const M = (x, y) => "M " + x + " " + y;
        switch (c) {
        case "0": return stadium(0, 0, w, h);
        case "1": return M(0, h * 0.17) + L(w * 0.6, 0) + L(w * 0.6, h);
        case "2": return M(0, b) + A(w, b, 1) + " C " + w + " " + (b + (h - b) * 0.3) + " 0 " + (h * 0.64) + " 0 " + h + L(w, h);
        case "3": {
            const m = h / 2;
            return M(0, b) + A(w, b, 1) + L(w, m - q) + arc(a, q, a, m, 1) + L(w * 0.28, m)
                 + " " + M(a, m) + arc(a, q, w, m + q, 1) + L(w, h - b) + A(0, h - b, 1);
        }
        case "4": return M(w * 0.78, h) + L(w * 0.78, 0) + L(0, h * 0.68) + L(w, h * 0.68);
        case "5": {
            const y = h * 0.42;
            return M(w, 0) + L(0, 0) + L(0, y) + L(a, y) + arc(a, q, w, y + q, 1) + L(w, h - b) + A(0, h - b, 1);
        }
        case "6": {
            const y = h * 0.42;
            return M(w, b) + A(0, b, 0) + L(0, h - b) + A(w, h - b, 0) + L(w, y + q) + arc(a, q, 0, y + q, 0);
        }
        case "7": return M(0, 0) + L(w, 0) + L(w * 0.28, h);
        case "8": {
            const m = h * 0.47;
            return stadium(w * 0.06, 0, w * 0.94, m) + " " + stadium(0, m, w, h);
        }
        case "9": {
            const y = h * 0.58;
            return M(0, h - b) + A(w, h - b, 0) + L(w, b) + A(0, b, 0) + L(0, y - q) + arc(a, q, w, y - q, 0);
        }
        }
        return "";
    }

    Repeater {
        model: root.layout.items
        delegate: Item {
            id: g
            required property var modelData
            x: modelData.x + root.s / 2
            y: root.s / 2
            width: root.glyphW(modelData.c)
            height: root.h

            Shape {
                anchors.fill: parent
                visible: g.modelData.c !== ":"
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: root.color
                    strokeWidth: root.s
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: root.glyph(g.modelData.c) }
                }
            }

            // двоеточие — две точки
            Repeater {
                model: g.modelData.c === ":" ? [0.36, 0.64] : []
                delegate: Rectangle {
                    required property real modelData
                    width: root.s * 1.9
                    height: width
                    radius: width / 2
                    color: root.color
                    x: (g.width - width) / 2
                    y: root.h * modelData - height / 2
                }
            }
        }
    }
}
