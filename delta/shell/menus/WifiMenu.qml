pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import qs.common
import qs.common.ui
import qs.launcher.parts

// Меню сети: Wi‑Fi вкл/выкл, список сетей с уровнем сигнала и замком,
// подключение с вводом пароля, кабель, ссылка на «Настройки».
Item {
    id: root

    implicitWidth: 320
    implicitHeight: col.implicitHeight
    signal close()

    readonly property var devices: Networking.devices.values
    readonly property WifiDevice wifi: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wired: devices.filter(d => d.type === DeviceType.Wired)

    // пока меню открыто, просим NetworkManager искать сети
    Binding {
        when: root.wifi !== null && root.visible && Networking.wifiEnabled
        target: root.wifi
        property: "scannerEnabled"
        value: true
        restoreMode: Binding.RestoreBindingOrValue
    }

    readonly property var networks: {
        if (!wifi || !Networking.wifiEnabled) return [];
        return wifi.networks.values
            .filter(n => n.name && n.name.length)
            .sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength));
    }

    function strength(n) {
        const s = n.signalStrength > 1 ? n.signalStrength / 100 : n.signalStrength;
        return s > 0.75 ? "wifi" : s > 0.5 ? "wifi-3" : s > 0.25 ? "wifi-2" : "wifi-1";
    }
    function secured(n) {
        return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe;
    }
    function status(n) {
        if (n.state === ConnectionState.Connecting) return "Подключение…";
        if (n.state === ConnectionState.Disconnecting) return "Отключение…";
        if (n.connected) return "Подключено";
        if (n.known) return "Сохранена";
        return "";
    }

    // сеть, под которой раскрыта строка: пароль или «Отключить»
    property string expanded: ""
    property string error: ""

    function activate(n) {
        error = "";
        if (n.connected) { expanded = expanded === n.name ? "" : n.name; return; }
        if (n.known || !secured(n)) { expanded = ""; n.connect(); return; }
        expanded = n.name;
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 8

        MenuTitle {
            text: "Сеть"
            Toggle {
                visible: root.wifi !== null
                enabled: Networking.wifiHardwareEnabled
                checked: Networking.wifiEnabled
                onToggled: v => Networking.wifiEnabled = v
            }
        }

        // кабель
        Repeater {
            model: root.wired
            delegate: MenuRow {
                id: wire
                required property var modelData
                clickable: false
                icon: "ethernet"
                iconColor: modelData.connected ? Theme.accent : Theme.fg3
                title: "Кабель"
                subtitle: (modelData.connected ? "Подключено" : "Не подключено") + " · " + modelData.name
                Sym { visible: wire.modelData.connected; name: "check"; size: 18; color: Theme.accent }
            }
        }

        MenuRow {
            visible: Networking.backend === NetworkBackendType.None
            clickable: false
            icon: "warning"
            title: "NetworkManager не запущен"
            subtitle: "Списка сетей не будет"
        }
        MenuRow {
            visible: Networking.backend !== NetworkBackendType.None && root.wifi === null
            clickable: false
            icon: "wifi-off"
            title: "Wi‑Fi-адаптер не найден"
        }
        MenuRow {
            visible: root.wifi !== null && !Networking.wifiEnabled
            clickable: false
            icon: "wifi-off"
            title: Networking.wifiHardwareEnabled ? "Wi‑Fi выключен" : "Wi‑Fi выключен кнопкой или в BIOS"
        }
        Label {
            visible: root.wifi !== null && Networking.wifiEnabled && root.networks.length === 0
            text: "Поиск сетей…"
            tone: 3
            size: "small"
            Layout.leftMargin: 4
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 330)
            visible: root.networks.length > 0
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: root.networks

            delegate: ColumnLayout {
                id: item
                required property WifiNetwork modelData
                readonly property bool open: root.expanded === modelData.name
                width: list.width
                spacing: 6

                MenuRow {
                    active: item.modelData.connected
                    icon: root.strength(item.modelData)
                    iconColor: item.modelData.connected ? Theme.accent : Theme.fg2
                    title: item.modelData.name
                    subtitle: root.status(item.modelData)
                    onClicked: root.activate(item.modelData)
                    Sym { visible: root.secured(item.modelData); name: "lock"; size: 15; color: Theme.fg3 }
                    Sym { visible: item.modelData.connected; name: "check"; size: 18; color: Theme.accent }
                }

                // ввод пароля
                RowLayout {
                    visible: item.open && !item.modelData.connected
                    spacing: 6
                    Layout.fillWidth: true
                    Field {
                        id: psk
                        Layout.fillWidth: true
                        height: 36
                        icon: "lock"
                        password: !showPsk.active
                        placeholder: "Пароль"
                        fontSize: 13
                        onAccepted: if (text.length >= 8) { root.error = ""; item.modelData.connectWithPsk(text); }
                        onKey: e => { if (e.key === Qt.Key_Escape) { root.expanded = ""; e.accepted = true; } }
                        onVisibleChanged: if (visible) { text = ""; focusInput(); }
                    }
                    Btn { id: showPsk; icon: psk.password ? "eye" : "eye-off"; iconSize: 16; onClicked: active = !active }
                    Btn {
                        text: "Подключить"
                        kind: "accent"
                        enabled: psk.text.length >= 8
                        onClicked: { root.error = ""; item.modelData.connectWithPsk(psk.text); }
                    }
                }
                RowLayout {
                    visible: item.open && item.modelData.connected
                    Layout.fillWidth: true
                    spacing: 6
                    Item { Layout.fillWidth: true }
                    Btn { visible: item.modelData.known; text: "Забыть"; kind: "ghost"; onClicked: { root.expanded = ""; item.modelData.forget(); } }
                    Btn { text: "Отключить"; onClicked: { root.expanded = ""; item.modelData.disconnect(); } }
                }

                Connections {
                    target: item.modelData
                    function onConnectionFailed(reason) {
                        root.expanded = item.modelData.name;
                        root.error = reason === ConnectionFailReason.NoSecrets ? "Неверный пароль"
                            : reason === ConnectionFailReason.WifiAuthTimeout ? "Сеть не ответила"
                            : "Не удалось подключиться";
                    }
                    function onConnectedChanged() { if (item.modelData.connected) { root.error = ""; root.expanded = ""; } }
                }
                Label {
                    visible: item.open && root.error.length > 0
                    text: root.error
                    size: "small"
                    color: "#ff6b6b"
                    Layout.leftMargin: 4
                }
            }
        }

        Btn {
            Layout.alignment: Qt.AlignLeft
            Layout.topMargin: 2
            kind: "ghost"
            icon: "settings"
            text: "Настройки сети…"
            implicitHeight: 32
            onClicked: { ShellState.openSettings("network", null); root.close(); }
        }
    }
}
