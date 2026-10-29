pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common
import qs.common.ui
import qs.settings
import qs.settings.parts

// Автозапуск: записи XDG в ~/.config/autostart (helpers/autostart).
// Выключение — Hidden=true в своей копии записи, системные файлы не трогаем.
ColumnLayout {
    id: root

    property string title: "Автозапуск"
    property string icon: "rocket"
    property string keywords: "запуск при входе программы автозагрузка"
    spacing: 18

    property var entries: []
    property bool loaded: false

    function refresh() {
        Exec.read(["bash", Exec.helper("autostart"), "list"], (code, out) => {
            try { root.entries = JSON.parse(out); } catch (e) { root.entries = []; }
            root.loaded = true;
        });
    }
    Component.onCompleted: refresh()

    function op(args, label) {
        Exec.run(["bash", Exec.helper("autostart")].concat(args), {
            label: label, home: true, toast: false,
            done: (code, out, err) => {
                if (code !== 0) Nav.toast("Не получилось: " + (err.trim() || label));
                root.refresh();
            }
        });
    }

    Card {
        title: "При входе запускаются"
        Rows {
            Repeater {
                model: root.entries
                delegate: SettingRow {
                    id: arow
                    required property var modelData
                    icon: modelData.icon || "apps"
                    title: modelData.name
                    subtitle: (modelData.system ? "системная · " : "") + modelData.exec
                    RowLayout {
                        spacing: 10
                        Btn {
                            icon: "trash"; kind: "danger"; iconSize: 16; implicitHeight: 32
                            visible: arow.modelData.user && !arow.modelData.system
                            onClicked: root.op(["remove", arow.modelData.file], "убрать из автозапуска " + arow.modelData.name)
                        }
                        Toggle {
                            checked: !arow.modelData.hidden
                            onToggled: v => root.op(["hide", arow.modelData.file, v ? "false" : "true"], (v ? "включить " : "выключить ") + arow.modelData.name)
                        }
                    }
                }
            }
            SettingRow {
                visible: root.loaded && root.entries.length === 0
                icon: "info"
                title: "Пока ничего"
                subtitle: "Добавьте программу, которая должна открываться сама после входа"
            }
            SettingRow {
                icon: "plus"
                title: "Добавить приложение"
                Btn { text: "Добавить…"; icon: "plus"; onClicked: picker.openWith() }
            }
        }
    }

    Picker {
        id: picker
        title: "Добавить в автозапуск"
        searchHint: "Приложение"
        model: DesktopEntries.applications.values
            .filter(e => !e.noDisplay && root.entries.every(x => x.file !== e.id + ".desktop"))
            .map(e => ({ value: e.id + ".desktop", label: e.name, sub: e.genericName || e.comment || "", icon: e.icon }))
            .sort((a, b) => a.label.localeCompare(b.label))
        onPicked: v => root.op(["add", v], "добавить в автозапуск " + v)
    }

    Connections {
        target: Nav
        function onAction(name, arg) {
            if (name === "autostart.add") { if (arg) root.op(["add", arg], "добавить " + arg); else picker.openWith(); }
            else if (name === "autostart.hide") root.op(["hide", arg, "true"], "выключить " + arg);
            else if (name === "autostart.show") root.op(["hide", arg, "false"], "включить " + arg);
            else if (name === "autostart.remove") root.op(["remove", arg], "убрать " + arg);
        }
    }
}
