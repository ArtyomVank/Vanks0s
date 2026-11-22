pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common
import qs.common.ui
import qs.settings.parts
import qs.wallpaper

// Раздел «Пресеты»: свои наборы обоев, часов и виджетов (до 5 штук) — каждый
// с миниатюрами стола и экрана блокировки — и готовые виды (wallpaper/Looks).
ColumnLayout {
    id: root

    property string title: I18n.tr("Пресеты")
    property string icon: "layers"
    property string keywords: "пресет набор сохранить обои часы виджеты готовые виды экран блокировки"
    spacing: 18

    Card {
        title: I18n.tr("Мои пресеты")
        subtitle: I18n.tr("Обои, часы и виджеты стола и экрана блокировки — как стоят сейчас")

        SettingRow {
            icon: "plus"
            title: I18n.tr("Сохранить текущий вид")
            subtitle: Looks.full ? I18n.tr("Сохранено 5 из 5 — удалите пресет, чтобы сохранить новый")
                                 : I18n.tr("Можно сохранить до 5 пресетов") + " · " + Looks.presets.length + " / " + Looks.max
            Btn { text: I18n.tr("Сохранить"); icon: "check"; kind: "accent"; enabled: !Looks.full; onClicked: Looks.save() }
        }
        Label {
            visible: Looks.presets.length === 0
            Layout.fillWidth: true
            Layout.margins: 14
            text: I18n.tr("Пока пусто: поставьте обои, часы и виджеты, как нравится, и нажмите «Сохранить»")
            size: "caption"
            tone: 3
            wrapMode: Text.WordWrap
        }
        Repeater {
            model: Looks.presets
            delegate: PresetItem {
                required property var modelData
                Layout.fillWidth: true
                preset: modelData
            }
        }
    }

    Card {
        title: I18n.tr("Готовые виды")
        subtitle: I18n.tr("Обои, часы и виджеты вместе — на столе и на экране блокировки")

        Item {
            Layout.fillWidth: true
            implicitHeight: looksRow.implicitHeight + 24
            RowLayout {
                id: looksRow
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 10
                Repeater {
                    model: Looks.list
                    delegate: LookTile {
                        required property var modelData
                        Layout.fillWidth: true
                        look: modelData
                    }
                }
            }
        }
        SettingRow {
            visible: Looks.saved !== null
            icon: "undo"
            title: I18n.tr("Вернуть как было")
            subtitle: I18n.tr("Обои, часы и виджеты, которые стояли до готового вида или пресета")
            Btn { text: I18n.tr("Вернуть"); kind: "soft"; onClicked: Looks.undo() }
        }
    }

    // пресет: имя, две миниатюры (стол и экран блокировки), под ними «Применить»
    component PresetItem: Item {
        id: pi
        property var preset
        readonly property bool sel: Looks.currentId === preset.id
        property bool asking: false
        implicitHeight: box.implicitHeight + 40

        Timer { id: askEnd; interval: 3000; onTriggered: pi.asking = false }

        Rectangle {
            anchors { fill: parent; leftMargin: 10; rightMargin: 10; topMargin: 4; bottomMargin: 12 }
            radius: 14
            color: Theme.soft
            border.width: pi.sel ? 2 : 1
            border.color: pi.sel ? Theme.accent : Theme.line
        }
        ColumnLayout {
            id: box
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 24; rightMargin: 24; topMargin: 14 }
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Label { text: Looks.nameOf(pi.preset, I18n.tr("Пресет")); font.weight: Font.Bold }
                Sym { visible: pi.sel; name: "check"; size: 14; color: Theme.accent }
                Label {
                    Layout.fillWidth: true
                    text: pi.preset.time ? Qt.formatDateTime(new Date(pi.preset.time), "d MMM, HH:mm") : ""
                    size: "caption"
                    tone: 3
                    elide: Text.ElideRight
                }
                // удаление — со второго нажатия, чтобы не стереть пресет случайно
                Btn {
                    text: pi.asking ? I18n.tr("Удалить?") : ""
                    icon: "trash"
                    kind: pi.asking ? "danger" : "ghost"
                    onClicked: {
                        if (!pi.asking) { pi.asking = true; askEnd.restart(); return; }
                        askEnd.stop();
                        Looks.remove(pi.preset.id);
                    }
                }
            }
            RowLayout {
                id: shots
                Layout.fillWidth: true
                spacing: 12
                readonly property real w: Math.min(320, (width - spacing) / 2)
                Repeater {
                    model: [false, true]
                    delegate: ColumnLayout {
                        id: shot
                        required property bool modelData
                        spacing: 5
                        Layout.preferredWidth: shots.w
                        ScenePreview {
                            Layout.preferredWidth: shots.w
                            Layout.preferredHeight: shots.w * 9 / 16
                            lock: shot.modelData
                            wall: shot.modelData ? Looks.lockWall(pi.preset) : Looks.deskWall(pi.preset)
                            items: (shot.modelData ? pi.preset.lock : pi.preset.desktop) || []
                            clock: shot.modelData ? Object.assign({}, pi.preset.clock || {}, pi.preset.lockClock || {}) : (pi.preset.clock || {})
                        }
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: shot.modelData ? I18n.tr("Экран блокировки") : I18n.tr("Главный экран")
                            size: "caption"
                            tone: 2
                        }
                    }
                }
                Item { Layout.fillWidth: true }
            }
            Btn {
                Layout.preferredWidth: shots.w * 2 + shots.spacing
                text: pi.sel ? I18n.tr("Применён") : I18n.tr("Применить")
                icon: pi.sel ? "check" : ""
                kind: pi.sel ? "soft" : "accent"
                onClicked: {
                    Looks.applyPreset(pi.preset);
                    if (Looks.isFlow(pi.preset)) Looks.introAtShell();
                }
            }
        }
    }

    // плитка готового вида: стол этого вида в миниатюре, название и пояснение
    component LookTile: Rectangle {
        id: lt
        property var look
        readonly property bool sel: Looks.currentId === look.id
        readonly property var wall: SuperWalls.flows.concat(SuperWalls.builtin).find(x => x.id === look.wall) || null
        implicitWidth: 180
        implicitHeight: scene.height + 86
        radius: 14
        color: hovL.hovered ? Theme.soft2 : Theme.soft
        border.width: 2
        border.color: sel ? Theme.accent : Theme.line
        scale: tapL.pressed ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: 140 * Theme.anim.k; easing.type: Easing.OutBack } }

        ScenePreview {
            id: scene
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 7 }
            height: width * 9 / 16
            wall: lt.wall ? SuperWalls.still(lt.wall) : ""
            items: Looks.withClock(lt.look.desktop, lt.look.clock)
            clock: lt.look.clock
        }
        Column {
            anchors { left: parent.left; right: parent.right; top: scene.bottom; topMargin: 7; leftMargin: 11; rightMargin: 9 }
            spacing: 1
            Row {
                spacing: 6
                Label { text: I18n.tr(lt.look.title); font.weight: Font.Bold }
                Sym { visible: lt.sel; anchors.verticalCenter: parent.verticalCenter; name: "check"; size: 14; color: Theme.accent }
            }
            Label { width: parent.width; text: I18n.tr(lt.look.note); size: "caption"; tone: 3; wrapMode: Text.WordWrap; maximumLineCount: 2 }
        }
        HoverHandler { id: hovL; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            id: tapL
            onTapped: {
                Looks.apply(lt.look);
                if (lt.wall && lt.wall.kind === "flow") Looks.introAtShell();
            }
        }
    }
}
