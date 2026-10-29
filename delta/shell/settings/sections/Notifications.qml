import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui

// Уведомления: «Не беспокоить», время показа, экран блокировки, индикаторы.
// Оболочка следит за settings.json, поэтому изменения применяются сразу.
ColumnLayout {
    id: root

    property string title: "Уведомления"
    property string icon: "bell"
    property string keywords: "уведомления не беспокоить тихо всплывающие экран блокировки громкость яркость раскладка индикатор osd"
    spacing: 18

    Card {
        title: "Уведомления"
        SettingRow {
            icon: "bell-off"; title: "Не беспокоить"; subtitle: "Всплывающие уведомления скрыты, кроме важных; всё остаётся в центре уведомлений (Super+N)"
            Toggle { checked: Settings.get("notifications.dnd", false) === true; onToggled: v => Settings.set("notifications.dnd", v) }
        }
        SettingRow {
            icon: "clock"; title: "Сколько показывать"; subtitle: "Если приложение не задало своё время. Наведение мыши задерживает уведомление"; wide: true
            Chips {
                model: [{ value: 4, label: "4 с" }, { value: 6, label: "6 с" }, { value: 10, label: "10 с" }, { value: 20, label: "20 с" }]
                current: Settings.get("notifications.timeout", 6)
                onPicked: v => Settings.set("notifications.timeout", v)
            }
        }
        SettingRow {
            icon: "lock"; title: "На экране блокировки"; subtitle: "Показывать последние уведомления на экране блокировки"
            Toggle { checked: Settings.get("notifications.onLock", true) !== false; onToggled: v => Settings.set("notifications.onLock", v) }
        }
    }

    Card {
        title: "Индикаторы"
        SettingRow {
            icon: "volume"; title: "Громкость и яркость"; subtitle: "Шарик выходит из дока приложений при изменении клавишами"
            Toggle { checked: Settings.get("osd.enabled", true) !== false; onToggled: v => Settings.set("osd.enabled", v) }
        }
        SettingRow {
            icon: "keyboard"; title: "Раскладка клавиатуры"; subtitle: "Коротко показывать новую раскладку при переключении"
            Toggle { checked: Settings.get("osd.layout", true) !== false; onToggled: v => Settings.set("osd.layout", v) }
        }
    }

    Card {
        title: "По приложениям"
        SettingRow {
            icon: "apps"; title: "Настройка для отдельных приложений"; subtitle: "Скоро: отключить или сделать тихими уведомления выбранных программ"
        }
    }
}
