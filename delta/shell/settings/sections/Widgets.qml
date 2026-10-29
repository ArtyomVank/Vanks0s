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

    property string title: "Виджеты"
    property string icon: "widgets"
    property string keywords: "виджеты рабочий стол часы погода город градусы фаренгейт показатели редактор"
    spacing: 18

    WeatherUser { active: root.visible }

    Card {
        title: "Рабочий стол"
        SettingRow {
            icon: "grid"
            title: "Редактор виджетов"
            subtitle: "Расставить, добавить и убрать виджеты, поменять размер и вид. Super+W"
            Btn {
                text: "Открыть"
                kind: "accent"
                onClicked: Quickshell.execDetached(["delta-shell", "ipc", "call", "widgets", "edit"])
            }
        }
    }

    Card {
        title: "Часы"
        SettingRow {
            icon: "clock"
            title: "Стиль"
            subtitle: "Для часов, у которых в редакторе не выбран свой стиль"
            wide: true
            Chips {
                model: [{ value: "ios", label: "iOS" }, { value: "thin", label: "Тонкие" }, { value: "mono", label: "Моно" },
                        { value: "neon", label: "Неон" }, { value: "stack", label: "Столбиком" },
                        { value: "serif", label: "С засечками" }, { value: "wide", label: "Разрядка" },
                        { value: "outline", label: "Контур" }, { value: "minimal", label: "Минимум" },
                        { value: "tall", label: "Длинные" }]
                current: Settings.get("clock.style", "ios")
                onPicked: v => Settings.set("clock.style", v)
            }
        }
        SettingRow {
            visible: Settings.get("clock.style", "ios") === "tall"
            icon: "sliders"
            title: "Ширина цифр"
            subtitle: "Для «Длинных» часов; у отдельных часов — ползунок в редакторе"
            Slider {
                implicitWidth: 220
                from: 0.35; to: 0.95
                value: Number(Settings.get("clock.tallWidth", 0.62)) || 0.62
                onReleased: v => Settings.set("clock.tallWidth", Math.round(v * 100) / 100)
            }
        }
        SettingRow {
            icon: "palette"
            title: "Цвет"
            wide: true
            Chips {
                model: [{ value: "white", label: "Белые" }, { value: "accent", label: "Акцент" },
                        { value: "gradient", label: "Градиент" }, { value: "glass", label: "Стекло" }]
                current: Settings.get("clock.color", "white")
                onPicked: v => Settings.set("clock.color", v)
            }
        }
    }

    Card {
        title: "Погода"
        SettingRow {
            icon: "globe"
            title: "Город"
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
                    placeholder: "Например, Москва"
                    text: Settings.get("weather.city", "")
                    onAccepted: v => Settings.set("weather.city", v.trim())
                }
                Btn { text: "Найти"; implicitHeight: 32; onClicked: Settings.set("weather.city", city.text.trim()) }
            }
        }
        SettingRow {
            icon: "thermometer"
            title: "Единицы"
            Chips {
                model: [{ value: "c", label: "°C, м/с" }, { value: "f", label: "°F, миль/ч" }]
                current: Settings.get("weather.units", "c")
                onPicked: v => Settings.set("weather.units", v)
            }
        }
    }
}
