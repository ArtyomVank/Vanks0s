import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.common
import qs.common.ui
import qs.widgets
import qs.widgets.parts

// Ярлык приложения (id «app:<id .desktop>»): значок и подпись («С подписью»)
// или только значок. Нажатие открывает приложение — его ловит карточка
// (WidgetCard), здесь только отклик: пока держат — значок вдавливается,
// по щелчку — волна от центра и пружинка. Приложение удалили — значок
// «приложение» и id вместо названия.
Base {
    id: root

    readonly property string entryId: WidgetTypes.appEntry(item ? item.id : "")
    // DesktopEntries загружаются не сразу — ищем заново, когда список меняется.
    // Название и значок записываем при поиске, а не привязкой: entryId
    // вычисляется лениво, и его onChanged посреди такой привязки давал петлю
    // (подпись оставалась id).
    property var entry: null
    property string appTitle: ""
    property string entryIcon: ""
    function lookup() {
        const id = entryId;
        entry = id ? DesktopEntries.byId(id) : null;
        appTitle = entry && entry.name ? entry.name : id;
        entryIcon = entry ? (entry.icon || "") : "";
    }
    Component.onCompleted: lookup()
    onEntryIdChanged: lookup()
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { root.lookup(); }
    }

    readonly property bool named: mode !== "icon" && root.height > 46 * root.cm
    readonly property bool pressed: card ? card.pressing : false

    // щелчок: волна и пружинка
    function pulse() { ripple.restart(); bounce.restart(); }
    Connections {
        target: root.card
        ignoreUnknownSignals: true
        function onLaunched() { root.pulse(); }
    }

    Item {
        id: art
        readonly property real size: Math.min(root.width, root.height * (root.named ? 0.7 : 1)) * (root.named ? 0.82 : 0.86)
        width: size
        height: size
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.named ? (root.height - size - label.height - 4 * root.cm) / 2 : (root.height - size) / 2

        scale: root.pressed ? 0.86 : 1
        Behavior on scale { NumberAnimation { duration: 260 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }

        // волна под значком
        Rectangle {
            id: wave
            anchors.centerIn: parent
            width: parent.width
            height: width
            radius: width / 2
            color: Theme.accent
            opacity: 0
            scale: 0.6
        }
        ParallelAnimation {
            id: ripple
            NumberAnimation { target: wave; property: "scale"; from: 0.6; to: 1.5; duration: 520 * Theme.anim.k; easing.type: Easing.OutCubic }
            NumberAnimation { target: wave; property: "opacity"; from: 0.45; to: 0; duration: 520 * Theme.anim.k; easing.type: Easing.OutCubic }
        }

        Item {
            id: iconBox
            anchors.fill: parent
            transform: Scale { id: pop; origin.x: iconBox.width / 2; origin.y: iconBox.height / 2 }
            IconImage {
                id: icon
                anchors.fill: parent
                asynchronous: true
                source: root.entryIcon ? Quickshell.iconPath(root.entryIcon, "application-x-executable") : ""
                visible: status === Image.Ready
            }
            Rectangle {
                anchors.fill: parent
                visible: !icon.visible
                radius: width * 0.28
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                Sym { anchors.centerIn: parent; name: "apps"; size: Math.round(parent.width * 0.5); color: Theme.accent }
            }
        }
        SequentialAnimation {
            id: bounce
            NumberAnimation { target: pop; properties: "xScale,yScale"; to: 1.12; duration: 140 * Theme.anim.k; easing.type: Easing.OutQuad }
            NumberAnimation { target: pop; properties: "xScale,yScale"; to: 1; duration: 420 * Theme.anim.k; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
        }
    }

    WText {
        id: label
        visible: root.named
        anchors { top: art.bottom; topMargin: 4 * root.cm }
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.appTitle
        px: Math.max(11, 9 * root.cm)
        color: root.pal.c1
    }
}
