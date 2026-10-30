pragma ComponentBehavior: Bound

import QtQuick
import qs.common

// Искры: короткий всплеск звёздочек-ромбиков из центра — вокруг значка или
// заголовка. Размер — по размеру элемента; ввод не перехватывает.
//     Sparkles { id: spark; anchors.centerIn: icon; width: 120; height: 120 }
//     spark.burst()
Item {
    id: root

    property int count: 14
    property var colors: [Theme.accent, "#FFFFFF", "#FFD166"]
    property real t: 1
    property real seed: 0

    function burst() {
        seed = Math.random() * 100;
        anim.restart();
    }
    NumberAnimation { id: anim; target: root; property: "t"; from: 0; to: 1; duration: 950; easing.type: Easing.OutCubic }

    // псевдослучайное 0…1 — у каждой искры своё, но стабильное на весь залп
    function rnd(i, k) {
        const v = Math.sin(i * 12.9898 + k * 78.233 + seed) * 43758.5453;
        return v - Math.floor(v);
    }

    Repeater {
        model: root.count
        delegate: Rectangle {
            id: spark
            required property int index
            readonly property real a: index / root.count * Math.PI * 2 + root.rnd(index, 1) * 0.6
            readonly property real dist: Math.min(root.width, root.height) / 2 * (0.55 + 0.45 * root.rnd(index, 2))
            readonly property real s: 4 + 6 * root.rnd(index, 3)
            width: s; height: s
            radius: s * 0.15
            color: root.colors[index % root.colors.length]
            x: root.width / 2 + Math.cos(a) * dist * root.t - s / 2
            y: root.height / 2 + Math.sin(a) * dist * root.t - s / 2
            rotation: 45 + root.t * 180
            scale: Math.sin(Math.PI * Math.min(1, root.t * 1.15))
            opacity: root.t < 1 ? 1 - root.t * root.t : 0
            visible: root.t < 1
        }
    }
}
