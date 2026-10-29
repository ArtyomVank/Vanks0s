import QtQuick
import QtQuick.Effects
import qs.common

// Тело дока: «край экрана вздувается → капля отрывается и стекает → растекается
// в панель» и обратно (собирается в каплю и втягивается в край).
//
// Вся анимация — одно число t от 0 (спрятан) до 1 (панель). Каждая фаза
// берёт свой кусок t и свою кривую, а форму рисует шейдер (Goo): капля
// слита с краем мягким минимумом, поэтому при отрыве тянется «шейка».
// Если наведение мыши дёргается посреди анимации, t просто идёт обратно из
// текущего места — без скачков и без «застрявших» состояний.
//
// В покое панель — тоже жидкость («желе»): под курсором вздувается и тянется
// за ним с запаздыванием, от нажатия сплющивается и колышется, при смене
// длины поджимается поперёк. Всё это — пружины (Spring), poke() — толчок извне.
//
// Окно-владелец заполняет Island целиком; тело ставится от края `edge`.
// Содержимое кладётся в `content` (центр тела) и само задаёт свой размер,
// чтобы во время морфинга не было перераскладки.
Item {
    id: root

    property string edge: "bottom"
    readonly property bool vertical: edge === "left" || edge === "right"
    // открытый размер: вдоль края и поперёк
    property real along: 300
    property real thick: 60
    property real radiusOpen: thick / 2
    // зазор между краем экрана и доком
    property real margin: 10
    property bool want: true
    // плитки: в открытом виде без общей подложки (каждый элемент — своё стекло)
    property bool tiles: false
    property bool editing: false
    // какой это док и где окно на экране — чтобы край вздувался каплей
    // там, откуда течёт меню (ShellState.pullPoint)
    property string screenName: ""
    property string dockId: "top"        // top | apps
    property point origin: Qt.point(0, 0)

    default property alias content: holder.data
    readonly property alias body: body
    // 0 за краем, 1 капля у края, 2 капля летит / растекается, 3 панель
    readonly property int stage: t <= 0 ? 0 : t < p1End ? 1 : t < 1 ? 2 : 3
    readonly property bool isOpen: t >= 1
    readonly property bool hidden: t <= 0 && !anim.running
    readonly property real contentOpacity: holder.opacity
    readonly property bool hovered: bodyHover.hovered

    // --- ход анимации ---
    property real t: 0
    readonly property real p1End: 0.26      // край вздулся, капля показалась
    readonly property real p2End: 0.52      // капля оторвалась и долетела до места дока
    readonly property bool rest: t >= 1 && !anim.running

    NumberAnimation {
        id: anim
        target: root
        property: "t"
        easing.type: Easing.Linear
    }
    function go() {
        const to = want ? 1 : 0;
        if (t === to && !anim.running) return;
        anim.stop();
        anim.from = t;
        anim.to = to;
        // открытие чуть дольше закрытия: капле нужно «стечь»
        anim.duration = Math.max(1, Math.round(Math.abs(to - t) * (to > 0 ? 1000 : 720)));
        anim.start();
    }
    onWantChanged: go()
    Component.onCompleted: go()

    // --- открытый размер с пружиной (полоса ↔ пилюля, режим правки) ---
    property real osMorph: 1
    property bool morph: false
    property real aOpen: along
    property real cOpen: thick
    Behavior on aOpen { enabled: root.rest; NumberAnimation { duration: 680; easing.type: Easing.OutBack; easing.overshoot: root.osMorph } }
    Behavior on cOpen { enabled: root.rest; NumberAnimation { duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
    onAlongChanged: if (rest) {
        osMorph = overshootFor(aOpen - along);
        morph = true;
        morphTimer.restart();
        // объём «сохраняется»: вытягиваясь вдоль края, панель на миг худеет поперёк
        const d = (along - aOpen) / Math.max(1, aOpen);
        jC.kick(-Math.max(-1.6, Math.min(1.6, d * 2.4)));
    }
    Timer { id: morphTimer; interval: 720; onTriggered: root.morph = false }

    // Пружина с перелётом не больше ~20 px, чтобы длинная панель не вылезала за экран.
    // Пик перелёта OutBack: 4s³ / 27(s+1)² от расстояния.
    function overshootFor(dist) {
        const d = Math.abs(dist);
        if (d < 1) return 1;
        const frac = Math.min(0.09, 20 / d);
        let lo = 0, hi = 1.70158;
        for (let i = 0; i < 18; i++) {
            const s = (lo + hi) / 2;
            if (4 * s * s * s / (27 * (s + 1) * (s + 1)) > frac) hi = s; else lo = s;
        }
        return lo;
    }

    // --- «желе» в покое ---
    // jA, jC — относительная деформация вдоль края и поперёк (0 — покой)
    Spring { id: jA; stiffness: 300; damping: 12 }
    Spring { id: jC; stiffness: 340; damping: 10 }
    // толчок извне: сменился стол, пришло уведомление, щелчок по модулю
    function poke(strength) {
        if (!rest) return;
        const k = strength === undefined ? 1 : strength;
        jC.kick(-2.4 * k);
        jA.kick(0.8 * k);
    }
    // докатилась до места — чуть колышется, как упавшая капля
    onRestChanged: if (rest) poke(0.7)
    Connections {
        target: ShellState
        function onDockPoked(id, k) { if (id === root.dockId) root.poke(k); }
    }

    // выпуклость под курсором: тянется за мышью с запаздыванием и вытягивается
    // хвостом при быстром движении
    readonly property real devU: ShellState.devHover[screenName + "/" + dockId] ?? -1
    readonly property bool liquidHover: rest && !tiles && !editing && (bodyHover.hovered || devU >= 0)
    Spring { id: hv; target: root.liquidHover ? 1 : 0; stiffness: 170; damping: 16 }
    Spring { id: hu; stiffness: 240; damping: 19; epsilon: 0.2 }
    readonly property real cursorU: devU >= 0 ? devU
        : vertical ? body.y + bodyHover.point.position.y : body.x + bodyHover.point.position.x
    onCursorUChanged: if (liquidHover) hu.target = cursorU
    // курсор только вошёл — капля рождается под ним, а не едет от края
    onLiquidHoverChanged: if (liquidHover && hv.value < 0.05) { hu.snap(cursorU); hu.target = cursorU; }
    readonly property vector4d hoverDrop: {
        const h = Math.max(0, hv.value);
        if (h < 0.01) return Qt.vector4d(0, 0, 0, 0);
        const R = cOpen * 0.3 * Math.min(1.15, h);
        const stretch = Math.min(0.9, Math.abs(hu.velocity) / 1400);
        const mid = (vertical ? height : width) / 2, half = aOpen / 2 - cOpen * 0.6;
        const u = Math.max(mid - half, Math.min(mid + half, hu.value));
        // центр капли чуть внутри внешнего края панели — край вздувается наружу
        const v = margin + thick / 2 + cOpen * (1 + jC.value) / 2 - R * 0.62;
        const c = rectAt(u, v, 0, 0);
        const ra = R * (1 + stretch), rc = R * (1 - 0.25 * stretch);
        return Qt.vector4d(c.x, c.y, vertical ? rc : ra, vertical ? ra : rc);
    }
    // тело в покое с деформацией
    readonly property rect liquidRect: rectAt((vertical ? height : width) / 2, margin + thick / 2,
                                              aOpen * (1 + jA.value), cOpen * (1 + jC.value))

    // --- кривые ---
    function clamp01(x) { return Math.max(0, Math.min(1, x)); }
    function outCubic(x) { return 1 - Math.pow(1 - x, 3); }
    function inOutCubic(x) { return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; }
    function outBack(x, s) { const y = x - 1; return 1 + (s + 1) * y * y * y + s * y * y; }
    function mix(a, b, x) { return a + (b - a) * x; }

    // точка «вдоль края u, от края v» → координаты элемента
    function rectAt(u, v, a, c) {
        // a — вдоль края, c — поперёк; (u, v) — центр
        if (edge === "bottom") return Qt.rect(u - a / 2, height - v - c / 2, a, c);
        if (edge === "top")    return Qt.rect(u - a / 2, v - c / 2, a, c);
        if (edge === "left")   return Qt.rect(v - c / 2, u - a / 2, c, a);
        return Qt.rect(width - v - c / 2, u - a / 2, c, a);
    }

    // --- форма в момент t ---
    readonly property real dropR: Math.min(17, thick * 0.36)
    readonly property var g: {
        const t = root.t, R = dropR;
        const u0 = (vertical ? height : width) / 2;
        const vDock = margin + thick / 2;
        const p1 = clamp01(t / p1End), p2 = clamp01((t - p1End) / (p2End - p1End)), p3 = clamp01((t - p2End) / (1 - p2End));

        // 1. край вздувается: капля выходит из-за края, полоска края утолщается
        // 2. капля отрывается (шейка рвётся сама — растёт расстояние) и стекает
        // 3. капля растекается в панель с пружиной
        const r = R * (0.35 + 0.65 * outCubic(p1));
        const stretch = Math.sin(Math.PI * p2);
        const vd = t < p1End ? mix(-R * 0.6, R * 0.55, outCubic(p1)) : mix(R * 0.55, vDock, inOutCubic(p2));
        const dropAlong = r * (1 - 0.16 * stretch) * (1 - p3);
        const dropAcross = r * (1 + 0.38 * stretch) * (1 - p3);

        const bt = 6 * outCubic(p1) * (1 - p2);
        const band = bt > 0.3 ? rectAt(u0, (bt - 8) / 2, R * 3.4, bt + 8) : Qt.rect(0, 0, 0, 0);

        let bodyRect = Qt.rect(0, 0, 0, 0), bodyR = R;
        if (t > p2End) {
            const bAlong = mix(2 * R, aOpen, outBack(p3, overshootFor(aOpen - 2 * R)));
            const bAcross = mix(2 * R * 0.9, cOpen, outBack(p3, 1.2));
            bodyRect = rectAt(u0, vDock, Math.max(1, bAlong), Math.max(1, bAcross));
            bodyR = mix(R, radiusOpen, outCubic(p3));
        }
        const dr = rectAt(u0, vd, 2 * dropAlong, 2 * dropAcross);
        return {
            band: band,
            drop: Qt.vector4d(dr.x + dr.width / 2, dr.y + dr.height / 2, Math.max(0, dr.width / 2), Math.max(0, dr.height / 2)),
            body: bodyRect,
            bodyR: bodyR,
            // тело для маски ввода и наведения: панель или прямоугольник капли
            hit: t > p2End ? bodyRect : dr,
            colorMix: clamp01((p3 - 0.15) / 0.55),
            glow: 1 - p3
        };
    }

    // --- край вздувается каплей (меню, окно приложений, «Настройки») ---
    // Карточка в своём окне рисует каплю только после отрыва; до отрыва капля —
    // часть острова: растёт из края, тянет шейку и отпускает. Когда капля
    // возвращается, край её втягивает. После отрыва и втягивания край пружинит.
    readonly property bool pullMine: {
        const k = ShellState.pullKey, pre = screenName + "/";
        if (!screenName || !k.startsWith(pre)) return false;
        const top = k.slice(pre.length).startsWith("top:");
        return dockId === "top" ? top : !top;
    }
    readonly property real pullTarget: pullMine && rest ? ShellState.pull : 0
    property real bulge: 0
    onPullTargetChanged: {
        if (pullTarget > 0) { wobble.stop(); bulge = pullTarget; }
        else if (bulge > 0.05) wobble.restart();
        else bulge = 0;
    }
    SequentialAnimation {
        id: wobble
        NumberAnimation { target: root; property: "bulge"; to: 0; duration: 70; easing.type: Easing.InQuad }
        NumberAnimation { target: root; property: "bulge"; to: 0.32; duration: 150; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "bulge"; to: 0; duration: 280; easing.type: Easing.InOutQuad }
    }
    readonly property bool bulging: rest && bulge > 0.001
    readonly property vector4d bulgeDrop: {
        const R = ShellState.pullR > 0 ? ShellState.pullR : dropR;
        const b = Math.max(0, bulge);
        const lx = ShellState.pullPoint.x - origin.x, ly = ShellState.pullPoint.y - origin.y;
        const half = aOpen / 2 - R, mid = (vertical ? height : width) / 2;
        const u = Math.max(mid - half, Math.min(mid + half, vertical ? ly : lx));
        const c = rectAt(u, margin + cOpen + mix(-0.6 * R, 0.55 * R, b), 0, 0);
        const r = R * (0.35 + 0.65 * b);
        return Qt.vector4d(c.x, c.y, r, r);
    }
    // остров готов рисовать каплю сам — сообщаем карточкам
    readonly property bool pullReady: rest && screenName !== ""
    function publishReady() {
        if (!screenName) return;
        const r = Object.assign({}, ShellState.islandReady);
        r[screenName + "/" + dockId] = pullReady;
        ShellState.islandReady = r;
    }
    onPullReadyChanged: publishReady()
    onScreenNameChanged: publishReady()

    readonly property rect restRect: rectAt((vertical ? height : width) / 2, margin + thick / 2, aOpen, cOpen)

    readonly property color openColor: tiles ? Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0) : Theme.glass
    function mixColor(a, b, x) { return Qt.rgba(mix(a.r, b.r, x), mix(a.g, b.g, x), mix(a.b, b.b, x), mix(a.a, b.a, x)); }

    // мягкая тень открытой панели
    RectangularShadow {
        anchors.fill: body
        radius: body.radius
        blur: 40
        offset.y: root.vertical ? 0 : 10
        color: Qt.rgba(0, 0, 0, root.tiles ? 0 : 0.30)
        opacity: root.rest ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 220 } }
    }

    // Панель всегда рисует жидкость: при выезде — капля и тело по t, в покое —
    // «желе» (деформированное тело, выпуклость под курсором, капля меню из края)
    // с обводкой по общему контуру. Rectangle ниже — только размер и ввод.
    Goo {
        anchors.fill: parent
        visible: root.t > 0
        readonly property bool resting: root.rest
        band: resting ? Qt.rect(0, 0, 0, 0) : root.g.band
        drop: resting ? (root.bulging ? root.bulgeDrop : Qt.vector4d(0, 0, 0, 0)) : root.g.drop
        drop2: resting ? root.hoverDrop : Qt.vector4d(0, 0, 0, 0)
        body: resting ? (root.tiles ? Qt.rect(0, 0, 0, 0) : root.liquidRect) : root.g.body
        bodyR: resting ? root.radiusOpen : root.g.bodyR
        k: 13
        glow: resting ? 0 : root.g.glow
        color: resting ? (root.tiles ? Theme.glass : root.openColor) : root.mixColor(Theme.accent, root.openColor, root.g.colorMix)
        strokeColor: resting && !root.tiles ? (root.editing ? Theme.accent : Theme.line) : "transparent"
        strokeW: root.editing ? 1.5 : 1
    }

    Rectangle {
        id: body
        readonly property rect r: root.rest ? root.restRect : root.g.hit
        x: r.x
        y: r.y
        width: Math.max(0, r.width)
        height: Math.max(0, r.height)
        radius: Math.min(root.rest ? root.radiusOpen : root.g.bodyR, width / 2, height / 2)
        color: "transparent"
        // у сплошной панели обводку рисует Goo; у плиток — рамка режима правки
        border.width: root.rest && root.tiles && root.editing ? 1.5 : 0
        border.color: Theme.accent
        // в открытом виде значки увеличиваются и подсказки выходят за край панели
        clip: !root.rest || root.morph

        HoverHandler { id: bodyHover }
        // нажатие в любом месте панели: сплющивается и отпружинивает
        // (пассивный захват — модулям и значкам щелчок доходит как обычно)
        PointHandler {
            acceptedButtons: Qt.AllButtons
            onActiveChanged: {
                if (!root.rest) return;
                if (active) { jC.kick(-2.6); jA.kick(0.7); }
                else { jC.kick(1.8); jA.kick(-0.5); }
            }
        }

        Item {
            id: holder
            anchors.centerIn: parent
            width: 0
            height: 0
            opacity: root.want && root.t > 0.86 ? 1 : 0
            visible: opacity > 0
            // содержимое колышется вместе с «желе», но вполсилы
            transform: Scale {
                xScale: 1 + 0.5 * (root.vertical ? jC.value : jA.value)
                yScale: 1 + 0.5 * (root.vertical ? jA.value : jC.value)
            }
            Behavior on opacity { NumberAnimation { duration: holder.opacity < 0.5 ? 280 : 120; easing.type: Easing.OutCubic } }
        }
    }
}
