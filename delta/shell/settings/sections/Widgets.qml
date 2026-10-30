pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common
import qs.common.ui
import qs.services
import qs.widgets
import qs.widgets.parts
import qs.lock.parts

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

    // Часы рабочего стола: значение — у самого виджета (его меняет и
    // редактор виджетов), иначе общее clock.*; пишем и туда, и туда —
    // настройки и редактор всегда показывают одно и то же.
    readonly property var deskClock: (Settings.get("widgets.desktop", []) || []).find(x => x && x.id === "clock") || null
    function clockGet(key, def) { return WidgetTypes.clockValue(root.deskClock, key, Settings.get("clock." + key, def)); }
    function setClock(key, value) {
        Settings.set("clock." + key, value);
        const list = Settings.get("widgets.desktop", []);
        if (!Array.isArray(list) || !list.some(w => w && w.id === "clock")) return;
        Settings.set("widgets.desktop", list.map(w => {
            if (!w || w.id !== "clock") return w;
            const c = Object.assign({}, w);
            c[key] = value;
            return c;
        }));
    }

    Card {
        title: I18n.tr("Часы")
        // предпросмотр на обоях
        Item {
            Layout.fillWidth: true
            implicitHeight: 170
            Rectangle {
                anchors { fill: parent; margins: 12 }
                radius: Theme.radius - 6
                clip: true
                color: "#3a4256"
                LockBackground { anchors.fill: parent }
                BigClock {
                    anchors.centerIn: parent
                    style: root.clockGet("style", "ios")
                    tint: root.clockGet("color", "white")
                    tallWidth: Number(root.clockGet("tallWidth", 0.62)) || 0.62
                    tallKind: root.clockGet("tallKind", "line")
                    tallThick: Number(root.clockGet("tallThick", 1)) || 1
                    size: 80
                }
            }
        }
        SettingRow {
            icon: "clock"
            title: I18n.tr("Стиль")
            subtitle: I18n.tr("Часы на рабочем столе. Их же меняет редактор виджетов")
            wide: true
            Chips {
                model: WidgetTypes.clockStyles.map(x => ({ value: x.value, label: I18n.tr(x.label) }))
                current: root.clockGet("style", "ios")
                onPicked: v => root.setClock("style", v)
            }
        }
        TallClockRows {
            visible: root.clockGet("style", "ios") === "tall"
            kind: root.clockGet("tallKind", "line")
            widthRatio: Number(root.clockGet("tallWidth", 0.62)) || 0.62
            thick: Number(root.clockGet("tallThick", 1)) || 1
            onPicked: (key, v) => root.setClock(key, v)
        }
        SettingRow {
            icon: "palette"
            title: I18n.tr("Цвет")
            wide: true
            Chips {
                model: WidgetTypes.clockColors.map(x => ({ value: x.value, label: I18n.tr(x.label) }))
                current: root.clockGet("color", "white")
                onPicked: v => root.setClock("color", v)
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
