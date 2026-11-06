pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common
import qs.common.ui
import qs.launcher.parts
import qs.services

// Меню программы Windows из трея (services/WinApps.qml): показать окно,
// закрыть, завершить процессы, открыть папку, настройки запуска (delta-exe).
// Какую программу показать — WinApps.menuApp (его ставит TrayModule).
Item {
    id: root

    implicitWidth: 300
    implicitHeight: col.implicitHeight
    signal close()

    // программа могла закрыться, пока меню открыто, — берём свежую запись;
    // открыто не из трея (delta-shell ipc call docks menu winapp) — первая
    readonly property var app: {
        const m = WinApps.menuApp ?? WinApps.apps[0];
        return m ? (WinApps.apps.find(a => a.key === m.key) ?? null) : null;
    }
    property bool confirmKill: false

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 6

        // шапка: значок, название, сколько процессов
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            spacing: 10
            Rectangle {
                implicitWidth: 40
                implicitHeight: 40
                radius: Theme.round ? 20 : 11
                color: Theme.soft
                Image {
                    anchors.centerIn: parent
                    visible: (root.app?.icon ?? "") !== ""
                    source: root.app?.icon ?? ""
                    sourceSize: Qt.size(26, 26)
                    width: 26
                    height: 26
                }
                Sym { anchors.centerIn: parent; visible: (root.app?.icon ?? "") === ""; name: "windows"; size: 20; color: Theme.fg2 }
            }
            ColumnLayout {
                spacing: 1
                Layout.fillWidth: true
                Label { text: root.app ? root.app.name : I18n.tr("Программа закрыта"); font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                Label {
                    text: root.app ? I18n.tr("Программа Windows") + " · " + root.app.exe : I18n.tr("Её больше нет среди запущенных")
                    size: "caption"; tone: 3; elide: Text.ElideMiddle; Layout.fillWidth: true
                }
            }
        }

        MenuRow {
            enabled: root.app !== null
            icon: "maximize"
            title: I18n.tr("Показать окно")
            onClicked: { WinApps.focus(root.app); root.close(); }
        }
        MenuRow {
            enabled: root.app !== null
            icon: "close"
            title: I18n.tr("Закрыть окно")
            subtitle: I18n.tr("Программа может спросить о сохранении")
            onClicked: { WinApps.close(root.app); root.close(); }
        }
        MenuRow {
            enabled: root.app !== null
            icon: "power"
            iconColor: root.confirmKill ? "#e5484d" : Theme.fg2
            active: root.confirmKill
            title: root.confirmKill ? I18n.tr("Точно завершить?") : I18n.tr("Завершить")
            subtitle: root.confirmKill ? I18n.tr("Несохранённое пропадёт. Нажмите ещё раз")
                : (root.app ? I18n.tr("Процессов: ") + root.app.pids.length : "")
            onClicked: {
                if (!root.confirmKill) { root.confirmKill = true; return; }
                WinApps.kill(root.app);
                root.close();
            }
        }
        MenuRow {
            enabled: root.app !== null && (root.app.path ?? "") !== ""
            icon: "folder"
            title: I18n.tr("Открыть папку программы")
            onClicked: { WinApps.openFolder(root.app); root.close(); }
        }
        Btn {
            Layout.alignment: Qt.AlignLeft
            kind: "ghost"
            icon: "settings"
            text: I18n.tr("Программы Windows…")
            implicitHeight: 32
            onClicked: { Quickshell.execDetached(["delta-exe", "--manager"]); root.close(); }
        }
    }
}
