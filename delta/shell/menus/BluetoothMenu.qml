pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.common
import qs.common.ui
import qs.launcher.parts

// Меню Bluetooth: вкл/выкл, известные устройства с подключением и
// отключением, поиск новых. Сопряжение с PIN Quickshell пока не умеет —
// для таких устройств отправляем в «Настройки».
Item {
    id: root

    implicitWidth: 320
    implicitHeight: col.implicitHeight
    signal close()

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter?.enabled ?? false

    readonly property var devices: {
        if (!adapter) return [];
        return adapter.devices.values
            .filter(d => d.paired || d.connected || d.trusted || (adapter.discovering && d.name))
            .sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name));
    }

    function status(d) {
        switch (d.state) {
        case BluetoothDeviceState.Connecting: return "Подключение…";
        case BluetoothDeviceState.Disconnecting: return "Отключение…";
        case BluetoothDeviceState.Connected:
            return "Подключено" + (d.batteryAvailable ? " · " + Math.round(d.battery * 100) + "%" : "");
        }
        if (d.pairing) return "Сопряжение…";
        return d.paired ? "Сопряжено" : "Новое устройство";
    }

    function toggle(d) {
        if (d.connected) d.disconnect();
        else if (d.paired) d.connect();
        else d.pair();
    }

    // поиск — только пока меню открыто
    Binding {
        when: root.adapter !== null && root.on && !root.visible
        target: root.adapter
        property: "discovering"
        value: false
        restoreMode: Binding.RestoreNone
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 8

        MenuTitle {
            text: "Bluetooth"
            Toggle {
                visible: root.adapter !== null
                enabled: root.adapter?.state !== BluetoothAdapterState.Blocked
                checked: root.on
                onToggled: v => root.adapter.enabled = v
            }
        }

        MenuRow {
            visible: root.adapter === null
            clickable: false
            icon: "bluetooth"
            iconColor: Theme.fg3
            title: I18n.tr("Bluetooth недоступен")
            subtitle: I18n.tr("Нет адаптера или службы bluetooth")
        }
        MenuRow {
            visible: root.adapter !== null && !root.on
            clickable: false
            icon: "bluetooth"
            iconColor: Theme.fg3
            title: root.adapter?.state === BluetoothAdapterState.Blocked ? "Заблокирован (rfkill)" : "Выключен"
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 300)
            visible: root.on && count > 0
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: root.devices

            delegate: MenuRow {
                id: dev
                required property BluetoothDevice modelData
                width: list.width
                active: modelData.connected
                icon: modelData.icon || "bluetooth"
                iconColor: modelData.connected ? Theme.accent : Theme.fg2
                title: modelData.name || modelData.address
                subtitle: root.status(modelData)
                onClicked: root.toggle(modelData)
                Sym { visible: dev.modelData.connected; name: "check"; size: 18; color: Theme.accent }
            }
        }

        MenuRow {
            visible: root.on && list.count === 0
            clickable: false
            title: root.adapter?.discovering ? "Поиск устройств…" : "Нет известных устройств"
            subtitle: root.adapter?.discovering ? "" : "Нажмите «Искать», чтобы найти новые"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Btn {
                kind: "ghost"
                icon: "settings"
                text: I18n.tr("Настройки…")
                implicitHeight: 32
                onClicked: { ShellState.openSettings("bluetooth", null); root.close(); }
            }
            Item { Layout.fillWidth: true }
            Btn {
                visible: root.on
                implicitHeight: 32
                icon: "search"
                text: root.adapter?.discovering ? "Остановить" : "Искать"
                active: root.adapter?.discovering ?? false
                onClicked: root.adapter.discovering = !root.adapter.discovering
            }
        }
    }
}
