import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui

// Строка с ползунком и значением справа (как «Непрозрачность 62 %» в концепте).
//     SliderRow { title: "Отступы"; from: 0; to: 40; step: 1; value: …; unit: " px"
//                 onCommit: v => Settings.set("windows.gapsIn", v) }
// commit приходит при отпускании и колесе: дорогие записи не дёргаются на каждый пиксель.
SettingRow {
    id: root

    property real from: 0
    property real to: 1
    property real step: 0
    property real value: 0
    property string unit: ""
    property var format: null          // v => текст
    property bool live: false          // писать на каждом движении
    property bool enabled: true
    signal commit(real value)

    property real shownValue: value
    onValueChanged: shownValue = value

    wide: true

    RowLayout {
        spacing: 14
        Slider {
            Layout.fillWidth: true
            from: root.from
            to: root.to
            step: root.step
            value: root.value
            enabled: root.enabled
            onMoved: v => { root.shownValue = v; if (root.live) root.commit(v); }
            onReleased: v => root.commit(v)
        }
        Label {
            Layout.preferredWidth: 64
            horizontalAlignment: Text.AlignRight
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
            text: root.format ? root.format(root.shownValue) : (Math.round(root.shownValue) + root.unit)
        }
    }
}
