import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.settings.parts

// Окна приложений: всё уходит в Hyprland через delta-apply (раздел windows.*).
ColumnLayout {
    id: root

    property string title: I18n.tr("Окна")
    property string icon: "windows"
    property string keywords: "отступы рамка скругление размытие анимации желе сворачивание кнопки заголовок"
    spacing: 18

    readonly property var w: Settings.s.windows || ({})

    Card {
        title: I18n.tr("Расположение")
        SettingRow {
            icon: "windows"
            title: I18n.tr("Плавающие окна")
            subtitle: I18n.tr("Окна лежат свободно, как на обычном столе")
            Toggle { checked: root.w.floating ?? true; onToggled: v => Settings.set("windows.floating", v) }
        }
        SliderRow {
            icon: "grid"
            title: I18n.tr("Отступы между окнами")
            from: 0; to: 40; step: 1; unit: " px"
            value: root.w.gapsIn ?? 6
            onCommit: v => Settings.set("windows.gapsIn", Math.round(v))
        }
        SliderRow {
            icon: "monitor"
            title: I18n.tr("Отступ от краёв экрана")
            from: 0; to: 80; step: 1; unit: " px"
            value: root.w.gapsOut ?? 14
            onCommit: v => Settings.set("windows.gapsOut", Math.round(v))
        }
    }

    Card {
        title: I18n.tr("Вид")
        SliderRow {
            icon: "windows"
            title: I18n.tr("Рамка активного окна")
            subtitle: I18n.tr("Рамка в цвет оформления")
            from: 0; to: 6; step: 1; unit: " px"
            value: root.w.border ?? 2
            onCommit: v => Settings.set("windows.border", Math.round(v))
        }
        SliderRow {
            icon: "grid"
            title: I18n.tr("Скругление углов окон")
            from: 0; to: 30; step: 1; unit: " px"
            value: root.w.rounding ?? 16
            onCommit: v => Settings.set("windows.rounding", Math.round(v))
        }
        SettingRow {
            icon: "eye"
            title: I18n.tr("Размытие под прозрачными окнами")
            subtitle: I18n.tr("Красиво, но нагружает видеокарту")
            Toggle { checked: root.w.blur ?? true; onToggled: v => Settings.set("windows.blur", v) }
        }
        SettingRow {
            icon: "windows"
            title: I18n.tr("Кнопки окна")
            subtitle: I18n.tr("Свернуть, развернуть и закрыть")
            Toggle { checked: root.w.buttons ?? true; onToggled: v => Settings.set("windows.buttons", v) }
        }
        SettingRow {
            icon: "windows"
            title: I18n.tr("Программы со своими кнопками")
            readonly property var list: Array.isArray(root.w.buttonsSkip) ? root.w.buttonsSkip : []
            subtitle: I18n.tr("Браузеры и программы GNOME рисуют кнопки сами, им наши не нужны. В списке: ") + list.length
            Btn {
                text: I18n.tr("Сбросить")
                onClicked: Settings.set("windows.buttonsSkip", (Settings.defaults.windows || {}).buttonsSkip || [])
            }
        }
    }

    Card {
        title: I18n.tr("Анимации")
        SettingRow {
            icon: "play"
            title: I18n.tr("Анимации окон")
            subtitle: I18n.tr("Окна и столы двигаются плавно")
            Toggle { checked: root.w.animations ?? true; onToggled: v => Settings.set("windows.animations", v) }
        }
        SettingRow {
            icon: "windows"
            title: I18n.tr("Анимация открытия")
            subtitle: I18n.tr("Как окно появляется на экране")
            Chips {
                opacity: (root.w.animations ?? true) ? 1 : 0.45
                model: [{ value: "popin", label: I18n.tr("Сборка") }, { value: "slide", label: I18n.tr("Выезд") }, { value: "fade", label: I18n.tr("Плавно") }]
                current: root.w.openAnim ?? "popin"
                onPicked: v => Settings.set("windows.openAnim", v)
            }
        }
        SettingRow {
            icon: "dock"
            title: I18n.tr("Сворачивание в значок")
            subtitle: I18n.tr("Свёрнутое окно утекает в значок дока")
            Toggle { checked: root.w.genie ?? true; onToggled: v => Settings.set("windows.genie", v) }
        }
        SettingRow {
            icon: "windows"
            title: I18n.tr("Желе при перетаскивании")
            subtitle: I18n.tr("Окно чуть покачивается, когда его тащат")
            Chips {
                model: [{ value: 0, label: I18n.tr("Выкл") }, { value: 0.5, label: I18n.tr("Слабо") }, { value: 1, label: I18n.tr("Средне") }, { value: 1.7, label: I18n.tr("Сильно") }]
                current: root.w.jelly ?? 0.5
                onPicked: v => Settings.set("windows.jelly", v)
            }
        }
    }
}
