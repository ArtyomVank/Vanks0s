import QtQuick
import QtQuick.Effects
import qs.common

// «Капля из дока → карточка» (меню модулей, меню значка, уведомления, OSD,
// окно приложений, призрак «Настроек»).
//
// Владелец задаёт итоговый прямоугольник карточки (x, y, width, height) и
// откуда течёт капля: точку источника srcX/srcY в координатах карточки (обычно
// за её краем — у дока). Если точка не задана, она берётся из направления
// dirX/dirY (единичный вектор от карточки к доку) и расстояния fly.
//
// Ход анимации — одно число t от 0 до 1: край источника вздувается, капля
// отрывается с «шейкой», стекает к карточке и растекается в неё с пружиной.
// Закрытие — тот же путь обратно, прерывание в любой момент плавное.
Item {
    id: root

    property bool open: false
    property real dirX: 0
    property real dirY: -1
    property real radiusOpen: 24
    property color ballColor: Theme.accent
    property bool strong: true
    // насколько далеко от карточки источник, если srcX/srcY не заданы
    property real fly: 44
    property real srcX: NaN
    property real srcY: NaN
    // плитка дока, из которой течёт капля (ShellState.pullKey): она
    // вытягивается вслед за каплей и пружинит, когда та отрывается
    property string pullKey: ""
    // где окно Blob на экране, если оно не на весь экран (уведомления, OSD):
    // точку источника для острова дока нужно отдать в координатах экрана
    property point screenOffset: Qt.point(0, 0)

    default property alias content: inner.data
    readonly property alias body: body
    // 0 спрятан, 1 капля у источника, 2 летит / растекается, 3 карточка
    readonly property int stage: t <= 0 ? 0 : t < p1End ? 1 : t < 1 ? 2 : 3
    readonly property bool settled: t >= 1 && open && !anim.running
    // Где карточка принимает ввод — в координатах родителя (для mask окна).
    // Пока капля у дока (вытекает или стекает обратно), ввода нет: слой карточки
    // выше дока, и прозрачная капля глотала бы нажатия по самому доку. Числа,
    // а не Region { item: body }: такой регион не замечает, что карточка переехала.
    readonly property rect inputRect: open && t > p2End
        ? Qt.rect(x + body.x, y + body.y, body.width, body.height) : Qt.rect(0, 0, 0, 0)
    signal closed()

    // --- источник ---
    readonly property real sx: !isNaN(srcX) ? srcX
        : dirX < 0 ? -fly : dirX > 0 ? width + fly : width / 2
    readonly property real sy: !isNaN(srcY) ? srcY
        : dirY < 0 ? -fly : dirY > 0 ? height + fly : height / 2
    // с какой стороны карточки источник (к нему обращена «шейка»)
    readonly property real sdx: sx < 0 ? -1 : sx > width ? 1 : 0
    readonly property real sdy: sdx !== 0 ? 0 : sy < 0 ? -1 : sy > height ? 1 : 0

    // --- ход анимации ---
    property real t: 0
    readonly property real p1End: 0.22
    readonly property real p2End: 0.5
    readonly property bool rest: t >= 1 && !anim.running

    // капля ещё держится за плитку — плитка тянется следом
    onTChanged: {
        if (!pullKey) return;
        const p = mapToItem(null, sx, sy);
        ShellState.pullPoint = Qt.point(p.x + screenOffset.x, p.y + screenOffset.y);
        ShellState.pullR = dropR;
        ShellState.pullKey = pullKey;
        ShellState.pull = t > 0 && t < p1End ? outCubic(t / p1End) : 0;
    }
    // Пока капля держится за край, её рисует сам остров дока (край вздувается
    // и отпускает каплю) — здесь её не рисуем, чтобы не было двух капель.
    readonly property string islandId: {
        const i = pullKey.indexOf("/");
        if (i < 0) return "";
        return pullKey.slice(0, i) + "/" + (pullKey.slice(i + 1).startsWith("top:") ? "top" : "apps");
    }
    readonly property bool fromIsland: pullKey !== "" && ShellState.islandReady[islandId] === true
    readonly property bool handOff: fromIsland && t < p1End
    Component.onDestruction: if (pullKey && ShellState.pullKey === pullKey) ShellState.pull = 0

    NumberAnimation {
        id: anim
        target: root
        property: "t"
        easing.type: Easing.Linear
        onFinished: if (root.t <= 0 && !root.open) root.closed()
    }
    function go() {
        const to = open ? 1 : 0;
        if (t === to && !anim.running) return;
        anim.stop();
        anim.from = t;
        anim.to = to;
        // длинный путь (окно приложений из дока) — чуть дольше
        const dist = Math.hypot(sx - land.x, sy - land.y);
        const full = Math.min(1250, 720 + dist * 0.6);
        anim.duration = Math.max(1, Math.round(Math.abs(to - t) * (to > 0 ? full : full * 0.72)));
        anim.start();
    }
    // сразу карточка, без анимации (обратный путь «Настроек» начинается с окна)
    function snapOpen() { anim.stop(); t = 1; }
    onOpenChanged: {
        // закрыли, не успев открыть, — сообщаем сразу, владелец выгрузит окно
        if (!open && t <= 0 && !anim.running) { closed(); return; }
        go();
    }
    Component.onCompleted: go()

    // --- кривые ---
    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }
    function clamp01(x) { return clamp(x, 0, 1); }
    function outCubic(x) { return 1 - Math.pow(1 - x, 3); }
    function inOutCubic(x) { return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; }
    function outBack(x, s) { const y = x - 1; return 1 + (s + 1) * y * y * y + s * y * y; }
    function mix(a, b, x) { return a + (b - a) * x; }
    function mixColor(a, b, x) { return Qt.rgba(mix(a.r, b.r, x), mix(a.g, b.g, x), mix(a.b, b.b, x), mix(a.a, b.a, x)); }
    // перелёт пружины не больше ~16 px
    function overshootFor(dist) {
        const d = Math.abs(dist);
        if (d < 1) return 1;
        const frac = Math.min(0.09, 16 / d);
        let lo = 0, hi = 1.70158;
        for (let i = 0; i < 18; i++) {
            const s = (lo + hi) / 2;
            if (4 * s * s * s / (27 * (s + 1) * (s + 1)) > frac) hi = s; else lo = s;
        }
        return lo;
    }

    readonly property real dropR: Math.max(10, Math.min(16, Math.min(width, height) * 0.2))
    // куда капля «приземляется» внутри карточки, прежде чем растечься
    readonly property point land: {
        const inset = Math.min(64, Math.min(width, height) * 0.3);
        return Qt.point(clamp(sx, inset, Math.max(inset, width - inset)), clamp(sy, inset, Math.max(inset, height - inset)));
    }

    // --- форма в момент t (в координатах карточки) ---
    readonly property var g: {
        const t = root.t, R = dropR;
        const p1 = clamp01(t / p1End), p2 = clamp01((t - p1End) / (p2End - p1End)), p3 = clamp01((t - p2End) / (1 - p2End));
        const r = R * (0.35 + 0.65 * outCubic(p1));
        // 1. капля выходит из источника в сторону карточки
        const e1 = mix(-0.6 * R, 0.55 * R, outCubic(p1));
        const start = Qt.point(sx - sdx * 0.55 * R, sy - sdy * 0.55 * R);
        const c = t < p1End ? Qt.point(sx - sdx * e1, sy - sdy * e1)
                            : Qt.point(mix(start.x, land.x, inOutCubic(p2)), mix(start.y, land.y, inOutCubic(p2)));
        // 2. в полёте капля вытягивается вдоль пути
        const stretch = Math.sin(Math.PI * p2);
        const dx = land.x - start.x, dy = land.y - start.y;
        const alongY = Math.abs(dy) >= Math.abs(dx);
        const longR = r * (1 + 0.4 * stretch) * (1 - p3);
        const shortR = r * (1 - 0.16 * stretch) * (1 - p3);

        // полоска у источника — «край дока» вздувается и отпускает каплю
        const bt = 5 * outCubic(p1) * (1 - p2);
        let band = Qt.rect(0, 0, 0, 0);
        if (bt > 0.3 && (sdx !== 0 || sdy !== 0)) {
            const bl = R * 3.4;
            band = sdy < 0 ? Qt.rect(sx - bl / 2, sy - 8, bl, bt + 8)
                 : sdy > 0 ? Qt.rect(sx - bl / 2, sy - bt, bl, bt + 8)
                 : sdx < 0 ? Qt.rect(sx - 8, sy - bl / 2, bt + 8, bl)
                 :           Qt.rect(sx - bt, sy - bl / 2, bt + 8, bl);
        }

        // 3. капля растекается в карточку от точки приземления
        let bodyRect = Qt.rect(0, 0, 0, 0), bodyR = R;
        if (t > p2End) {
            const ew = outBack(p3, overshootFor(width)), eh = outBack(p3, overshootFor(height));
            const w = mix(2 * R, width, ew), h = mix(2 * R, height, eh);
            const x = mix(land.x - R, 0, ew), y = mix(land.y - R, 0, eh);
            bodyRect = Qt.rect(x, y, Math.max(1, w), Math.max(1, h));
            bodyR = mix(R, radiusOpen, outCubic(p3));
        }
        const rx = alongY ? shortR : longR, ry = alongY ? longR : shortR;
        return {
            band: band,
            drop: Qt.vector4d(c.x, c.y, Math.max(0, rx), Math.max(0, ry)),
            body: bodyRect,
            bodyR: bodyR,
            hit: t > p2End ? bodyRect : Qt.rect(c.x - rx, c.y - ry, 2 * rx, 2 * ry),
            colorMix: clamp01((p3 - 0.15) / 0.55),
            glow: 1 - p3
        };
    }

    readonly property color cardColor: strong ? Theme.glass2 : Theme.glass

    RectangularShadow {
        anchors.fill: body
        radius: body.radius
        blur: 40
        offset.y: 14
        color: Qt.rgba(0, 0, 0, 0.38)
        opacity: root.rest ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    // жидкость рисуется в рамке, охватывающей и карточку, и источник
    Goo {
        id: goo
        readonly property real pad: 40
        x: Math.min(0, root.sx - pad)
        y: Math.min(0, root.sy - pad)
        width: Math.max(root.width, root.sx + pad) - x
        height: Math.max(root.height, root.sy + pad) - y
        visible: !root.rest && root.t > 0
        band: root.handOff ? Qt.rect(0, 0, 0, 0) : Qt.rect(root.g.band.x - x, root.g.band.y - y, root.g.band.width, root.g.band.height)
        drop: root.handOff ? Qt.vector4d(0, 0, 0, 0) : Qt.vector4d(root.g.drop.x - x, root.g.drop.y - y, root.g.drop.z, root.g.drop.w)
        body: Qt.rect(root.g.body.x - x, root.g.body.y - y, root.g.body.width, root.g.body.height)
        bodyR: root.g.bodyR
        k: 12
        glow: root.g.glow
        // капля из острова — того же стекла, что и док, иначе — цвета акцента
        color: root.mixColor(root.fromIsland ? Theme.glass : root.ballColor, root.cardColor, root.g.colorMix)
    }

    Rectangle {
        id: body
        readonly property rect r: root.rest ? Qt.rect(0, 0, root.width, root.height) : root.g.hit
        x: r.x
        y: r.y
        width: Math.max(0, r.width)
        height: Math.max(0, r.height)
        radius: Math.min(root.rest ? root.radiusOpen : root.g.bodyR, width / 2, height / 2)
        color: root.rest ? root.cardColor : "transparent"
        border.width: root.rest ? 1 : 0
        border.color: Theme.line
        clip: true

        // содержимое не меняет размер во время морфинга: оно стоит на месте
        // карточки, а растущее тело его открывает
        Item {
            id: inner
            x: -body.x
            y: -body.y
            width: root.width
            height: root.height
            opacity: root.open && root.t > 0.86 ? 1 : 0
            // открытое окно должно уметь взять фокус ещё до конца анимации
            visible: opacity > 0 || root.open
            Behavior on opacity { NumberAnimation { duration: inner.opacity < 0.5 ? 260 : 90; easing.type: Easing.OutCubic } }
        }
    }
}
