pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.launcher.parts
import qs.services

// Меню буфера обмена: щелчок по записи снова кладёт её в буфер. Настройки здесь же:
// сколько копирований хранить (до 2000) и очистка истории.
Item {
    id: root

    implicitWidth: 340
    implicitHeight: col.implicitHeight
    signal close()

    property bool settingsOpen: false

    function saveMax() {
        const n = parseInt(maxField.text);
        if (isFinite(n)) Clipboard.setMax(n);
        maxField.text = String(Clipboard.max);
    }
    function picture(text) {
        const m = /\s(\d+x\d+)\s\]\]$/.exec(text);
        return I18n.tr("Картинка") + (m ? " · " + m[1].replace("x", "×") : "");
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 10

        MenuTitle {
            text: root.settingsOpen ? I18n.tr("Настройки буфера") : I18n.tr("Буфер обмена") + (Clipboard.total > 0 ? " · " + Clipboard.total : "")
            Btn {
                icon: root.settingsOpen ? "check" : "settings"
                iconSize: 14
                implicitHeight: 28
                kind: "ghost"
                onClicked: {
                    if (root.settingsOpen) root.saveMax();
                    else maxField.text = String(Clipboard.max);
                    root.settingsOpen = !root.settingsOpen;
                }
            }
        }

        // --- список ---
        ListView {
            id: list
            visible: !root.settingsOpen && Clipboard.items.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 380)
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: Clipboard.items
            delegate: Rectangle {
                id: row
                required property var modelData
                width: list.width
                height: 38
                radius: 10
                color: rowHover.hovered ? Theme.soft2 : Qt.rgba(1, 1, 1, 0.04)
                Sym {
                    id: kindIcon
                    visible: row.modelData.image
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    name: "image"
                    size: 16
                    color: Theme.fg2
                }
                Label {
                    anchors {
                        left: kindIcon.visible ? kindIcon.right : parent.left; leftMargin: 10
                        right: del.visible ? del.left : parent.right; rightMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    text: row.modelData.image ? root.picture(row.modelData.text) : row.modelData.text
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        Clipboard.copy(row.modelData.id);
                        ShellState.island({ kind: "clipboard", icon: "check", color: "#30D158", ms: 1800, title: I18n.tr("Скопировано"),
                                            text: row.modelData.image ? root.picture(row.modelData.text) : row.modelData.text });
                        root.close();
                    }
                }
                Sym {
                    id: del
                    visible: rowHover.hovered
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    name: "close"
                    size: 14
                    color: Theme.fg2
                    TapHandler { onTapped: Clipboard.remove(row.modelData.id) }
                }
            }
        }
        Label {
            visible: !root.settingsOpen && Clipboard.items.length === 0
            Layout.fillWidth: true
            Layout.topMargin: 16
            Layout.bottomMargin: 16
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: I18n.tr("Здесь появится то, что вы копируете")
            tone: 3
        }

        // --- настройки ---
        Label {
            visible: root.settingsOpen
            Layout.fillWidth: true
            text: I18n.tr("Сколько копирований хранить (до 2000)")
            tone: 2
            wrapMode: Text.WordWrap
        }
        Field {
            id: maxField
            visible: root.settingsOpen
            Layout.fillWidth: true
            icon: "copy"
            placeholder: "200"
            clearable: false
            // больше 2000 не запрещаем набирать: при вводе число само станет 2000
            input.validator: RegularExpressionValidator { regularExpression: /[0-9]{0,4}/ }
            onAccepted: root.saveMax()
            onVisibleChanged: if (visible) focusInput()
        }
        Btn {
            visible: root.settingsOpen
            text: I18n.tr("Очистить историю")
            icon: "trash"
            kind: "ghost"
            onClicked: Clipboard.wipe()
        }
    }
}
