pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.common
import qs.common.ui

// Окно выбора экрана или окна для демонстрации (Discord, OBS, браузеры).
// Ответ — строка для xdg-desktop-portal-hyprland: «screen:DP-1» или «window:<id>»
// в файл DELTA_SHARE_OUT; закрыли без выбора — файл пустой, портал вернёт отмену.
FloatingWindow {
    id: win

    property string tab: "screens"      // screens · windows
    property string picked: ""          // что выбрано: screen:… или window:…
    // портал отдаёт программе ключ, и в следующий раз она не спрашивает
    property bool remember: Quickshell.env("DELTA_SHARE_TOKEN") === "1"

    // список окон от портала: id[HC>]класс[HT>]заголовок[HE>]адрес[HA>]…
    readonly property var windows: {
        const list = [];
        for (const row of (Quickshell.env("XDPH_WINDOW_SHARING_LIST") || "").split("[HA>]")) {
            const m = row.match(/^(\d+)\[HC>\](.*)\[HT>\](.*)\[HE>\]/);
            if (m) list.push({ id: m[1], cls: m[2], title: m[3] });
        }
        return list;
    }

    title: I18n.tr("Что показать?")
    implicitWidth: 760
    implicitHeight: 560
    minimumSize: Qt.size(560, 420)
    color: "transparent"

    onClosed: Qt.quit()

    Process {
        id: answer
        onExited: Qt.quit()
    }

    function share() {
        if (!picked || answer.running) return;
        answer.command = ["sh", "-c", 'printf "%s" "$1" > "$DELTA_SHARE_OUT"', "sh",
            (remember ? "r" : "") + "/" + picked];
        answer.running = true;
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.glass2
        border.width: 1
        border.color: Theme.line

        ColumnLayout {
            anchors { fill: parent; margins: 24 }
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: I18n.tr("Что показать?")
                    color: Theme.fg
                    font { family: Theme.fontDisplay; pixelSize: 22; weight: Font.DemiBold }
                    Layout.fillWidth: true
                }
                Repeater {
                    model: [{ id: "screens", name: I18n.tr("Экран") }, { id: "windows", name: I18n.tr("Окно") }]
                    Btn {
                        required property var modelData
                        text: modelData.name
                        kind: win.tab === modelData.id ? "accent" : "ghost"
                        onClicked: { win.tab = modelData.id; win.picked = ""; }
                    }
                }
            }

            // --- экраны: живая картинка ---
            GridLayout {
                visible: win.tab === "screens"
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: Quickshell.screens.length > 1 ? 2 : 1
                columnSpacing: 14
                rowSpacing: 14
                Repeater {
                    model: Quickshell.screens
                    Item {
                        id: cell
                        required property var modelData
                        readonly property string key: "screen:" + modelData.name
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 8
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 14
                                color: Qt.rgba(0, 0, 0, 0.25)
                                border.width: win.picked === cell.key ? 3 : 1
                                border.color: win.picked === cell.key ? Theme.accent : Theme.line
                                Behavior on border.color { ColorAnimation { duration: Theme.anim.fast } }
                                ScreencopyView {
                                    anchors { fill: parent; margins: 6 }
                                    captureSource: cell.modelData
                                    live: true
                                    constraintSize: Qt.size(width, height)
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: cell.modelData.name + " · " + cell.modelData.width + "×" + cell.modelData.height
                                color: Theme.fg2
                                elide: Text.ElideRight
                                font { family: Theme.font; pixelSize: 14 }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.picked = cell.key
                            onDoubleClicked: { win.picked = cell.key; win.share(); }
                        }
                    }
                }
            }

            // --- окна: список от портала ---
            ListView {
                visible: win.tab === "windows"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                model: win.windows
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property string key: "window:" + modelData.id
                    width: ListView.view.width
                    height: 56
                    radius: 14
                    color: win.picked === key ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22) : area.containsMouse ? Theme.line : "transparent"
                    RowLayout {
                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                        spacing: 12
                        Image {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            sourceSize: Qt.size(60, 60)
                            source: {
                                const e = DesktopEntries.heuristicLookup(row.modelData.cls);
                                return Quickshell.iconPath(e?.icon ?? "", "application-x-executable");
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.title || row.modelData.cls
                                color: Theme.fg
                                elide: Text.ElideRight
                                font { family: Theme.font; pixelSize: 15 }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.cls
                                color: Theme.fg3
                                elide: Text.ElideRight
                                font { family: Theme.font; pixelSize: 12 }
                            }
                        }
                    }
                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.picked = row.key
                        onDoubleClicked: { win.picked = row.key; win.share(); }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: win.windows.length === 0
                    text: I18n.tr("Нет окон, которые можно показать")
                    color: Theme.fg3
                    font { family: Theme.font; pixelSize: 15 }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    implicitWidth: 22; implicitHeight: 22; radius: 7
                    color: win.remember ? Theme.accent : "transparent"
                    border.width: win.remember ? 0 : 2
                    border.color: Theme.fg3
                    Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
                    Sym { anchors.centerIn: parent; name: "check"; size: 14; color: Theme.onAccent; visible: win.remember }
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: win.remember = !win.remember }
                }
                Text {
                    text: I18n.tr("Запомнить выбор")
                    color: Theme.fg2
                    font { family: Theme.font; pixelSize: 14 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.remember = !win.remember }
                }
                Item { Layout.fillWidth: true }
                Btn { text: I18n.tr("Отмена"); kind: "ghost"; onClicked: Qt.quit() }
                Btn { text: I18n.tr("Показать"); kind: "accent"; enabled: win.picked !== ""; onClicked: win.share() }
            }
        }
    }

    Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
    Shortcut { sequences: ["Return", "Enter"]; onActivated: win.share() }
}
