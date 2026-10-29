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
            icon: "bell-off"; title: "Не беспокоить"; subtitle: "Сообщения не всплывают, но ждут вас в центре уведомлений"
            Toggle { checked: Settings.get("notifications.dnd", false) === true; onToggled: v => Settings.set("notifications.dnd", v) }
        }
        SettingRow {
            icon: "clock"; title: "Сколько показывать"; subtitle: "Пока мышь над уведомлением, оно не исчезнет"; wide: true
            Chips {
                model: [{ value: 4, label: "4 с" }, { value: 6, label: "6 с" }, { value: 10, label: "10 с" }, { value: 20, label: "20 с" }]
                current: Settings.get("notifications.timeout", 6)
                onPicked: v => Settings.set("notifications.timeout", v)
            }
        }
        SettingRow {
            icon: "lock"; title: "На экране блокировки"; subtitle: "Видны, пока экран заблокирован"
            Toggle { checked: Settings.get("notifications.onLock", true) !== false; onToggled: v => Settings.set("notifications.onLock", v) }
        }
    }

    Card {
        title: "Индикаторы"
        SettingRow {
            icon: "volume"; title: "Громкость и яркость"; subtitle: "Показывать уровень, когда меняете клавишами"
            Toggle { checked: Settings.get("osd.enabled", true) !== false; onToggled: v => Settings.set("osd.enabled", v) }
        }
        SettingRow {
            icon: "keyboard"; title: "Раскладка клавиатуры"; subtitle: "Подсказка при смене языка"
            Toggle { checked: Settings.get("osd.layout", true) !== false; onToggled: v => Settings.set("osd.layout", v) }
        }
    }

    Card {
        title: "По приложениям"
        SettingRow {
            icon: "apps"; title: "Настройка для отдельных приложений"; subtitle: "Скоро"
        }
    }
}
