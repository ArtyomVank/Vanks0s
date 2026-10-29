pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Pipewire
import qs.common

// Визуализатор: столбики пляшут под уровень звука узла PipeWire (поток
// плеера или выход по умолчанию). PwNodePeakMonitor даёт только пики по
// каналам, а не спектр, поэтому рисуем «эхо»: свежий уровень — в центре,
// более старые расходятся к краям, у каждого столбика своё дыхание.
// Таймер и захват работают, только пока виджет виден и музыка играет.
Item {
    id: root

    property PwNode node: null
    property bool playing: false
    property int bars: 28
    // для проверки без звука: 0…1 — подставной уровень, -1 — настоящий
    property real demo: -1
    readonly property bool active: playing && visible && (node !== null || demo >= 0)

    implicitHeight: 40

    PwNodePeakMonitor {
        id: peaks
        node: root.node
        enabled: root.active && root.demo < 0
    }

    property var history: []
    property var levels: []
    property real t: 0

    Timer {
        interval: 33
        repeat: true
        running: root.active || root.settling
        onTriggered: root.tick()
    }
    property bool settling: false
    onActiveChanged: if (!active) settling = true

    function tick() {
        t += 0.033;
        const half = Math.ceil(bars / 2);
        let p = 0;
        if (active) {
            p = demo >= 0 ? demo * (0.6 + 0.4 * Math.abs(Math.sin(t * 7.3))) : peaks.peak;
            // громкость воспринимается логарифмически — поднимаем тихие места
            p = Math.pow(Math.max(0, Math.min(1, p)), 0.55);
        }
        const h = history.slice(0, half);
        h.unshift(p);
        history = h;
        const out = [];
        let sum = 0;
        for (let i = 0; i < bars; i++) {
            const d = Math.abs(i - (bars - 1) / 2) / ((bars - 1) / 2);
            const v = h[Math.min(h.length - 1, Math.floor(d * (half - 1)))] || 0;
            const wobble = 0.72 + 0.28 * Math.sin(t * (3 + (i * 7) % 5) + i * 1.7);
            const target = Math.max(0.1, v * (1 - 0.25 * d) * wobble);
            const prev = levels[i] ?? 0.1;
            // быстро вверх, плавно вниз
            const next = target > prev ? prev + (target - prev) * 0.6 : prev + (target - prev) * 0.18;
            out.push(next);
            sum += next;
        }
        levels = out;
        if (!active && sum < bars * 0.105) settling = false;
    }

    Row {
        anchors.fill: parent
        spacing: 3

        Repeater {
            model: root.bars
            delegate: Rectangle {
                required property int index
                width: (root.width - (root.bars - 1) * 3) / root.bars
                height: root.height * (root.levels[index] ?? 0.1)
                y: root.height - height
                radius: Math.min(3, width / 2)
                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.accents[1] }
                    GradientStop { position: 1; color: Theme.accent }
                }
            }
        }
    }
}
