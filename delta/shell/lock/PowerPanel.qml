pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.common
import qs.common.ui
import qs.lock.parts
import qs.services

// Содержимое меню питания — общее для выпадающего меню дока (menus/PowerMenu.qml)
// и окна по центру (Super+Escape, PowerOverlay.qml). Как в концепте:
// аккаунт, «Уведомления» с последними сообщениями, VPN (если он есть в
// NetworkManager или поднят программой), сетка кнопок 3×2.
// Перезагрузку и выключение нужно зажать и держать, выход — с подтверждением.
ColumnLayout {
    id: root

    signal close()

    spacing: 14

    // «Не беспокоить» живёт в notifications.dnd; ShellState.dnd — для модулей, которые уже запущены
    readonly property bool notifOn: !Settings.get("notifications.dnd", ShellState.dnd)
    readonly property var recent: (ShellState.notifications || []).slice(0, 3)
    property string confirm: ""

    function run(action) {
        root.close();
        PowerActions.run(action);
    }

    // значок с подписью на плитке
    component Face: Column {
        property string glyph
        property string text
        property color tint
        spacing: 6
        Sym { anchors.horizontalCenter: parent.horizontalCenter; name: parent.glyph; size: 22; color: parent.tint }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: parent.text
            size: "caption"
            font.weight: Font.DemiBold
            color: parent.tint
        }
    }

    // ---------- аккаунт ----------
    RowLayout {
        spacing: 12
        Avatar {
            size: 52
            source: Account.avatar
            name: Account.name
            revision: Account.revision
        }
        ColumnLayout {
            spacing: 2
            Layout.fillWidth: true
            Label { text: Account.name; size: "title"; font.weight: Font.ExtraBold; Layout.fillWidth: true }
            Label {
                text: Account.admin ? "Учётная запись администратора" : "Обычная учётная запись"
                size: "small"; tone: 3; Layout.fillWidth: true
            }
        }
    }

    // ---------- уведомления ----------
    ColumnLayout {
        spacing: 8
        Layout.fillWidth: true
        RowLayout {
            Layout.fillWidth: true
            Label { text: I18n.tr("Уведомления"); size: "small"; font.weight: Font.ExtraBold; Layout.fillWidth: true }
            Toggle {
                checked: root.notifOn
                onToggled: v => {
                    Settings.set("notifications.dnd", !v);
                    ShellState.dnd = !v;
                }
            }
        }
        Repeater {
            model: root.notifOn ? root.recent : []
            delegate: Rectangle {
                id: n
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: nCol.implicitHeight + 18
                radius: 12
                color: Theme.soft
                Rectangle {
                    x: 12; y: 14
                    width: 8; height: 8; radius: 4
                    color: Theme.accent
                }
                ColumnLayout {
                    id: nCol
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 28; rightMargin: 12 }
                    spacing: 1
                    Label { text: n.modelData.summary || n.modelData.app || ""; size: "small"; font.weight: Font.Bold; Layout.fillWidth: true }
                    Label {
                        visible: text.length > 0
                        text: String(n.modelData.body || "").replace(/<[^>]*>/g, "")
                        textFormat: Text.PlainText
                        size: "small"; tone: 3; Layout.fillWidth: true
                    }
                }
            }
        }
        Rectangle {
            visible: !root.notifOn || root.recent.length === 0
            Layout.fillWidth: true
            implicitHeight: 44
            radius: 12
            color: Theme.soft
            Label {
                anchors.centerIn: parent
                width: parent.width - 24
                horizontalAlignment: Text.AlignHCenter
                text: root.notifOn ? "Новых уведомлений нет" : "Уведомления выключены — шарики не появляются"
                size: "small"; tone: 3
            }
        }
    }

    // ---------- VPN ----------
    Binding { target: Vpn; property: "watch"; value: root.visible; when: root.visible; restoreMode: Binding.RestoreValue }
    Repeater {
        model: Vpn.connections
        delegate: Rectangle {
            id: vr
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: 52
            radius: 12
            color: Theme.soft
            RowLayout {
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                spacing: 10
                Sym { name: "vpn"; size: 20; color: vr.modelData.active ? Theme.accent : Theme.fg2 }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    Label { Layout.fillWidth: true; text: vr.modelData.name; size: "small"; font.weight: Font.Bold }
                    Label {
                        Layout.fillWidth: true
                        text: !vr.modelData.own ? I18n.tr("Включён в своей программе")
                            : Vpn.busy === vr.modelData.uuid ? I18n.tr("Подключение…")
                            : vr.modelData.active ? I18n.tr("Подключено") : I18n.tr("Отключено")
                        size: "caption"; tone: 3
                    }
                }
                Toggle {
                    visible: vr.modelData.own
                    checked: vr.modelData.active
                    enabled: Vpn.busy === ""
                    onToggled: Vpn.toggle(vr.modelData.uuid)
                }
            }
        }
    }

    // ---------- кнопки ----------
    GridLayout {
        id: grid
        visible: root.confirm === ""
        columns: 3
        rowSpacing: 8
        columnSpacing: 8
        Layout.fillWidth: true

        Repeater {
            model: ["lock", "logout", "suspend", "hibernate", "reboot", "poweroff"]
                .filter(a => a !== "hibernate" || PowerActions.canHibernate)
            delegate: ClippingRectangle {
                id: pw
                required property string modelData
                readonly property bool danger: modelData === "poweroff"
                readonly property bool hold: PowerActions.needsHold(modelData)
                readonly property color tint: danger ? "#ff6b6b" : Theme.fg
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 70
                radius: 14
                color: hover.hovered ? Theme.soft2 : Theme.soft
                scale: (tap.pressed ? 0.95 : 1) + charge.level * 0.04
                Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
                Behavior on scale { NumberAnimation { duration: Theme.anim.fast } }

                // перезагрузку и выключение нужно зажать: снизу поднимается жидкость
                HoldCharge {
                    id: charge
                    holdTime: 1200
                    onCompleted: { root.run(pw.modelData); refill.start(); }
                }
                Timer { id: refill; interval: 700; onTriggered: charge.reset() }
                Liquid {
                    id: liquid
                    anchors.fill: parent
                    level: charge.level
                    still: charge.done
                    color: pw.danger ? "#e5484d" : Theme.accent
                    waveHeight: 4
                }

                readonly property string glyph: modelData === "suspend" ? "sleep" : modelData === "reboot" ? "restart"
                    : modelData === "poweroff" ? "power" : modelData
                // пока держат — подсказка, что держать и надо
                readonly property string caption: hold && (charge.active || tap.pressed) ? I18n.tr("Удерживайте") : I18n.tr(PowerActions.labels[modelData])
                Face { id: face; anchors.centerIn: parent; glyph: pw.glyph; text: pw.caption; tint: pw.tint }
                // та же надпись под уровнем жидкости — белая
                Item {
                    y: Math.max(0, liquid.surface)
                    width: pw.width
                    height: Math.max(0, pw.height - y)
                    clip: true
                    visible: liquid.visible
                    Face { x: face.x; y: face.y - parent.y; glyph: pw.glyph; text: pw.caption; tint: pw.danger ? "#ffffff" : Theme.onAccent }
                }

                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    id: tap
                    onPressedChanged: if (pw.hold) { if (pressed) charge.begin(); else charge.cancel(); }
                    onTapped: {
                        if (pw.hold) return;
                        if (PowerActions.needsConfirm(pw.modelData)) root.confirm = pw.modelData;
                        else root.run(pw.modelData);
                    }
                }
            }
        }
    }

    // ---------- подтверждение ----------
    Rectangle {
        visible: root.confirm !== ""
        Layout.fillWidth: true
        implicitHeight: confirmCol.implicitHeight + 28
        radius: 14
        color: Theme.soft
        border.width: 1
        border.color: Theme.line

        readonly property var questions: ({
            logout: ["Выйти из системы?", "Все программы будут закрыты."]
        })
        readonly property var q: questions[root.confirm] || ["", ""]

        ColumnLayout {
            id: confirmCol
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
            spacing: 10
            Label { text: parent.parent.q[0]; size: "title"; Layout.fillWidth: true }
            Label { text: parent.parent.q[1]; size: "small"; tone: 3; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            RowLayout {
                spacing: 8
                Layout.alignment: Qt.AlignRight
                Btn { text: I18n.tr("Отмена"); onClicked: root.confirm = "" }
                Btn {
                    text: I18n.tr(PowerActions.labels[root.confirm] || "")
                    kind: "accent"
                    onClicked: root.run(root.confirm)
                }
            }
        }
    }

    Component.onCompleted: { Account.refresh(); PowerActions.refresh(); }
}
