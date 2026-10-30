import QtQuick
import QtQuick.Layouts
import qs.common

// Строки настроек «Длинных» часов: вид цифр, ширина и толщина линий.
// Сам ничего не пишет — отдаёт picked(ключ, значение), ключи как у виджета
// часов: tallKind, tallWidth, tallThick.
//     TallClockRows { kind: …; widthRatio: …; thick: …; onPicked: (key, v) => … }
ColumnLayout {
    id: root

    property string kind: "line"
    property real widthRatio: 0.62
    property real thick: 1
    signal picked(string key, var value)

    spacing: 0
    Layout.fillWidth: true

    SettingRow {
        icon: "font"; title: I18n.tr("Вид цифр"); wide: true
        Chips {
            current: root.kind
            model: [{ value: "line", label: I18n.tr("Линии") }, { value: "hollow", label: I18n.tr("Пустые внутри") },
                    { value: "column", label: I18n.tr("В столбик") }]
            onPicked: v => root.picked("tallKind", v)
        }
    }
    SettingRow {
        icon: "sliders"; title: I18n.tr("Ширина цифр")
        Slider {
            implicitWidth: 220
            from: 0.35; to: 0.95
            value: root.widthRatio
            onReleased: v => root.picked("tallWidth", Math.round(v * 100) / 100)
        }
    }
    SettingRow {
        icon: "sliders"; title: I18n.tr("Толщина линий"); subtitle: I18n.tr("Чем больше, тем жирнее цифры")
        Slider {
            implicitWidth: 220
            from: 0.5; to: 2.4
            value: root.thick
            onReleased: v => root.picked("tallThick", Math.round(v * 100) / 100)
        }
    }
}
