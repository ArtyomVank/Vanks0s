import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common
import qs.common.ui
import qs.wallpaper

// Отладка: витрина компонентов common/ui.
//   DELTA_DEV_NAME=kit DELTA_SHELL_ENTRY=delta/shell/dev-kit.qml tools/delta-dev.sh nested 120
ShellRoot {
    Variants {
        model: Quickshell.screens
        delegate: Wallpaper { required property ShellScreen modelData; screen: modelData }
    }

    FloatingWindow {
        title: "Delta UI kit"
        implicitWidth: 460
        implicitHeight: 560
        color: "transparent"

        Glass {
            anchors.fill: parent
            strong: true

            ColumnLayout {
                anchors { fill: parent; margins: 18 }
                spacing: 14

                Label { text: "Компоненты Delta"; size: "h1" }

                Card {
                    title: "Строки"
                    SettingRow {
                        icon: "bell-off"; title: "Не беспокоить"; subtitle: "Скрывать всплывающие уведомления"
                        Toggle { id: tg; checked: true; onToggled: v => checked = v }
                    }
                    SettingRow {
                        icon: "sun"; title: "Яркость"; wide: true
                        Slider { id: sl; value: 0.6; onMoved: v => value = v }
                    }
                    SettingRow {
                        icon: "dock"; title: "Длина дока"; wide: true
                        Chips {
                            id: ch
                            current: "compact"
                            model: [{ value: "full", label: "Полный" }, { value: "tiles", label: "Плиточный" }, { value: "compact", label: "Компактный" }]
                            onPicked: v => current = v
                        }
                    }
                }

                RowLayout {
                    spacing: 8
                    Btn { text: "Применить"; kind: "accent" }
                    Btn { text: "Отмена" }
                    Btn { icon: "power"; text: "Выключить"; kind: "danger" }
                    Btn { icon: "settings" }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 10
                    Repeater {
                        model: Object.keys(Icons.names)
                        delegate: Sym { required property string modelData; name: modelData; size: 20; color: Theme.fg2 }
                    }
                }
                Item { Layout.fillHeight: true }
            }
        }
    }
}
