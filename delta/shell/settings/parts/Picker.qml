pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.settings

// Диалог выбора из длинного списка с поиском (часовые пояса, раскладки,
// локали, шрифты, приложения).
//     Picker { id: p; title: "Часовой пояс"; model: [{ value, label, sub, icon }]
//              current: tz; onPicked: v => set(v) }
Dialog {
    id: root

    property var model: []
    property var current
    property string searchHint: "Поиск"
    property string emptyText: "Ничего не найдено"
    signal picked(var value)

    property string query: ""
    readonly property var shownModel: {
        const q = Registry.norm(query).trim();
        if (!q.length) return model;
        const words = q.split(/\s+/);
        return model.filter(m => {
            const hay = Registry.norm((m.label || "") + " " + (m.sub || "") + " " + m.value + " " + (m.keywords || ""));
            return words.every(w => hay.indexOf(w) !== -1);
        });
    }

    function openWith(q) {
        query = q || "";
        search.text = query;
        open();
        search.focusInput();
        const i = model.findIndex(m => m.value === current);
        list.positionViewAtIndex(Math.max(0, i), ListView.Center);
    }

    cardWidth: 480

    Field {
        id: search
        Layout.fillWidth: true
        icon: "search"
        placeholder: root.searchHint
        clearable: true
        onEdited: root.query = text
        onAccepted: if (root.shownModel.length) { root.picked(root.shownModel[0].value); root.close(); }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 340
        radius: Theme.radius - 6
        color: Theme.soft
        border.color: Theme.line
        clip: true

        ListView {
            id: list
            anchors { fill: parent; margins: 4 }
            model: root.shownModel
            boundsBehavior: Flickable.StopAtBounds
            spacing: 2
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool sel: modelData.value === root.current
                width: ListView.view.width
                height: modelData.sub ? 48 : 38
                radius: 10
                color: sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28)
                     : hov.hovered ? Theme.soft2 : "transparent"

                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    spacing: 10
                    Sym { visible: (row.modelData.icon || "").length > 0; name: row.modelData.icon || ""; size: 22 }
                    ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true
                        Label { text: row.modelData.label; Layout.fillWidth: true; font.family: row.modelData.font || Theme.font }
                        Label { visible: !!row.modelData.sub; text: row.modelData.sub || ""; size: "caption"; tone: 3; Layout.fillWidth: true }
                    }
                    Sym { visible: row.sel; name: "check"; size: 16; color: Theme.accent }
                }
                HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.picked(row.modelData.value); root.close(); } }
            }
        }
        Label {
            anchors.centerIn: parent
            visible: root.shownModel.length === 0
            text: root.emptyText
            tone: 3
        }
    }

    buttons: [Btn { text: "Закрыть"; onClicked: root.close() }]
}
