import QtQuick
import QtQuick.Effects
import qs.common
import qs.common.ui
import qs.widgets.kinds

// Карточка одного виджета на сетке: подложка, содержимое, а в редакторе —
// покачивание, рамка выбора, «×» и уголок для изменения размера.
// Геометрию (bx/by/bw/bh) и перетаскивание ведёт WidgetGrid.
Item {
    id: root

    required property var grid
    required property var item
    property string place: "desktop"
    property bool editing: false
    property bool selected: false
    // перетаскивание этой карточки: смещение от её клетки в пикселях
    property bool dragging: false
    property real dragDx: 0
    property real dragDy: 0
    property bool resizing: false
    // целевая геометрия в пикселях
    property real bx: 0
    property real by: 0
    property real bw: 100
    property real bh: 100
    // масштаб сетки относительно концепта (клетка 80 px)
    property real unit: 1

    readonly property bool lock: place === "lock"
    readonly property bool bg: item.bg !== false
    readonly property bool isClock: item.id === "clock"
    // прозрачность виджета (item.opacity, 0.15–1; редактор → «прозрачность»)
    readonly property real alpha: Math.max(0.15, Math.min(1, Number(item.opacity ?? 1) || 1))

    x: bx + (dragging ? dragDx : 0)
    y: by + (dragging ? dragDy : 0)
    width: bw
    height: bh
    z: dragging || resizing ? 10 : selected ? 2 : 1

    // перенос и смена размера — с пружинкой, как в концепте; за пальцем — без анимации
    Behavior on x { enabled: !root.dragging; NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
    Behavior on y { enabled: !root.dragging; NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
    Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
    Behavior on height { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

    // цвета содержимого: на стекле — тема, без подложки и на блокировке — белые с тенью
    readonly property QtObject pal: QtObject {
        readonly property bool themed: root.bg && !root.lock
        property color c1: themed ? Theme.fg : "#ffffff"
        property color c2: themed ? Theme.fg2 : Qt.rgba(1, 1, 1, 0.88)
        property color c3: themed ? Theme.fg3 : Qt.rgba(1, 1, 1, 0.78)
        property color track: themed ? Theme.soft2 : Qt.rgba(1, 1, 1, 0.2)
    }

    readonly property real radius: (lock ? 20 : 26) * unit

    Item {
        id: frame
        anchors.fill: parent
        // поднятая при перетаскивании карточка чуть крупнее
        transform: Scale {
            origin.x: frame.width / 2
            origin.y: frame.height / 2
            xScale: root.dragging ? 1.04 : 1
            yScale: xScale
            Behavior on xScale { NumberAnimation { duration: Theme.anim.fast } }
        }

        // появление: лёгкий «поп» (frame.scale занят только им)
        opacity: 0
        Component.onCompleted: appear.start()
        ParallelAnimation {
            id: appear
            NumberAnimation { target: frame; property: "opacity"; from: 0; to: 1; duration: 300 }
            NumberAnimation { target: frame; property: "scale"; from: 0.92; to: 1; duration: 450; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
        }

        // покачивание в редакторе (jig)
        SequentialAnimation on rotation {
            running: root.editing && !root.dragging && !root.resizing
            loops: Animation.Infinite
            NumberAnimation { from: -1.4; to: 1.4; duration: 340; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.4; to: -1.4; duration: 340; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) frame.rotation = 0
        }

        Rectangle {
            id: plate
            anchors.fill: parent
            radius: root.radius
            opacity: root.alpha
            color: !root.bg ? "transparent" : root.lock ? Qt.rgba(1, 1, 1, 0.14) : Theme.glass
            border.width: root.bg || root.editing ? 1 : 0
            border.color: !root.bg ? Qt.rgba(1, 1, 1, 0.45) : root.lock ? Qt.rgba(1, 1, 1, 0.16) : Theme.line
            Behavior on color { ColorAnimation { duration: Theme.anim.normal } }
        }

        // содержимое; отступы — в процентах от размера, как padding в cq-единицах
        Item {
            id: body
            opacity: root.alpha
            anchors {
                fill: parent
                topMargin: root.lock ? 12 * root.height / 100 : 7 * Math.min(root.width, root.height) / 100
                bottomMargin: anchors.topMargin
                leftMargin: root.lock ? 14 * root.height / 100 : 8 * Math.min(root.width, root.height) / 100
                rightMargin: anchors.leftMargin
            }
            // без подложки текст читается поверх обоев за счёт мягкой тени
            layer.enabled: !root.bg && !root.isClock
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.6)
                shadowBlur: 0.6
                blurMax: 20
                shadowVerticalOffset: 1
                shadowHorizontalOffset: 0
            }

            Loader {
                id: content
                anchors.fill: parent
                sourceComponent: {
                    switch (root.item.id) {
                    case "clock": return clockC;
                    case "weather": return weatherC;
                    case "music": return musicC;
                    case "pc": return pcC;
                    case "cpu": case "ram": case "gpu": case "disk": return metricC;
                    case "gtemp": case "ctemp": return tempC;
                    case "calendar": return calendarC;
                    case "battery": return batteryC;
                    case "notifs": return notifsC;
                    case "bars": return barsC;
                    }
                    return null;
                }
            }
        }

        Rectangle {
            // рамка выбранного виджета
            anchors { fill: parent; margins: -3 * root.unit - 2.5 }
            radius: root.radius + 3 * root.unit + 2.5
            color: "transparent"
            border.width: 2.5
            border.color: Theme.accent
            visible: root.editing && root.selected
        }

        // перетаскивание и выбор
        MouseArea {
            id: dragArea
            anchors.fill: parent
            enabled: root.editing
            cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            preventStealing: true
            property point start
            onPressed: m => {
                start = mapToItem(root.grid, m.x, m.y);
                root.grid.select(root.item.id);
                root.grid.beginDrag("move", root.item.id);
            }
            onPositionChanged: m => {
                const p = mapToItem(root.grid, m.x, m.y);
                root.grid.updateDrag(p.x - start.x, p.y - start.y);
            }
            onReleased: root.grid.endDrag()
            onCanceled: root.grid.cancelDrag()
        }

        // долгое нажатие вне редактора — войти в редактор (как на телефоне)
        TapHandler {
            enabled: !root.editing && !root.lock
            longPressThreshold: 0.6
            onLongPressed: root.grid.requestEdit(root.item.id)
        }

        // «×» — убрать виджет
        Rectangle {
            visible: root.editing && !root.dragging
            x: -8 * root.unit; y: -8 * root.unit
            width: 24 * root.unit; height: width
            radius: width / 2
            color: Theme.accents[5]
            Sym { anchors.centerIn: parent; name: "close"; size: Math.round(parent.width * 0.6); color: "#ffffff" }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.grid.remove(root.item.id) }
        }

        // уголок — изменить размер
        Rectangle {
            visible: root.editing && !root.dragging
            x: parent.width - width + 7 * root.unit; y: parent.height - height + 7 * root.unit
            width: 22 * root.unit; height: width
            radius: width / 2
            color: Theme.accent
            border.width: 2
            border.color: "#ffffff"
            MouseArea {
                anchors { fill: parent; margins: -6 }
                cursorShape: Qt.SizeFDiagCursor
                preventStealing: true
                property point start
                onPressed: m => {
                    start = mapToItem(root.grid, m.x, m.y);
                    root.grid.select(root.item.id);
                    root.grid.beginDrag("resize", root.item.id);
                }
                onPositionChanged: m => {
                    const p = mapToItem(root.grid, m.x, m.y);
                    root.grid.updateDrag(p.x - start.x, p.y - start.y);
                }
                onReleased: root.grid.endDrag()
                onCanceled: root.grid.cancelDrag()
            }
        }
    }

    Component { id: clockC; ClockWidget { card: root } }
    Component { id: weatherC; WeatherWidget { card: root } }
    Component { id: musicC; MusicWidget { card: root } }
    Component { id: pcC; PcWidget { card: root } }
    Component { id: metricC; MetricWidget { card: root } }
    Component { id: tempC; TempWidget { card: root } }
    Component { id: calendarC; CalendarWidget { card: root } }
    Component { id: batteryC; BatteryWidget { card: root } }
    Component { id: notifsC; NotifsWidget { card: root } }
    Component { id: barsC; BarsWidget { card: root } }
}
