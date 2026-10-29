import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.settings.parts

// Мышь и тачпад: input.* — их применяет delta-apply.
ColumnLayout {
    id: root

    property string title: I18n.tr("Мышь и тачпад")
    property string icon: "mouse"
    property string keywords: "чувствительность скорость указатель прокрутка тап касание тачпад"
    spacing: 18

    readonly property var i: Settings.s.input || ({})

    Card {
        title: I18n.tr("Указатель")
        SliderRow {
            icon: "cursor"
            title: I18n.tr("Скорость указателя")
            subtitle: I18n.tr("Середина — как задумал производитель")
            from: -1; to: 1; step: 0.05
            value: root.i.sensitivity ?? 0
            format: v => (v > 0 ? "+" : "") + v.toFixed(2)
            onCommit: v => Settings.set("input.sensitivity", Math.round(v * 100) / 100)
        }
    }

    Card {
        title: I18n.tr("Тачпад")
        SettingRow {
            icon: "mouse"
            title: I18n.tr("Естественная прокрутка")
            subtitle: I18n.tr("Как на телефоне: страница едет за пальцами")
            Toggle { checked: root.i.naturalScroll ?? true; onToggled: v => Settings.set("input.naturalScroll", v) }
        }
        SettingRow {
            icon: "check"
            title: I18n.tr("Нажатие касанием")
            subtitle: I18n.tr("Щелчок лёгким касанием")
            Toggle { checked: root.i.tapToClick ?? true; onToggled: v => Settings.set("input.tapToClick", v) }
        }
        SettingRow {
            icon: "windows"
            title: I18n.tr("Жесты")
            subtitle: I18n.tr("Проведите тремя пальцами вбок, чтобы сменить стол")
            Label { text: I18n.tr("включены"); tone: 3 }
        }
    }
}
