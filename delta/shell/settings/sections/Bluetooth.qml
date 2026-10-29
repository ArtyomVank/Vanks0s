pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.common
import qs.common.ui

// Раздел «Bluetooth»: адаптер, сопряжённые устройства, поиск новых.
// Сопряжение с вводом PIN Quickshell пока не поддерживает — такие
// устройства сопрягаются, только если не спрашивают код.
ColumnLayout {
    id: root

    property string title: "Bluetooth"
    property string icon: "bluetooth"
    property string keywords: "блютуз устройства наушники мышь клавиатура сопряжение"
    spacing: 18

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter?.enabled ?? false
    readonly property var all: adapter ? adapter.devices.values : []
    readonly property var paired: all.filter(d => d.paired).sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
    readonly property var found: all.filter(d => !d.paired && d.name).sort((a, b) => a.name.localeCompare(b.name))

    function status(d) {
        switch (d.state) {
        case BluetoothDeviceState.Connecting: return "Подключение…";
        case BluetoothDeviceState.Disconnecting: return "Отключение…";
        case BluetoothDeviceState.Connected: return "Подключено" + (d.batteryAvailable ? " · заряд " + Math.round(d.battery * 100) + "%" : "");
        }
        return d.pairing ? "Сопряжение…" : d.paired ? "Не подключено" : d.address;
    }

    // поиск выключаем, когда раздел закрыт
    Binding {
        when: root.adapter !== null && !root.visible
        target: root.adapter
        property: "discovering"
        value: false
        restoreMode: Binding.RestoreNone
    }

    Card {
        title: "Адаптер"
        SettingRow {
            icon: "bluetooth"
            title: root.adapter ? (root.adapter.name || "Bluetooth") : "Bluetooth недоступен"
            subtitle: !root.adapter ? "Нет адаптера или не запущена служба bluetooth.service"
                : root.adapter.state === BluetoothAdapterState.Blocked ? "Заблокирован (rfkill)"
                : root.on ? "Включён" : "Выключен"
            Toggle {
                visible: root.adapter !== null
                enabled: root.adapter?.state !== BluetoothAdapterState.Blocked
                checked: root.on
                onToggled: v => root.adapter.enabled = v
            }
        }
        SettingRow {
            visible: root.on
            icon: "eye"
            title: "Виден другим устройствам"
            subtitle: "Другие устройства смогут найти этот компьютер"
            Toggle {
                checked: root.adapter?.discoverable ?? false
                onToggled: v => root.adapter.discoverable = v
            }
        }
    }

    Card {
        title: "Мои устройства"
        visible: root.on
        SettingRow {
            visible: root.paired.length === 0
            title: "Сопряжённых устройств нет"
        }
        Repeater {
            model: root.paired
            delegate: SettingRow {
                id: dev
                required property BluetoothDevice modelData
                icon: modelData.icon || "bluetooth"
                title: modelData.name || modelData.address
                subtitle: root.status(modelData)
                Row {
                    spacing: 8
                    Btn {
                        text: dev.modelData.connected ? "Отключить" : "Подключить"
                        kind: dev.modelData.connected ? "soft" : "accent"
                        onClicked: dev.modelData.connected ? dev.modelData.disconnect() : dev.modelData.connect()
                    }
                    Btn { text: "Забыть"; kind: "danger"; onClicked: dev.modelData.forget() }
                }
            }
        }
    }

    Card {
        title: "Другие устройства"
        visible: root.on
        SettingRow {
            icon: "search"
            title: root.adapter?.discovering ? "Идёт поиск…" : "Поиск новых устройств"
            subtitle: "Переведите устройство в режим сопряжения"
            Btn {
                text: root.adapter?.discovering ? "Остановить" : "Искать"
                active: root.adapter?.discovering ?? false
                onClicked: root.adapter.discovering = !root.adapter.discovering
            }
        }
        Repeater {
            model: root.found
            delegate: SettingRow {
                id: nd
                required property BluetoothDevice modelData
                icon: modelData.icon || "bluetooth"
                title: modelData.name
                subtitle: root.status(modelData)
                Btn {
                    text: nd.modelData.pairing ? "Отмена" : "Сопрячь"
                    onClicked: nd.modelData.pairing ? nd.modelData.cancelPair() : nd.modelData.pair()
                }
            }
        }
    }
}
