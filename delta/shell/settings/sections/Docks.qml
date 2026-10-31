pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.common
import qs.common.ui
import qs.settings.parts

// Доки: край, длина, автоскрытие, увеличение, модули верхнего дока,
// закреплённые приложения. «Настройки» — отдельный процесс, поэтому режим
// правки верхнего дока включаем через IPC оболочки (delta-shell ipc call docks edit).
ColumnLayout {
    id: root

    property string title: I18n.tr("Доки")
    property string icon: "dock"
    property string keywords: "док панель край автоскрытие длина плитки компактный ширина прозрачность непрозрачность модули трей фоновые остров события закреплённые приложения увеличение музыка часы секунды"
    spacing: 18

    readonly property var edges: [{ value: "top", label: I18n.tr("Сверху") }, { value: "bottom", label: I18n.tr("Снизу") }, { value: "left", label: I18n.tr("Слева") }, { value: "right", label: I18n.tr("Справа") }]
    // автоскрытие: false — никогда, true — всегда, "smart" — только когда есть окна
    readonly property var hides: [{ value: false, label: I18n.tr("Нет") }, { value: true, label: I18n.tr("Всегда") }, { value: "smart", label: I18n.tr("Умное") }]
    function hideMode(which, def) {
        const v = Settings.get("docks." + which + ".autohide", def);
        return v === "smart" ? "smart" : v === true;
    }
    readonly property var lengths: [{ value: "full", label: I18n.tr("Полный") }, { value: "tiles", label: I18n.tr("Плитки") }, { value: "compact", label: I18n.tr("Компактный") }]

    // своя непрозрачность дока: нет ключа — как у темы
    function ownOpacity(which) { return Number(Settings.get("docks." + which + ".opacity", -1)) >= 0; }
    function setOwnOpacity(which, on) { Settings.set("docks." + which + ".opacity", on ? Math.round(Theme.opacity * 100) / 100 : -1); }
    function opt(key, def) { return Settings.get("docks.top.opts." + key, def); }

    // Оба дока на одном крае мешают друг другу — второй переезжает на противоположный.
    readonly property var opposite: ({ top: "bottom", bottom: "top", left: "right", right: "left" })
    function setEdge(which, edge) {
        const other = which === "top" ? "apps" : "top";
        if (Settings.get("docks." + other + ".edge", other === "top" ? "top" : "bottom") === edge)
            Settings.set("docks." + other + ".edge", opposite[edge]);
        Settings.set("docks." + which + ".edge", edge);
    }

    Card {
        title: I18n.tr("Верхний док")
        SettingRow {
            icon: "dock"; title: I18n.tr("Край экрана"); wide: true
            Chips { model: root.edges; current: Settings.get("docks.top.edge", "top"); onPicked: v => root.setEdge("top", v) }
        }
        SettingRow {
            icon: "scale"; title: I18n.tr("Длина"); subtitle: I18n.tr("Во всю ширину, отдельными плитками или по размеру содержимого"); wide: true
            Chips { model: root.lengths; current: Settings.get("docks.top.length", "full"); onPicked: v => Settings.set("docks.top.length", v) }
        }
        SliderRow {
            visible: Settings.get("docks.top.length", "full") !== "full"
            icon: "scale"; title: I18n.tr("Ширина")
            subtitle: I18n.tr("Для компактного и плиточного вида: больше — просторнее")
            from: 0.7; to: 1.6; step: 0.05
            value: Number(Settings.get("docks.top.width", 1)) || 1
            format: v => Math.round(v * 100) + " %"
            onCommit: v => Settings.set("docks.top.width", Math.round(v * 100) / 100)
        }
        SettingRow {
            icon: "eye"; title: I18n.tr("Своя прозрачность"); subtitle: I18n.tr("Иначе — как у доков и окон в «Оформлении»")
            Toggle { checked: root.ownOpacity("top"); onToggled: v => root.setOwnOpacity("top", v) }
        }
        SliderRow {
            visible: root.ownOpacity("top")
            icon: "eye"; title: I18n.tr("Непрозрачность")
            from: 0.1; to: 1; step: 0.01
            value: Number(Settings.get("docks.top.opacity", 0.62))
            live: true
            format: v => Math.round(v * 100) + " %"
            onCommit: v => Settings.set("docks.top.opacity", Math.round(v * 100) / 100)
        }
        SettingRow {
            icon: "eye-off"; title: I18n.tr("Скрывать автоматически"); wide: true
            subtitle: I18n.tr("Спрятанный док выходит, если подвести мышь к краю. «Умное» прячет его только когда мешает окно")
            Chips { model: root.hides; current: root.hideMode("top", false); onPicked: v => Settings.set("docks.top.autohide", v) }
        }
        SettingRow {
            icon: "windows"; title: I18n.tr("Рабочие столы"); subtitle: I18n.tr("Сколько столов показывать в доке"); wide: true
            Chips {
                model: [3, 4, 5, 6, 7, 8, 10].map(n => ({ value: n, label: String(n) }))
                current: Number(Settings.get("docks.top.workspaces", 5))
                onPicked: v => Settings.set("docks.top.workspaces", v)
            }
        }
        SettingRow {
            icon: "music"; title: I18n.tr("Плеер вместо дока"); subtitle: I18n.tr("Пока играет музыка, док сворачивается в пилюлю с обложкой")
            Toggle { checked: Settings.get("docks.top.media", true) === true; onToggled: v => Settings.set("docks.top.media", v) }
        }
        SettingRow {
            icon: "bell"; title: I18n.tr("События в острове")
            subtitle: I18n.tr("Зарядка, Bluetooth, снимок экрана, таймер, уведомления в режиме «Не беспокоить»")
            Toggle { checked: Settings.get("docks.top.island", true) !== false; onToggled: v => Settings.set("docks.top.island", v) }
        }
        SettingRow {
            visible: Settings.get("docks.top.island", true) !== false
            icon: "keyboard"; title: I18n.tr("Смена раскладки в острове")
            Toggle { checked: Settings.get("docks.top.islandLayout", false) === true; onToggled: v => Settings.set("docks.top.islandLayout", v) }
        }
        SettingRow {
            icon: "grid"; title: I18n.tr("Модули"); subtitle: I18n.tr("Переставьте, добавьте или уберите то, что видно в доке")
            Btn { text: I18n.tr("Изменить"); kind: "accent"; onClicked: Quickshell.execDetached(["delta-shell", "ipc", "call", "docks", "edit"]) }
        }
    }

    // что показывают модули верхнего дока
    Card {
        title: I18n.tr("Модули верхнего дока")
        SettingRow {
            icon: "calendar"; title: I18n.tr("Дата рядом с часами")
            Toggle { checked: root.opt("calendarDate", true) !== false; onToggled: v => Settings.set("docks.top.opts.calendarDate", v) }
        }
        SettingRow {
            icon: "clock"; title: I18n.tr("Секунды на часах")
            Toggle { checked: root.opt("calendarSeconds", false) === true; onToggled: v => Settings.set("docks.top.opts.calendarSeconds", v) }
        }
        SettingRow {
            icon: "cloud-sun"; title: I18n.tr("Температура у погоды")
            Toggle { checked: root.opt("weatherTemp", true) !== false; onToggled: v => Settings.set("docks.top.opts.weatherTemp", v) }
        }
        SettingRow {
            icon: "battery"; title: I18n.tr("Проценты батареи")
            Toggle { checked: root.opt("batteryPercent", true) !== false; onToggled: v => Settings.set("docks.top.opts.batteryPercent", v) }
        }
        SettingRow {
            icon: "cpu"; title: I18n.tr("Показатели ПК"); wide: true
            Chips {
                model: [{ value: "both", label: I18n.tr("ЦП и ОЗУ") }, { value: "cpu", label: I18n.tr("Только ЦП") }, { value: "ram", label: I18n.tr("Только ОЗУ") }]
                current: root.opt("pcShow", "both")
                onPicked: v => Settings.set("docks.top.opts.pcShow", v)
            }
        }
        SettingRow {
            icon: "layers"; title: I18n.tr("Фоновые приложения"); subtitle: I18n.tr("Сколько значков трея видно, остальные — за «+N»"); wide: true
            Chips {
                model: [3, 5, 8, 12].map(n => ({ value: n, label: String(n) }))
                current: Number(root.opt("trayMax", 5))
                onPicked: v => Settings.set("docks.top.opts.trayMax", v)
            }
        }
    }

    Card {
        title: I18n.tr("Док приложений")
        SettingRow {
            icon: "dock"; title: I18n.tr("Край экрана"); wide: true
            Chips { model: root.edges; current: Settings.get("docks.apps.edge", "bottom"); onPicked: v => root.setEdge("apps", v) }
        }
        SettingRow {
            icon: "scale"; title: I18n.tr("Длина"); wide: true
            Chips { model: root.lengths; current: Settings.get("docks.apps.length", "compact"); onPicked: v => Settings.set("docks.apps.length", v) }
        }
        SliderRow {
            visible: Settings.get("docks.apps.length", "compact") !== "full"
            icon: "scale"; title: I18n.tr("Ширина")
            subtitle: I18n.tr("Для компактного и плиточного вида: больше — просторнее")
            from: 0.7; to: 1.6; step: 0.05
            value: Number(Settings.get("docks.apps.width", 1)) || 1
            format: v => Math.round(v * 100) + " %"
            onCommit: v => Settings.set("docks.apps.width", Math.round(v * 100) / 100)
        }
        SettingRow {
            icon: "eye"; title: I18n.tr("Своя прозрачность"); subtitle: I18n.tr("Иначе — как у доков и окон в «Оформлении»")
            Toggle { checked: root.ownOpacity("apps"); onToggled: v => root.setOwnOpacity("apps", v) }
        }
        SliderRow {
            visible: root.ownOpacity("apps")
            icon: "eye"; title: I18n.tr("Непрозрачность")
            from: 0.1; to: 1; step: 0.01
            value: Number(Settings.get("docks.apps.opacity", 0.62))
            live: true
            format: v => Math.round(v * 100) + " %"
            onCommit: v => Settings.set("docks.apps.opacity", Math.round(v * 100) / 100)
        }
        SettingRow {
            icon: "eye-off"; title: I18n.tr("Скрывать автоматически"); wide: true
            subtitle: I18n.tr("«Умное» прячет док только когда мешает окно")
            Chips { model: root.hides; current: root.hideMode("apps", true); onPicked: v => Settings.set("docks.apps.autohide", v) }
        }
        SettingRow {
            icon: "search"; title: I18n.tr("Увеличение при наведении")
            Toggle { checked: Settings.get("docks.apps.magnify", true) !== false; onToggled: v => Settings.set("docks.apps.magnify", v) }
        }
        SettingRow {
            icon: "windows"; title: I18n.tr("Запущенные приложения"); subtitle: I18n.tr("Открытые программы тоже видны в доке")
            Toggle { checked: Settings.get("docks.apps.showRunning", true) !== false; onToggled: v => Settings.set("docks.apps.showRunning", v) }
        }
    }

    Card {
        title: I18n.tr("Закреплённые")

        Repeater {
            model: {
                const v = Settings.get("docks.apps.pinned", []);
                return Array.isArray(v) ? v : [];
            }
            delegate: SettingRow {
                id: row
                required property var modelData
                required property int index
                readonly property bool isApp: typeof modelData === "string"
                readonly property var entry: {
                    DesktopEntries.applications.values;
                    return isApp ? (DesktopEntries.byId(modelData) ?? DesktopEntries.heuristicLookup(modelData)) : null;
                }
                icon: isApp ? "" : modelData.type === "cmd" ? "terminal" : "folder"
                title: isApp ? (entry ? entry.name : modelData) : (modelData.name || modelData.command || modelData.path)
                subtitle: isApp ? (entry ? "" : "Не установлено") : modelData.type === "cmd" ? modelData.command : modelData.path

                RowLayout {
                    spacing: 4
                    IconImage {
                        visible: row.isApp
                        implicitSize: 24
                        source: row.entry ? Quickshell.iconPath(row.entry.icon, "application-x-executable") : ""
                    }
                    Btn { icon: "chevron-left"; kind: "ghost"; enabled: row.index > 0; onClicked: root.move(row.index, -1) }
                    Btn { icon: "chevron-right"; kind: "ghost"; onClicked: root.move(row.index, 1) }
                    Btn { icon: "trash"; kind: "ghost"; onClicked: root.remove(row.index) }
                }
            }
        }
        SettingRow {
            icon: "plus"; title: I18n.tr("Добавить"); subtitle: I18n.tr("Кнопка «+» в доке: программа, команда, файл или папка")
        }
    }

    function move(i, d) {
        const list = Settings.get("docks.apps.pinned", []).slice();
        const j = i + d;
        if (j < 0 || j >= list.length) return;
        const t = list[i]; list[i] = list[j]; list[j] = t;
        Settings.set("docks.apps.pinned", list);
    }
    function remove(i) {
        const list = Settings.get("docks.apps.pinned", []).slice();
        list.splice(i, 1);
        Settings.set("docks.apps.pinned", list);
    }
}
