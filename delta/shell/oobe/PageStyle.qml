pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui

// Шаг 3: стиль панелей — Delta (тонированное стекло), GNOME (сплошные,
// без прозрачности) или «Жидкое стекло». Применяется сразу; поменять можно
// в «Настройки → Оформление → Стиль».
Page {
    id: root

    icon: "layers"
    title: I18n.tr("Стиль")
    subtitle: I18n.tr("Как выглядят доки, меню и окна. Цвета остаются вашими.")

    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            Repeater {
                model: Theme.styles
                delegate: StyleCard {
                    id: card
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: 230
                    styleId: modelData.id
                    onClicked: { Theme.applyStyle(styleId); Sounds.play("oobe-select", 60); }
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
                        PauseAnimation { duration: 260 + card.index * 110 }
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
