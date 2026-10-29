import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.settings.parts

// Мышь и тачпад: input.* — их применяет delta-apply.
ColumnLayout {
    id: root

    property string title: "Мышь и тачпад"
    property string icon: "mouse"
    property string keywords: "чувствительность скорость указатель прокрутка тап касание тачпад"
    spacing: 18

    readonly property var i: Settings.s.input || ({})

    Card {
        title: "Указатель"
        SliderRow {
            icon: "cursor"
            title: "Скорость указателя"
            subtitle: "0 — как задано устройством"
            from: -1; to: 1; step: 0.05
            value: root.i.sensitivity ?? 0
            format: v => (v > 0 ? "+" : "") + v.toFixed(2)
            onCommit: v => Settings.set("input.sensitivity", Math.round(v * 100) / 100)
        }
    }

    Card {
        title: "Тачпад"
        SettingRow {
            icon: "mouse"
            title: "Естественная прокрутка"
            subtitle: "Содержимое движется за пальцами, как на телефоне"
            Toggle { checked: root.i.naturalScroll ?? true; onToggled: v => Settings.set("input.naturalScroll", v) }
        }
        SettingRow {
            icon: "check"
            title: "Нажатие касанием"
            subtitle: "Лёгкое касание тачпада — щелчок"
            Toggle { checked: root.i.tapToClick ?? true; onToggled: v => Settings.set("input.tapToClick", v) }
        }
        SettingRow {
            icon: "windows"
            title: "Жесты"
            subtitle: "Три пальца влево-вправо — переключение рабочих столов"
            Label { text: "включены"; tone: 3 }
        }
    }
}
