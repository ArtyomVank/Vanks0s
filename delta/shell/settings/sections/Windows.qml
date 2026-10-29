import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.settings.parts

// Окна приложений: всё уходит в Hyprland через delta-apply (раздел windows.*).
ColumnLayout {
    id: root

    property string title: "Окна"
    property string icon: "windows"
    property string keywords: "отступы рамка скругление размытие анимации желе сворачивание кнопки заголовок"
    spacing: 18

    readonly property var w: Settings.s.windows || ({})

    Card {
        title: "Расположение"
        SettingRow {
            icon: "windows"
            title: "Плавающие окна"
            subtitle: "Окна можно двигать и растягивать, а не раскладывать плиткой"
            Toggle { checked: root.w.floating ?? true; onToggled: v => Settings.set("windows.floating", v) }
        }
        SliderRow {
            icon: "grid"
            title: "Отступы между окнами"
            from: 0; to: 40; step: 1; unit: " px"
            value: root.w.gapsIn ?? 6
            onCommit: v => Settings.set("windows.gapsIn", Math.round(v))
        }
        SliderRow {
            icon: "monitor"
            title: "Отступ от краёв экрана"
            from: 0; to: 80; step: 1; unit: " px"
            value: root.w.gapsOut ?? 14
            onCommit: v => Settings.set("windows.gapsOut", Math.round(v))
        }
    }

    Card {
        title: "Вид"
        SliderRow {
            icon: "windows"
            title: "Рамка активного окна"
            subtitle: "Цвет рамки — цвет оформления"
            from: 0; to: 6; step: 1; unit: " px"
            value: root.w.border ?? 2
            onCommit: v => Settings.set("windows.border", Math.round(v))
        }
        SliderRow {
            icon: "grid"
            title: "Скругление углов окон"
            from: 0; to: 30; step: 1; unit: " px"
            value: root.w.rounding ?? 16
            onCommit: v => Settings.set("windows.rounding", Math.round(v))
        }
        SettingRow {
            icon: "eye"
            title: "Размытие под прозрачными окнами"
            subtitle: "Стекло у терминала, доков и меню. Выключите на слабой видеокарте"
            Toggle { checked: root.w.blur ?? true; onToggled: v => Settings.set("windows.blur", v) }
        }
        SettingRow {
            icon: "windows"
            title: "Кнопки окна"
            subtitle: "Свернуть, развернуть и закрыть в правом верхнем углу активного окна"
            Toggle { checked: root.w.buttons ?? true; onToggled: v => Settings.set("windows.buttons", v) }
        }
        SettingRow {
            icon: "windows"
            title: "Программы со своими кнопками"
            readonly property var list: Array.isArray(root.w.buttonsSkip) ? root.w.buttonsSkip : []
            subtitle: "Браузеры, Electron и программы GNOME рисуют кнопки сами — кнопки Delta им не добавляются. "
                    + "Ещё одну программу можно добавить правым щелчком по кнопкам Delta на её окне. Сейчас в списке: " + list.length
            Btn {
                text: "Сбросить"
                onClicked: Settings.set("windows.buttonsSkip", (Settings.defaults.windows || {}).buttonsSkip || [])
            }
        }
    }

    Card {
        title: "Анимации"
        SettingRow {
            icon: "play"
            title: "Анимации окон"
            subtitle: "Открытие, закрытие, переключение рабочих столов"
            Toggle { checked: root.w.animations ?? true; onToggled: v => Settings.set("windows.animations", v) }
        }
        SettingRow {
            icon: "windows"
            title: "Анимация открытия"
            subtitle: "«Сборка» — окно собирается из центра с пружинкой"
            Chips {
                opacity: (root.w.animations ?? true) ? 1 : 0.45
                model: [{ value: "popin", label: "Сборка" }, { value: "slide", label: "Выезд" }, { value: "fade", label: "Плавно" }]
                current: root.w.openAnim ?? "popin"
                onPicked: v => Settings.set("windows.openAnim", v)
            }
        }
        SettingRow {
            icon: "dock"
            title: "Сворачивание в значок"
            subtitle: "Окно утекает в свой значок в доке"
            Toggle { checked: root.w.genie ?? true; onToggled: v => Settings.set("windows.genie", v) }
        }
        SettingRow {
            icon: "windows"
            title: "Желе при перетаскивании"
            subtitle: "Окно догоняет курсор на пружине и покачивается, когда его тащат или растягивают"
            Chips {
                model: [{ value: 0, label: "Выкл" }, { value: 0.5, label: "Слабо" }, { value: 1, label: "Средне" }, { value: 1.7, label: "Сильно" }]
                current: root.w.jelly ?? 0.5
                onPicked: v => Settings.set("windows.jelly", v)
            }
        }
    }
}
