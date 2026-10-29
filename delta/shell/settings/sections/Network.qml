pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import qs.common
import qs.common.ui

// Раздел «Сеть»: Wi‑Fi (список, подключение с паролем, сохранённые сети) и кабель.
ColumnLayout {
    id: root

    property string title: "Сеть"
    property string icon: "wifi"
    property string keywords: "wi-fi wifi интернет ethernet кабель пароль сохранённые сети"
    spacing: 18

    readonly property var devices: Networking.devices.values
    readonly property WifiDevice wifi: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wired: devices.filter(d => d.type === DeviceType.Wired)
    readonly property var networks: !wifi || !Networking.wifiEnabled ? [] : wifi.networks.values
        .filter(n => n.name && n.name.length)
        .sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength))
    readonly property var saved: networks.filter(n => n.known)

    // пока раздел открыт — ищем сети
    Binding {
        when: root.wifi !== null && root.visible && Networking.wifiEnabled
        target: root.wifi
        property: "scannerEnabled"
        value: true
        restoreMode: Binding.RestoreBindingOrValue
    }

    function strength(n) {
        const s = n.signalStrength > 1 ? n.signalStrength / 100 : n.signalStrength;
        return s > 0.75 ? "wifi" : s > 0.5 ? "wifi-3" : s > 0.25 ? "wifi-2" : "wifi-1";
    }
    function secured(n) { return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe; }
    function percent(n) { return Math.round(n.signalStrength > 1 ? n.signalStrength : n.signalStrength * 100); }
    readonly property string connectivity: {
        switch (Networking.connectivity) {
        case NetworkConnectivity.Full: return "Есть доступ к интернету";
        case NetworkConnectivity.Limited: return "Ограниченный доступ";
        case NetworkConnectivity.Portal: return "Нужен вход на странице сети";
        case NetworkConnectivity.None: return "Нет доступа к интернету";
        }
        return "Неизвестно";
    }

    property string asking: ""      // сеть, для которой вводят пароль
    property string error: ""

    Card {
        title: "Состояние"
        SettingRow {
            icon: Networking.connectivity === NetworkConnectivity.Full ? "globe" : "warning"
            title: Networking.backend === NetworkBackendType.None ? "NetworkManager не запущен" : root.connectivity
            subtitle: Networking.backend === NetworkBackendType.None ? "Управлять сетью отсюда не получится" : ""
        }
    }

    Card {
        title: "Wi‑Fi"
        SettingRow {
            icon: Networking.wifiEnabled ? "wifi" : "wifi-off"
            title: "Wi‑Fi"
            subtitle: root.wifi === null ? "Адаптер не найден"
                : !Networking.wifiHardwareEnabled ? "Выключен кнопкой или в BIOS"
                : root.wifi.name
            Toggle {
                visible: root.wifi !== null
                enabled: Networking.wifiHardwareEnabled
                checked: Networking.wifiEnabled
                onToggled: v => Networking.wifiEnabled = v
            }
        }
        SettingRow {
            visible: root.wifi !== null && Networking.wifiEnabled && root.networks.length === 0
            title: "Поиск сетей…"
        }
        Repeater {
            model: root.networks
            delegate: SettingRow {
                id: net
                required property WifiNetwork modelData
                readonly property bool ask: root.asking === modelData.name
                icon: root.strength(modelData)
                title: modelData.name
                subtitle: [modelData.connected ? "Подключено" : modelData.state === ConnectionState.Connecting ? "Подключение…" : modelData.known ? "Сохранена" : "",
                           root.secured(modelData) ? "защищена" : "открытая", root.percent(modelData) + "%"].filter(s => s).join(" · ")
                    + (net.ask && root.error ? " — " + root.error : "")
                wide: net.ask

                Connections {
                    target: net.modelData
                    function onConnectionFailed(reason) {
                        root.asking = net.modelData.name;
                        root.error = reason === ConnectionFailReason.NoSecrets ? "неверный пароль" : "не удалось подключиться";
                    }
                    function onConnectedChanged() { if (net.modelData.connected && root.asking === net.modelData.name) root.asking = ""; }
                }

                RowLayout {
                    spacing: 8
                    // ввод пароля — прямо в строке
                    Rectangle {
                        visible: net.ask
                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: 10
                        color: Theme.soft2
                        border.width: 1
                        border.color: psk.activeFocus ? Theme.accent : Theme.line
                        TextInput {
                            id: psk
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: 14
                            echoMode: TextInput.Password
                            passwordCharacter: "•"
                            clip: true
                            onAccepted: if (text.length >= 8) net.modelData.connectWithPsk(text)
                            Label { anchors.fill: parent; visible: psk.text.length === 0; text: "Пароль сети"; tone: 3 }
                        }
                    }
                    Btn {
                        visible: net.ask
                        text: "Подключить"; kind: "accent"
                        enabled: psk.text.length >= 8
                        onClicked: { root.error = ""; net.modelData.connectWithPsk(psk.text); }
                    }
                    Btn {
                        visible: net.ask
                        text: "Отмена"; kind: "ghost"
                        onClicked: { root.asking = ""; root.error = ""; }
                    }
                    Btn {
                        visible: !net.ask
                        text: net.modelData.connected ? "Отключить" : "Подключить"
                        kind: net.modelData.connected ? "soft" : "accent"
                        enabled: !net.modelData.stateChanging
                        onClicked: {
                            root.error = "";
                            if (net.modelData.connected) net.modelData.disconnect();
                            else if (net.modelData.known || !root.secured(net.modelData)) net.modelData.connect();
                            else { root.asking = net.modelData.name; psk.text = ""; psk.forceActiveFocus(); }
                        }
                    }
                }
            }
        }
    }

    Card {
        title: "Сохранённые сети"
        visible: root.wifi !== null
        SettingRow {
            visible: root.saved.length === 0
            title: "Рядом нет сохранённых сетей"
            subtitle: "Здесь видны сохранённые сети, которые сейчас в зоне действия"
        }
        Repeater {
            model: root.saved
            delegate: SettingRow {
                id: sv
                required property WifiNetwork modelData
                icon: "lock"
                title: modelData.name
                subtitle: modelData.connected ? "Подключено" : "Подключаться автоматически"
                Btn { text: "Забыть"; kind: "danger"; onClicked: sv.modelData.forget() }
            }
        }
    }

    Card {
        title: "Кабель"
        visible: root.wired.length > 0
        Repeater {
            model: root.wired
            delegate: SettingRow {
                id: w
                required property WiredDevice modelData
                icon: "ethernet"
                title: modelData.name
                subtitle: !modelData.hasLink ? "Кабель не подключён"
                    : (modelData.connected ? "Подключено" : "Не подключено")
                      + (modelData.linkSpeed > 0 ? " · " + (modelData.linkSpeed >= 1000 ? modelData.linkSpeed / 1000 + " Гбит/с" : modelData.linkSpeed + " Мбит/с") : "")
                      + (modelData.address ? " · " + modelData.address : "")
                Btn {
                    visible: w.modelData.connected
                    text: "Отключить"
                    onClicked: w.modelData.disconnect()
                }
            }
        }
    }
}
