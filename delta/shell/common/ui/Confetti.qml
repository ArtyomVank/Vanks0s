pragma ComponentBehavior: Bound

import QtQuick
import qs.common

// Конфетти: залп из точки, кусочки летят, кружатся и падают. Кладётся поверх
// всего (anchors.fill), ввод не перехватывает.
//     Confetti { id: boom; anchors.fill: parent }
//     boom.burst(x, y)
Item {
    id: root

    property int count: 90
    property var colors: [Theme.accent, "#FFD166", "#06D6A0", "#EF476F", "#4CC9F0", "#FFFFFF"]
    property var parts: []

    function burst(x, y) {
        const out = [];
        for (let i = 0; i < count; i++) {
            const a = -Math.PI / 2 + (Math.random() - 0.5) * Math.PI * 1.25;
            const v = 520 + Math.random() * 760;
            out.push({
                x: x, y: y,
                vx: Math.cos(a) * v, vy: Math.sin(a) * v,
                rot: Math.random() * 360, vr: (Math.random() - 0.5) * 900,
                w: 6 + Math.random() * 8, h: 4 + Math.random() * 6,
                color: colors[i % colors.length],
                life: 0, ttl: 1.8 + Math.random() * 1.2
            });
        }
        parts = out;
        tick.running = true;
    }

    FrameAnimation {
        id: tick
        onTriggered: {
            const dt = Math.min(0.05, frameTime);
            let alive = 0;
            const next = root.parts;
            for (const p of next) {
                p.life += dt;
                if (p.life >= p.ttl) continue;
                alive++;
                p.vy += 1500 * dt;                  // тяжесть
                p.vx *= Math.pow(0.35, dt);         // воздух
                p.vy *= Math.pow(0.55, dt);
                p.x += p.vx * dt;
                p.y += p.vy * dt;
                p.rot += p.vr * dt;
            }
            root.parts = next;
            if (alive === 0) { running = false; root.parts = []; }
        }
    }

    Repeater {
        model: root.parts.length
        delegate: Rectangle {
            id: bit
            required property int index
            readonly property var p: root.parts[index] || ({})
            x: (p.x || 0) - width / 2
            y: (p.y || 0) - height / 2
            width: p.w || 0
            height: (p.h || 0) * Math.abs(Math.cos((p.rot || 0) * Math.PI / 90))   // переворачивается в полёте
            radius: 1.5
            rotation: p.rot || 0
            color: p.color || "white"
            opacity: 1 - Math.max(0, ((p.life || 0) - (p.ttl || 1) + 0.5) / 0.5)
        }
    }
}
