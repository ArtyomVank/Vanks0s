import QtQuick
import qs.common
import qs.common.ui
import qs.widgets
import qs.widgets.parts as WParts
import "../../wallpaper/media.js" as Media

// Миниатюра стола или экрана блокировки: обои, виджеты на своих местах и
// часы в своём виде. Нужна «Пресетам» (свои и готовые виды): показывает,
// как будет выглядеть, не трогая настоящий экран.
//     ScenePreview { wall: path; items: widgets.desktop; clock: Settings clock; lock: false }
// Сетка — как у WidgetGrid на экране 1600×900: клетка 80 px, 18 колонок,
// 9 рядов, поля слева 80 px и сверху 70 px.
Rectangle {
    id: root

    property string wall: ""
    property var items: []
    // часы по умолчанию (clock.* или lock.clock.*), у виджета часов — свои поля
    property var clock: ({})
    property bool lock: false

    readonly property real sx: width / 1600
    readonly property real sy: height / 900
    function bx(c) { return (80 + c * 80) * sx; }
    function by(r) { return (70 + r * 80) * sy; }
    function clockOf(it, key, def) { return WidgetTypes.clockValue(it, key, (clock || {})[key] ?? def); }

    implicitWidth: 240
    implicitHeight: 135
    radius: 9
    clip: true
    color: Theme.base

    // фон темы, если обоев нет (как у самого стола)
    Rectangle {
        anchors.fill: parent
        visible: !wallImg.visible
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.darker(Theme.accent, 2.2) }
            GradientStop { position: 1; color: Theme.base }
        }
    }
    Image {
        id: wallImg
        anchors.fill: parent
        visible: root.wall !== "" && !Media.isVideo(root.wall) && status !== Image.Error
        source: visible ? Media.fileUrl(root.wall) : ""
        sourceSize: Qt.size(480, 270)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    // экран блокировки чуть темнее обоев
    Rectangle { anchors.fill: parent; visible: root.lock; color: Qt.rgba(0, 0, 0, 0.18) }

    // доки стола
    Rectangle {
        visible: !root.lock
        anchors { top: parent.top; topMargin: 12 * root.sy; horizontalCenter: parent.horizontalCenter }
        width: parent.width * 0.33; height: Math.max(3, 40 * root.sy)
        radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.55)
    }
    Rectangle {
        visible: !root.lock
        anchors { bottom: parent.bottom; bottomMargin: 14 * root.sy; horizontalCenter: parent.horizontalCenter }
        width: parent.width * 0.23; height: Math.max(4, 74 * root.sy)
        radius: height * 0.3
        color: Qt.rgba(0, 0, 0, 0.45)
    }

    Repeater {
        model: (root.items || []).filter(x => x && x.id !== "clock" && x.id !== "login")
        delegate: Rectangle {
            required property var modelData
            x: root.bx(modelData.c ?? 0) + 2
            y: root.by(modelData.r ?? 0) + 2
            width: (modelData.w ?? 2) * 80 * root.sx - 4
            height: (modelData.h ?? 2) * 80 * root.sy - 4
            radius: Math.min(width, height) * 0.18
            color: modelData.bg === false ? "transparent" : Qt.rgba(0, 0, 0, 0.32)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.22)
            Sym {
                anchors.centerIn: parent
                readonly property var t: (root.lock ? WidgetTypes.lock : WidgetTypes.desktop)[parent.modelData.id] || null
                name: t ? t.icon : "widgets"
                size: Math.max(8, Math.min(parent.width, parent.height) * 0.42)
                color: Qt.rgba(1, 1, 1, 0.85)
            }
        }
    }

    // часы — в своём виде
    Repeater {
        model: (root.items || []).filter(x => x && x.id === "clock")
        delegate: Item {
            id: ck
            required property var modelData
            readonly property string st: root.clockOf(modelData, "style", "ios")
            readonly property string tint: root.clockOf(modelData, "color", "white")
            readonly property string kind: root.clockOf(modelData, "tallKind", "line")
            readonly property color ink: tint === "accent" ? Theme.accent : "#ffffff"
            x: root.bx(modelData.c ?? 5)
            y: root.by(modelData.r ?? 1)
            width: (modelData.w ?? 7) * 80 * root.sx
            height: (modelData.h ?? 3) * 80 * root.sy

            WParts.TallDigits {
                visible: ck.st === "tall"
                anchors.centerIn: parent
                text: "09:41"
                digitHeight: parent.height * 0.72
                widthRatio: Math.min(0.5, Number(root.clockOf(ck.modelData, "tallWidth", 0.35)) || 0.35)
                look: ck.kind === "hollow" ? "hollow" : ck.kind === "mixed" || ck.tint === "glass" ? "glass" : "solid"
                minutesLook: ck.kind === "mixed" ? "solid" : look
                color: ck.ink
            }
            WParts.DotDigits {
                visible: ck.st === "dots"
                anchors.centerIn: parent
                text: "09:41"
                digitHeight: parent.height * 0.6
                color: ck.ink
            }
            Text {
                id: plain
                visible: ck.st !== "tall" && ck.st !== "dots"
                anchors.centerIn: parent
                text: ck.st === "stack" ? "09\n41" : "09:41"
                horizontalAlignment: Text.AlignHCenter
                lineHeight: ck.st === "stack" ? 0.82 : 1
                color: ck.tint === "glass" ? "#ffffff" : ck.ink
                style: ck.st === "outline" ? Text.Outline : Text.Normal
                styleColor: ck.ink
                font.family: Theme.fontDisplay
                font.weight: ck.st === "thin" ? Font.ExtraLight : Font.Bold
                font.pixelSize: Math.max(6, ck.st === "stack" ? parent.height * 0.4 : Math.min(parent.height * 0.5, parent.width * 0.22))
                layer.enabled: ck.tint === "glass"
            }
            GlassFace {
                item: plain
                visible: plain.visible && ck.tint === "glass"
                rim: 1
                fill: 0.38
                tint: "#ffffff"
            }
        }
    }

    // поле входа на экране блокировки: аватар и строка пароля
    Item {
        visible: root.lock
        readonly property var spot: (root.items || []).find(x => x && x.id === "login") || { c: 6, r: 6, w: 5, h: 3 }
        x: root.bx(spot.c); y: root.by(spot.r)
        width: spot.w * 80 * root.sx; height: spot.h * 80 * root.sy
        Rectangle {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.1 }
            width: parent.height * 0.32; height: width; radius: width / 2
            color: Theme.accent
        }
        Rectangle {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: parent.height * 0.18 }
            width: parent.width * 0.7; height: parent.height * 0.16; radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.2)
        }
    }
}
