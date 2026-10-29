pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.services
import qs.widgets.parts

// Панель редактора виджетов: сверху — галерея карточек (нажатие добавляет
// или убирает виджет), снизу — настройки выбранного виджета, по строке на
// свойство. Панель узкая и стоит по центру снизу, чтобы не закрывать сетку.
Glass {
    id: root

    required property var grid
    property bool shown: false

    strong: true
    radius: 24
    implicitHeight: col.implicitHeight + 28
    // пока что-то тащат, панель почти прозрачна: под ней тоже клетки сетки
    opacity: !shown ? 0 : grid.drag ? 0.25 : 1
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Theme.anim.normal } }
    Behavior on y { NumberAnimation { duration: 450; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
    Behavior on implicitHeight { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

    readonly property string place: grid.place
    readonly property var it: grid.sel ? grid.find(grid.sel) : null
    readonly property var info: it ? WidgetTypes.info(place, it.id) : null
    readonly property bool isClock: !!it && it.id === "clock"
    readonly property bool isWeather: !!it && it.id === "weather"
    readonly property bool tallClock: isClock && (it.style || Settings.get("clock.style", "ios")) === "tall"

    // клики по панели не должны снимать выбор на сетке
    MouseArea { anchors.fill: parent; onPressed: m => m.accepted = true }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; leftMargin: 18; rightMargin: 18 }
        spacing: 12

        // ---- шапка ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true
                Label { text: root.place === "lock" ? "Виджеты экрана блокировки" : "Виджеты рабочего стола"; size: "title" }
                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.grid.caption || "Перетаскивайте по сетке, тяните за уголок — размер. Стрелки двигают выбранный, Delete убирает."
                    size: "caption"
                    color: root.grid.caption ? Theme.accents[4] : Theme.fg3
                }
            }
            Btn { text: "Готово"; kind: "accent"; onClicked: root.grid.finish() }
        }

        // ---- галерея: карточка на каждый вид виджета ----
        ListView {
            id: gallery
            Layout.fillWidth: true
            Layout.preferredHeight: 78
            orientation: ListView.Horizontal
            spacing: 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: WidgetTypes.order(root.place).filter(id => WidgetTypes.available(root.place, id))
            delegate: Rectangle {
                id: card
                required property string modelData
                readonly property var meta: WidgetTypes.info(root.place, modelData) || ({ name: "", icon: "widgets" })
                readonly property bool on: root.grid.items.some(x => x.id === card.modelData)
                readonly property bool current: root.grid.sel === modelData
                width: 92
                height: 78
                radius: 16
                color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, current ? 0.32 : 0.18)
                     : tap.containsMouse ? Theme.soft2 : Theme.soft
                border.width: current ? 1.5 : 1
                border.color: current ? Theme.accent : Theme.line
                Behavior on color { ColorAnimation { duration: 160 } }
                scale: tap.pressed ? 0.94 : 1
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 } }

                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    Sym {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: card.meta.icon
                        size: 22
                        color: card.on ? Theme.accent : Theme.fg2
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: card.width - 12
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: card.meta.short || card.meta.name
                        size: "caption"
                        tone: card.on ? 1 : 2
                    }
                }
                // уже на столе — галочка в углу
                Rectangle {
                    visible: card.on
                    anchors { right: parent.right; top: parent.top; margins: 6 }
                    width: 18; height: 18; radius: 9
                    color: Theme.accent
                    Sym { anchors.centerIn: parent; name: "check"; size: 12; color: Theme.onAccent }
                }
                MouseArea {
                    id: tap
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // нет на столе — добавить и сразу выбрать; есть — выбрать,
                    // повторное нажатие по выбранному — убрать
                    onClicked: {
                        if (!card.on) { root.grid.toggle(card.modelData); root.grid.select(card.modelData); }
                        else if (!card.current) root.grid.select(card.modelData);
                        else root.grid.toggle(card.modelData);
                        root.grid.forceActiveFocus();
                    }
                }
            }
            // колесо мыши листает галерею вбок
            WheelHandler {
                orientation: Qt.Vertical
                onWheel: e => gallery.flick(e.angleDelta.y * 6, 0)
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.line }

        // ---- ничего не выбрано ----
        Label {
            visible: !root.it
            Layout.fillWidth: true
            Layout.bottomMargin: 2
            horizontalAlignment: Text.AlignHCenter
            text: "Нажмите на виджет на столе — здесь появятся его настройки"
            tone: 3
        }

        // ---- выбранный виджет ----
        RowLayout {
            visible: !!root.it
            Layout.fillWidth: true
            spacing: 10
            Rectangle {
                implicitWidth: 34; implicitHeight: 34; radius: 10
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2)
                Sym { anchors.centerIn: parent; name: root.info ? root.info.icon : "widgets"; size: 18; color: Theme.accent }
            }
            Label { text: root.info ? root.info.name : ""; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
            Btn { text: "Убрать со стола"; kind: "danger"; icon: "trash"; onClicked: root.grid.remove(root.it.id) }
        }

        GridLayout {
            visible: !!root.it
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 12
            rowSpacing: 10

            // вид (режим)
            Label { Layout.preferredWidth: 104; tone: 3; visible: !!root.info && root.info.modes.length > 0; text: "Вид" }
            Chips {
                Layout.fillWidth: true
                visible: !!root.info && root.info.modes.length > 0
                model: root.info ? root.info.modes.map(m => ({ value: m[0], label: m[1] })) : []
                current: root.it ? root.it.mode : ""
                onPicked: v => root.grid.setMode(root.it.id, v)
            }

            // часы
            Label { Layout.preferredWidth: 104; tone: 3; visible: root.isClock; text: "Стиль цифр" }
            Chips {
                Layout.fillWidth: true
                visible: root.isClock
                model: WidgetTypes.clockStyles
                current: root.it ? (root.it.style || Settings.get("clock.style", "ios")) : ""
                onPicked: v => root.grid.setStyle("clock", v)
            }
            Label { Layout.preferredWidth: 104; tone: 3; visible: root.isClock; text: "Цвет" }
            Chips {
                Layout.fillWidth: true
                visible: root.isClock
                model: WidgetTypes.clockColors
                current: root.it ? (root.it.color || Settings.get("clock.color", "white")) : ""
                onPicked: v => root.grid.setColor("clock", v)
            }
            Label { Layout.preferredWidth: 104; tone: 3; visible: root.tallClock; text: "Ширина цифр" }
            Slider {
                visible: root.tallClock
                Layout.preferredWidth: 220
                implicitHeight: 30
                from: 0.35; to: 0.95
                value: root.it ? Number(root.it.tallWidth ?? Settings.get("clock.tallWidth", 0.62)) : 0.62
                onReleased: v => root.grid.setTallWidth(root.it.id, v)
            }

            // погода
            Label { Layout.preferredWidth: 104; tone: 3; visible: root.isWeather; text: "Город" }
            RowLayout {
                visible: root.isWeather
                spacing: 8
                Field {
                    id: city
                    implicitWidth: 200
                    implicitHeight: 32
                    icon: "search"
                    placeholder: "Например, Москва"
                    text: Settings.get("weather.city", "")
                    onAccepted: v => { Settings.set("weather.city", v.trim()); root.grid.forceActiveFocus(); }
                }
                Btn { text: "Найти"; onClicked: { Settings.set("weather.city", city.text.trim()); root.grid.forceActiveFocus(); } }
                Label {
                    tone: 3
                    size: "small"
                    text: Weather.loading ? "Ищем…"
                        : Weather.error.length ? Weather.error
                        : Weather.hasData ? "✓ " + Weather.place.name + (Weather.place.country ? ", " + Weather.place.country : "")
                        : ""
                }
            }

            // размер
            Label { Layout.preferredWidth: 104; tone: 3; visible: !!root.it; text: "Размер" }
            RowLayout {
                visible: !!root.it
                spacing: 10
                Chips {
                    model: root.it ? WidgetTypes.presets(root.place, root.it.id, root.it.mode) : []
                    current: root.it ? root.it.w + "×" + root.it.h : ""
                    onPicked: v => {
                        const p = v.split("×").map(Number);
                        root.grid.resizeTo(root.it.id, p[0], p[1]);
                    }
                }
                Label { text: "или тяните за уголок"; size: "caption"; tone: 3 }
            }

            // фон и прозрачность — у любого виджета
            Label { Layout.preferredWidth: 104; tone: 3; visible: !!root.it; text: "Подложка" }
            Chips {
                Layout.fillWidth: true
                visible: !!root.it
                model: [{ value: true, label: "Стекло" }, { value: false, label: "Без подложки" }]
                current: root.it ? root.it.bg !== false : true
                onPicked: v => root.grid.setBg(root.it.id, v)
            }
            Label { Layout.preferredWidth: 104; tone: 3; visible: !!root.it; text: "Прозрачность" }
            RowLayout {
                visible: !!root.it
                spacing: 10
                Slider {
                    id: alpha
                    Layout.preferredWidth: 220
                    implicitHeight: 30
                    from: 0.15; to: 1
                    value: root.it ? Number(root.it.opacity ?? 1) : 1
                    onReleased: v => root.grid.setOpacity(root.it.id, v)
                }
                Label { text: Math.round(alpha.shown * 100 * (alpha.to - alpha.from) + alpha.from * 100) + " %"; size: "small"; tone: 2 }
            }
        }
    }
}
