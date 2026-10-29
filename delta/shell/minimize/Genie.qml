pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common

// Слой анимации «джинн» одного монитора. Виден только во время анимации и
// пропускает клики насквозь. Регистрируется в Minimizer.genies.
//
//   capture(toplevel, rect, done)   снять окно (rect — где оно на экране);
//                                   done(ItemGrabResult | null)
//   play(url, src, dst, edge, reverse, onCovered, onDone)
//       reverse=false: снимок из src в значок dst; onCovered — снимок уже
//       закрыл окно, его можно убирать. reverse=true: из значка в окно,
//       onCovered — снимок на месте, пора возвращать окно.
PanelWindow {
    id: win

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "delta-genie"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    mask: Region {}
    visible: capturing || playing

    property bool capturing: false
    property bool playing: false

    Component.onCompleted: register()
    onScreenChanged: register()
    function register() {
        if (!screen) return;
        const g = Object.assign({}, Minimizer.genies);
        g[screen.name] = win;
        Minimizer.genies = g;
    }

    // --- снимок -----------------------------------------------------------

    property var captureDone: null

    ScreencopyView {
        id: cap
        visible: win.capturing
        live: false
        onHasContentChanged: if (hasContent && win.capturing) grabDelay.restart()
    }
    // кадр должен попасть на экран слоя, иначе grabToImage вернёт пустоту
    Timer { id: grabDelay; interval: 32; onTriggered: win.grab() }
    // окно не отдало кадр (уже закрывается, защищено) — сворачиваем без анимации
    Timer { id: captureTimeout; interval: 400; onTriggered: win.finishCapture(null) }

    function capture(toplevel, rect, done) {
        // прежний снимок не успел — его владелец должен узнать, иначе окно
        // навсегда останется «в анимации» и док не спрячется
        if (capturing) finishCapture(null);
        captureDone = done;
        cap.x = rect.x; cap.y = rect.y;
        cap.width = rect.w; cap.height = rect.h;
        cap.captureSource = toplevel;
        capturing = true;
        captureTimeout.restart();
        if (cap.hasContent) grabDelay.restart();
        else cap.captureFrame();
    }
    function grab() {
        if (!cap.grabToImage(r => win.finishCapture(r), Qt.size(cap.width, cap.height))) finishCapture(null);
    }
    function finishCapture(result) {
        if (!capturing) return;
        captureTimeout.stop();
        capturing = false;
        cap.captureSource = null;
        const d = captureDone;
        captureDone = null;
        if (d) d(result);
    }

    // --- анимация ---------------------------------------------------------

    property var onCovered: null
    property var onDone: null
    property bool reverse: false

    Image {
        id: shot
        visible: false
        asynchronous: false
        cache: false
    }

    ShaderEffect {
        id: fx
        anchors.fill: parent
        visible: win.playing
        property real progress: 0
        property real edge: 0
        property rect src
        property rect dst
        property variant source: shot
        // мелкая сетка вдоль пути к доку — бока воронки гнутся плавно
        mesh: GridMesh { resolution: fx.edge >= 2 ? Qt.size(56, 20) : Qt.size(20, 56) }
        vertexShader: Qt.resolvedUrl("shaders/genie.vert.qsb")
        fragmentShader: Qt.resolvedUrl("shaders/genie.frag.qsb")
    }

    NumberAnimation {
        id: run
        target: fx
        property: "progress"
        // кривые — в самом шейдере (воронка, затем ускорение к значку)
        easing.type: Easing.Linear
        onFinished: win.finishPlay()
    }
    FrameAnimation {
        id: coverWait
        onTriggered: {
            if (currentFrame < 2) return;
            stop();
            if (win.onCovered) { const c = win.onCovered; win.onCovered = null; c(); }
        }
    }
    // в обратную сторону окно возвращается под снимок, и только потом снимок гаснет
    Timer { id: settle; interval: 140; onTriggered: win.stopPlay() }

    function play(url, src, dst, edge, back, covered, done) {
        // прерываем прежнюю анимацию, но её колбэки доигрываем: окно должно
        // оказаться на своём месте, а Minimizer — снять отметку «занято»
        if (playing) {
            coverWait.stop();
            settle.stop();
            run.stop();
            if (onCovered) { const c = onCovered; onCovered = null; c(); }
            const d = onDone;
            onDone = null;
            if (d) d();
        }
        settle.stop();
        run.stop();
        onCovered = covered;
        onDone = done;
        reverse = back;
        shot.source = url;
        fx.src = Qt.rect(src.x, src.y, src.w, src.h);
        fx.dst = Qt.rect(dst.x, dst.y, dst.w, dst.h);
        fx.edge = edge;
        fx.progress = back ? 1 : 0;
        run.from = back ? 1 : 0;
        run.to = back ? 0 : 1;
        run.duration = back ? 560 : 700;
        playing = true;
        // окно прячем, только когда снимок уже на экране (через пару кадров):
        // раньше — и окно на кадр пропадало, мигая перед «джинном»
        if (!back) coverWait.restart();
        run.start();
    }
    function finishPlay() {
        if (reverse) {
            if (onCovered) { onCovered(); onCovered = null; }
            settle.restart();
        } else {
            // окно «упало» в док — значки вздрагивают волной
            ShellState.pokeDock("apps", 0.8);
            stopPlay();
        }
    }
    function stopPlay() {
        playing = false;
        shot.source = "";
        const d = onDone;
        onDone = null;
        if (d) d();
    }
}
