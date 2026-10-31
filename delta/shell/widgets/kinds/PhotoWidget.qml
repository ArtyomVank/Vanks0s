pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.common
import qs.common.ui
import qs.widgets.parts

// Фото: одно или несколько своих фотографий на всю карточку. Несколько —
// сменяются по очереди с плавным переходом (item.mode: «Медленно» — раз в
// минуту, «Быстро» — раз в 10 с). Выбор — PhotoPicker (zenity); фото
// копируются в ~/.local/share/delta/photos, чтобы виджет не пустел, если
// оригинал удалили или флешку вынули. Список — item.photos.
Base {
    id: root

    readonly property var photos: (item && Array.isArray(item.photos)) ? item.photos.filter(p => typeof p === "string" && p) : []
    readonly property bool empty: false
    property int index: 0
    readonly property string current: photos.length ? photos[index % photos.length] : ""

    function url(p) { return p ? "file://" + p.split("/").map(encodeURIComponent).join("/") : ""; }

    // выбрать фото (zenity) — копии в ~/.local/share/delta/photos
    function pick() { if (root.card) picker.pick(); }
    PhotoPicker {
        id: picker
        onPicked: list => { root.card.grid.patch(root.item.id, { photos: list }); root.index = 0; }
    }

    Timer {
        interval: root.mode === "fast" ? 10000 : 60000
        repeat: true
        running: root.photos.length > 1 && root.visible
        onTriggered: root.index = (root.index + 1) % root.photos.length
    }

    // на всю карточку: отступов содержимого у фото нет (WidgetCard)
    ClippingRectangle {
        id: frame
        anchors.fill: parent
        radius: root.card ? root.card.radius : 20
        color: "transparent"

        // два слоя: новое фото проявляется поверх старого
        Image {
            id: back
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(Math.max(64, frame.width * 2), Math.max(64, frame.height * 2))
        }
        Image {
            id: front
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: back.sourceSize
            source: root.url(root.current)
            onStatusChanged: if (status === Image.Ready) fade.restart()
            NumberAnimation on opacity { id: fade; from: 0; to: 1; duration: 900 * Theme.anim.k; easing.type: Easing.InOutQuad; running: false
                onFinished: back.source = front.source }
        }

        // пусто — подсказка
        Column {
            anchors.centerIn: parent
            visible: root.photos.length === 0
            spacing: 6 * root.cm
            Sym { anchors.horizontalCenter: parent.horizontalCenter; name: "image"; size: Math.max(16, 22 * root.cm); color: root.pal.c2 }
            WText {
                anchors.horizontalCenter: parent.horizontalCenter
                width: frame.width * 0.8
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: root.editing ? I18n.tr("«Выбрать фото» — в панели редактора") : I18n.tr("Нажмите, чтобы выбрать фото")
                px: Math.max(11, 9 * root.cm)
                color: root.pal.c2
            }
        }

        TapHandler {
            enabled: !root.editing && root.photos.length === 0
            onTapped: root.pick()
        }
        HoverHandler { enabled: !root.editing && root.photos.length === 0; cursorShape: Qt.PointingHandCursor }
    }
}
