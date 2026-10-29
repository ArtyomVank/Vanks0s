pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.common
import qs.common.ui

// Доки: край, длина, автоскрытие, увеличение, модули верхнего дока,
// закреплённые приложения. «Настройки» — отдельный процесс, поэтому режим
// правки верхнего дока включаем через IPC оболочки (delta-shell ipc call docks edit).
ColumnLayout {
    id: root

    property string title: "Доки"
    property string icon: "dock"
    property string keywords: "док панель край автоскрытие длина плитки компактный модули закреплённые приложения увеличение музыка"
    spacing: 18

    readonly property var edges: [{ value: "top", label: "Сверху" }, { value: "bottom", label: "Снизу" }, { value: "left", label: "Слева" }, { value: "right", label: "Справа" }]
    // автоскрытие: false — никогда, true — всегда, "smart" — только когда есть окна
    readonly property var hides: [{ value: false, label: "Нет" }, { value: true, label: "Всегда" }, { value: "smart", label: "Умное" }]
    function hideMode(which, def) {
        const v = Settings.get("docks." + which + ".autohide", def);
        return v === "smart" ? "smart" : v === true;
    }
    readonly property var lengths: [{ value: "full", label: "Полный" }, { value: "tiles", label: "Плитки" }, { value: "compact", label: "Компактный" }]

    // Оба дока на одном крае мешают друг другу — второй переезжает на противоположный.
    readonly property var opposite: ({ top: "bottom", bottom: "top", left: "right", right: "left" })
    function setEdge(which, edge) {
        const other = which === "top" ? "apps" : "top";
        if (Settings.get("docks." + other + ".edge", other === "top" ? "top" : "bottom") === edge)
            Settings.set("docks." + other + ".edge", opposite[edge]);
        Settings.set("docks." + which + ".edge", edge);
    }

    Card {
        title: "Верхний док"
        SettingRow {
            icon: "dock"; title: "Край экрана"; wide: true
            Chips { model: root.edges; current: Settings.get("docks.top.edge", "top"); onPicked: v => root.setEdge("top", v) }
        }
        SettingRow {
            icon: "scale"; title: "Длина"; subtitle: "Во всю ширину, отдельными плитками или по размеру содержимого"; wide: true
            Chips { model: root.lengths; current: Settings.get("docks.top.length", "full"); onPicked: v => Settings.set("docks.top.length", v) }
        }
        SettingRow {
            icon: "eye-off"; title: "Скрывать автоматически"; wide: true
            subtitle: "Спрятанный док выходит, если подвести мышь к краю. «Умное» прячет его только когда мешает окно"
            Chips { model: root.hides; current: root.hideMode("top", false); onPicked: v => Settings.set("docks.top.autohide", v) }
        }
        SettingRow {
            icon: "windows"; title: "Рабочие столы"; subtitle: "Сколько столов показывать в доке"; wide: true
            Chips {
                model: [3, 4, 5, 6, 7, 8, 10].map(n => ({ value: n, label: String(n) }))
                current: Number(Settings.get("docks.top.workspaces", 5))
                onPicked: v => Settings.set("docks.top.workspaces", v)
            }
        }
        SettingRow {
            icon: "music"; title: "Плеер вместо дока"; subtitle: "Пока играет музыка, док сворачивается в пилюлю с обложкой"
            Toggle { checked: Settings.get("docks.top.media", true) === true; onToggled: v => Settings.set("docks.top.media", v) }
        }
        SettingRow {
            icon: "grid"; title: "Модули"; subtitle: "Переставьте, добавьте или уберите то, что видно в доке"
            Btn { text: "Изменить"; kind: "accent"; onClicked: Quickshell.execDetached(["delta-shell", "ipc", "call", "docks", "edit"]) }
        }
    }

    Card {
        title: "Док приложений"
        SettingRow {
            icon: "dock"; title: "Край экрана"; wide: true
            Chips { model: root.edges; current: Settings.get("docks.apps.edge", "bottom"); onPicked: v => root.setEdge("apps", v) }
        }
        SettingRow {
            icon: "scale"; title: "Длина"; wide: true
            Chips { model: root.lengths; current: Settings.get("docks.apps.length", "compact"); onPicked: v => Settings.set("docks.apps.length", v) }
        }
        SettingRow {
            icon: "eye-off"; title: "Скрывать автоматически"; wide: true
            subtitle: "«Умное» прячет док только когда мешает окно"
            Chips { model: root.hides; current: root.hideMode("apps", true); onPicked: v => Settings.set("docks.apps.autohide", v) }
        }
        SettingRow {
            icon: "search"; title: "Увеличение при наведении"
            Toggle { checked: Settings.get("docks.apps.magnify", true) !== false; onToggled: v => Settings.set("docks.apps.magnify", v) }
        }
        SettingRow {
            icon: "windows"; title: "Запущенные приложения"; subtitle: "Открытые программы тоже видны в доке"
            Toggle { checked: Settings.get("docks.apps.showRunning", true) !== false; onToggled: v => Settings.set("docks.apps.showRunning", v) }
        }
    }

    Card {
        title: "Закреплённые"

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
            icon: "plus"; title: "Добавить"; subtitle: "Кнопка «+» в доке: программа, команда, файл или папка"
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
