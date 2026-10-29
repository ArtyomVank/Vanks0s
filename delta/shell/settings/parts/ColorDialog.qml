import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui

// Выбор любого цвета: квадрат насыщенность/яркость, полоса оттенка, поле #hex.
//     ColorDialog { id: cd; onPicked: c => Settings.set("appearance.accent", c) }
//     cd.openWith(Theme.accent)
Dialog {
    id: root

    property real hue: 0.7
    property real sat: 0.65
    property real val: 1
    readonly property color value: Qt.hsva(hue, sat, val, 1)
    readonly property string hex: "#" + [value.r, value.g, value.b].map(c => Math.round(c * 255).toString(16).padStart(2, "0")).join("").toUpperCase()
    signal picked(string hex)

    function openWith(c) {
        const col = Qt.color(c);
        hue = col.hsvHue < 0 ? hue : col.hsvHue;
        sat = col.hsvSaturation;
        val = col.hsvValue;
        hexField.text = hex;
        open();
    }

    title: "Свой цвет оформления"
    subtitle: "Капли доков, кнопки, выделение и рамка активного окна"
    cardWidth: 420

    RowLayout {
        spacing: 14
        Layout.fillWidth: true

        // насыщенность (вправо) и яркость (вверх)
        Rectangle {
            id: sv
            Layout.fillWidth: true
            implicitHeight: 200
            radius: 12
            clip: true
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#ffffff" }
                GradientStop { position: 1; color: Qt.hsva(root.hue, 1, 1, 1) }
            }
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: "#000000" }
                }
            }
            Rectangle {
                width: 18; height: 18; radius: 9
                x: root.sat * sv.width - 9
                y: (1 - root.val) * sv.height - 9
                color: root.value
                border.width: 3
                border.color: "#ffffff"
            }
            MouseArea {
                anchors.fill: parent
                preventStealing: true
                cursorShape: Qt.CrossCursor
                function pick(m) {
                    root.sat = Math.max(0, Math.min(1, m.x / width));
                    root.val = Math.max(0, Math.min(1, 1 - m.y / height));
                    hexField.text = root.hex;
                }
                onPressed: m => pick(m)
                onPositionChanged: m => { if (pressed) pick(m); }
            }
        }

        // оттенок
        Rectangle {
            id: hueBar
            implicitWidth: 22
            implicitHeight: 200
            radius: 11
            gradient: Gradient {
                GradientStop { position: 0.00; color: "#ff0000" }
                GradientStop { position: 0.17; color: "#ffff00" }
                GradientStop { position: 0.33; color: "#00ff00" }
                GradientStop { position: 0.50; color: "#00ffff" }
                GradientStop { position: 0.67; color: "#0000ff" }
                GradientStop { position: 0.83; color: "#ff00ff" }
                GradientStop { position: 1.00; color: "#ff0000" }
            }
            Rectangle {
                width: 28; height: 10; radius: 5
                x: -3
                y: root.hue * hueBar.height - 5
                color: "transparent"
                border.width: 3
                border.color: "#ffffff"
            }
            MouseArea {
                anchors.fill: parent
                preventStealing: true
                cursorShape: Qt.PointingHandCursor
                function pick(m) { root.hue = Math.max(0, Math.min(0.999, m.y / height)); hexField.text = root.hex; }
                onPressed: m => pick(m)
                onPositionChanged: m => { if (pressed) pick(m); }
            }
        }
    }

    RowLayout {
        spacing: 10
        Layout.fillWidth: true
        Rectangle { implicitWidth: 38; implicitHeight: 38; radius: 19; color: root.value; border.color: Theme.line }
        Field {
            id: hexField
            Layout.fillWidth: true
            placeholder: "#7C5CFF"
            maxLength: 7
            error: !/^#[0-9A-Fa-f]{6}$/.test(text)
            onEdited: if (/^#[0-9A-Fa-f]{6}$/.test(text)) {
                const c = Qt.color(text);
                if (c.hsvHue >= 0) root.hue = c.hsvHue;
                root.sat = c.hsvSaturation;
                root.val = c.hsvValue;
            }
        }
    }

    buttons: [
        Btn { text: "Отмена"; onClicked: root.close() },
        Btn { text: "Готово"; kind: "accent"; onClicked: { root.picked(root.hex); root.close(); } }
    ]
}
