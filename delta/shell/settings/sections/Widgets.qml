pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common
import qs.common.ui
import qs.services
import qs.widgets.parts

// Виджеты: редактор рабочего стола, город для погоды, часы по умолчанию, единицы.
// «Настройки» — отдельный процесс, поэтому редактор открываем через IPC оболочки.
ColumnLayout {
    id: root

    property string title: I18n.tr("Виджеты")
    property string icon: "widgets"
    property string keywords: "виджеты рабочий стол часы погода город градусы фаренгейт показатели редактор"
    spacing: 18

    WeatherUser { active: root.visible }

    Card {
        title: I18n.tr("Рабочий стол")
        SettingRow {
            icon: "grid"
            title: I18n.tr("Редактор виджетов")
            subtitle: I18n.tr("Расставьте виджеты прямо на столе. Super+W")
            Btn {
                text: I18n.tr("Открыть")
                kind: "accent"
                onClicked: Quickshell.execDetached(["delta-shell", "ipc", "call", "widgets", "edit"])
            }
        }
    }

    Card {
        title: I18n.tr("Часы")
        SettingRow {
            icon: "clock"
            title: I18n.tr("Стиль")
            subtitle: I18n.tr("Для всех часов, если у них не выбран свой")
            wide: true
            Chips {
                model: [{ value: "ios", label: "iOS" }, { value: "thin", label: I18n.tr("Тонкие") }, { value: "mono", label: I18n.tr("Моно") },
                        { value: "neon", label: I18n.tr("Неон") }, { value: "stack", label: I18n.tr("Столбиком") },
                        { value: "serif", label: I18n.tr("С засечками") }, { value: "wide", label: I18n.tr("Разрядка") },
                        { value: "outline", label: I18n.tr("Контур") }, { value: "minimal", label: I18n.tr("Минимум") },
                        { value: "tall", label: I18n.tr("Длинные") }]
                current: Settings.get("clock.style", "ios")
                onPicked: v => Settings.set("clock.style", v)
            }
        }
        SettingRow {
            visible: Settings.get("clock.style", "ios") === "tall"
            icon: "sliders"
            title: I18n.tr("Ширина цифр")
            subtitle: I18n.tr("Только для стиля «Длинные»")
            Slider {
                implicitWidth: 220
                from: 0.35; to: 0.95
                value: Number(Settings.get("clock.tallWidth", 0.62)) || 0.62
                onReleased: v => Settings.set("clock.tallWidth", Math.round(v * 100) / 100)
            }
        }
        SettingRow {
            icon: "palette"
            title: I18n.tr("Цвет")
            wide: true
            Chips {
                model: [{ value: "white", label: I18n.tr("Белые") }, { value: "accent", label: I18n.tr("Акцент") },
                        { value: "gradient", label: I18n.tr("Градиент") }, { value: "glass", label: I18n.tr("Стекло") }]
                current: Settings.get("clock.color", "white")
                onPicked: v => Settings.set("clock.color", v)
            }
        }
    }

    Card {
        title: I18n.tr("Погода")
        SettingRow {
            icon: "globe"
            title: I18n.tr("Город")
            subtitle: Weather.loading ? "Ищем…"
                : Weather.error.length ? Weather.error
                : Weather.hasData ? "Найдено: " + [Weather.place.name, Weather.place.admin, Weather.place.country].filter((s, i, a) => s && a.indexOf(s) === i).join(", ")
                : "Прогноз Open-Meteo, обновляется раз в 20 минут"
            wide: true
            RowLayout {
                spacing: 8
                Field {
                    id: city
                    Layout.fillWidth: true
                    icon: "search"
                    placeholder: I18n.tr("Например, Москва")
                    text: Settings.get("weather.city", "")
                    onAccepted: v => Settings.set("weather.city", v.trim())
                }
                Btn { text: I18n.tr("Найти"); implicitHeight: 32; onClicked: Settings.set("weather.city", city.text.trim()) }
            }
        }
        SettingRow {
            icon: "thermometer"
            title: I18n.tr("Единицы")
            Chips {
                model: [{ value: "c", label: I18n.tr("°C, м/с") }, { value: "f", label: I18n.tr("°F, миль/ч") }]
                current: Settings.get("weather.units", "c")
                onPicked: v => Settings.set("weather.units", v)
            }
        }
    }
}
