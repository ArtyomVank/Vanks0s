import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui

// Уведомления: «Не беспокоить», время показа, экран блокировки, индикаторы.
// Оболочка следит за settings.json, поэтому изменения применяются сразу.
ColumnLayout {
    id: root

    property string title: I18n.tr("Уведомления")
    property string icon: "bell"
    property string keywords: "уведомления не беспокоить тихо всплывающие экран блокировки громкость яркость раскладка индикатор osd"
    spacing: 18

    Card {
        title: I18n.tr("Уведомления")
        SettingRow {
            icon: "bell-off"; title: I18n.tr("Не беспокоить"); subtitle: I18n.tr("Сообщения не всплывают, но ждут вас в центре уведомлений")
            Toggle { checked: Settings.get("notifications.dnd", false) === true; onToggled: v => Settings.set("notifications.dnd", v) }
        }
        SettingRow {
            icon: "clock"; title: I18n.tr("Сколько показывать"); subtitle: I18n.tr("Пока мышь над уведомлением, оно не исчезнет"); wide: true
            Chips {
                model: [{ value: 4, label: I18n.tr("4 с") }, { value: 6, label: I18n.tr("6 с") }, { value: 10, label: I18n.tr("10 с") }, { value: 20, label: I18n.tr("20 с") }]
                current: Settings.get("notifications.timeout", 6)
                onPicked: v => Settings.set("notifications.timeout", v)
            }
        }
        SettingRow {
            icon: "lock"; title: I18n.tr("На экране блокировки"); subtitle: I18n.tr("Видны, пока экран заблокирован")
            Toggle { checked: Settings.get("notifications.onLock", true) !== false; onToggled: v => Settings.set("notifications.onLock", v) }
        }
    }

    Card {
        title: I18n.tr("Индикаторы")
        SettingRow {
            icon: "volume"; title: I18n.tr("Громкость и яркость"); subtitle: I18n.tr("Показывать уровень, когда меняете клавишами")
            Toggle { checked: Settings.get("osd.enabled", true) !== false; onToggled: v => Settings.set("osd.enabled", v) }
        }
        SettingRow {
            icon: "keyboard"; title: I18n.tr("Раскладка клавиатуры"); subtitle: I18n.tr("Подсказка при смене языка")
            Toggle { checked: Settings.get("osd.layout", true) !== false; onToggled: v => Settings.set("osd.layout", v) }
        }
    }

    Card {
        title: I18n.tr("По приложениям")
        SettingRow {
            icon: "apps"; title: I18n.tr("Настройка для отдельных приложений"); subtitle: I18n.tr("Скоро")
        }
    }
}
