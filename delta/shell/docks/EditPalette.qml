pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.docks.parts

// Панель режима правки верхнего дока: какие модули ещё можно добавить,
// «Сбросить» и «Готово». Не перехватывает клавиатуру и нажатия мимо —
// модули в это время перетаскивают в самом доке.
PopupLayer {
    id: pop

    property var topDock: null
    readonly property bool wanted: ShellState.dockEditing && (DockService.editScreen === "" || DockService.editScreen === screen?.name)

    open: wanted
    grab: false
    keyboard: false
    onDismissed: ShellState.dockEditing = false
    edge: topDock?.edge ?? "top"
    reach: topDock?.reach ?? 58
    gap: 14
    anchorRect: ({ x: sw / 2, y: sh / 2, w: 0, h: 0 })
    cardW: Math.min(sw - 32, 720)
    cardH: box.implicitHeight + 36

    readonly property var missing: DockService.order.filter(id => !DockService.modules.some(m => m.id === id))

    ColumnLayout {
        id: box
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label { text: I18n.tr("Верхний док — сетка модулей"); size: "title"; Layout.fillWidth: true }
                Label {
                    text: I18n.tr("Перетащите модуль в другую ячейку — занятые меняются местами. Крестик убирает модуль.")
                    size: "small"; tone: 3; wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }
            Btn { text: I18n.tr("Сбросить"); onClicked: DockService.resetModules() }
            Btn { text: I18n.tr("Готово"); kind: "accent"; onClicked: ShellState.dockEditing = false }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: pop.missing
                delegate: Btn {
                    required property string modelData
                    icon: DockService.catalog[modelData].icon
                    text: DockService.catalog[modelData].name
                    iconSize: 16
                    implicitHeight: 32
                    onClicked: DockService.addModule(modelData)
                }
            }
            Label {
                visible: pop.missing.length === 0
                text: I18n.tr("Все модули уже в доке")
                size: "small"
                tone: 3
            }
        }
    }
}
