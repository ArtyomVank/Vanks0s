pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.lock.parts

// Содержимое меню питания — общее для выпадающего меню дока (menus/PowerMenu.qml)
// и окна по центру (Super+Escape, PowerOverlay.qml). Как в концепте:
// аккаунт, «Уведомления» с последними сообщениями, сетка кнопок 3×2.
// Перезагрузка, выключение и выход — с подтверждением.
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
            delegate: Rectangle {
                id: pw
                required property string modelData
                readonly property bool danger: modelData === "poweroff"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 70
                radius: 14
                color: hover.hovered ? Theme.soft2 : Theme.soft
                scale: tap.pressed ? 0.95 : 1
                Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
                Behavior on scale { NumberAnimation { duration: Theme.anim.fast } }

                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    Sym {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: pw.modelData === "suspend" ? "sleep" : pw.modelData === "reboot" ? "restart"
                            : pw.modelData === "poweroff" ? "power" : pw.modelData
                        size: 22
                        color: pw.danger ? "#ff6b6b" : Theme.fg
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: PowerActions.labels[pw.modelData]
                        size: "caption"
                        font.weight: Font.DemiBold
                        color: pw.danger ? "#ff6b6b" : Theme.fg
                    }
                }
                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    id: tap
                    onTapped: {
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
            logout: ["Выйти из системы?", "Все программы будут закрыты."],
            reboot: ["Перезагрузить компьютер?", "Несохранённые данные в программах пропадут."],
            poweroff: ["Выключить компьютер?", "Несохранённые данные в программах пропадут."]
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
                    text: PowerActions.labels[root.confirm] || ""
                    kind: root.confirm === "poweroff" ? "danger" : "accent"
                    onClicked: root.run(root.confirm)
                }
            }
        }
    }

    Component.onCompleted: { Account.refresh(); PowerActions.refresh(); }
}
