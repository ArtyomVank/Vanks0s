pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui

// Шаг 3: стиль интерфейса (Theme.uiStyles: Delta, «Акрил») и тема — материал
// панелей (Theme.styles: Delta, акриловое и жидкое стекло, GNOME…).
// Применяется сразу; поменять можно в «Настройки → Стили и темы».
Page {
    id: root

    icon: "layers"
    title: I18n.tr("Стиль и тема")
    subtitle: I18n.tr("Стиль — как устроен интерфейс, тема — из чего сделаны панели. Цвета остаются вашими.")

    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        GridLayout {
            Layout.fillWidth: true
            columns: 6
            columnSpacing: 14
            rowSpacing: 14
            // сверху два стиля (по три колонки), ниже шесть тем
            Repeater {
                model: Theme.uiStyles.map(u => ({ kind: "style", id: u.id })).concat(Theme.styles.map(t => ({ kind: "theme", id: t.id })))
                delegate: StyleCard {
                    id: card
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.columnSpan: modelData.kind === "style" ? 3 : 1
                    implicitHeight: modelData.kind === "style" ? 200 : 150
                    kind: modelData.kind
                    styleId: modelData.id
                    onClicked: {
                        if (kind === "style") Theme.applyUi(styleId); else Theme.applyStyle(styleId);
                        Sounds.play("oobe-select", 60);
                    }
                    // плитки въезжают по очереди, когда шаг открывается
                    opacity: 0
                    transform: Translate { id: shift; y: 0 }
                    Connections {
                        target: root
                        function onShownChanged() {
                            if (!root.shown) return;
                            card.opacity = 0;
                            shift.y = 30;
                            enter.restart();
                        }
                    }
                    SequentialAnimation {
                        id: enter
                        PauseAnimation { duration: (260 + card.index * 110) * Theme.anim.k }
                        ParallelAnimation {
                            NumberAnimation { target: card; property: "opacity"; to: 1; duration: 360; easing.type: Easing.OutCubic }
                            NumberAnimation { target: shift; property: "y"; to: 0; duration: 620; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                        }
                    }
                }
            }
        }
        Item { Layout.fillHeight: true }
    }
}
