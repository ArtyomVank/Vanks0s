pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.services
import qs.widgets.parts

// Панель редактора виджетов (.edbar в концепте): сверху — галерея «добавить /
// убрать» и «Готово», снизу — настройки выбранного виджета.
Glass {
    id: root

    required property var grid
    property bool shown: false

    strong: true
    radius: 22
    implicitHeight: col.implicitHeight + 24
    // пока что-то тащат, панель почти прозрачна: под ней тоже клетки сетки
    opacity: !shown ? 0 : grid.drag ? 0.25 : 1
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Theme.anim.normal } }
    Behavior on y { NumberAnimation { duration: 450; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

    readonly property string place: grid.place
    readonly property var it: grid.sel ? grid.find(grid.sel) : null
    readonly property var info: it ? WidgetTypes.info(place, it.id) : null
    readonly property bool tallClock: !!it && it.id === "clock" && (it.style || Settings.get("clock.style", "ios")) === "tall"

    // клики по панели не должны снимать выбор на сетке
    MouseArea { anchors.fill: parent; onPressed: m => m.accepted = true }

    component Sub: Label { size: "small"; tone: 3 }
    component Sep: Item { width: 9; height: 30; Rectangle { anchors.centerIn: parent; width: 1; height: 22; color: Theme.line } }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12; leftMargin: 16; rightMargin: 16 }
        spacing: 10

        // ---- галерея ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Label { text: root.place === "lock" ? "Экран блокировки" : "Виджеты"; size: "title"; Layout.alignment: Qt.AlignTop; Layout.topMargin: 4 }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: WidgetTypes.order(root.place).filter(id => WidgetTypes.available(root.place, id))
                    delegate: Btn {
                        id: g
                        required property string modelData
                        readonly property bool on: root.grid.items.some(x => x.id === g.modelData)
                        implicitHeight: 30
                        iconSize: 14
                        icon: on ? "check" : "plus"
                        text: (WidgetTypes.info(root.place, modelData) || { name: "" }).name
                        kind: on ? "accent" : "ghost"
                        onClicked: { root.grid.toggle(modelData); root.grid.forceActiveFocus(); }
                    }
                }
            }
            Btn { text: "Готово"; kind: "accent"; Layout.alignment: Qt.AlignTop; onClicked: root.grid.finish() }
        }

        // ---- выбранный виджет ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Flow {
                Layout.fillWidth: true
                spacing: 8

                Sub {
                    visible: !root.it
                    height: 30
                    text: "Нажмите на виджет — здесь появятся его настройки"
                }

                Label { visible: !!root.it; height: 30; text: root.info ? "«" + root.info.name + "»" : ""; font.weight: Font.DemiBold }

                // режим
                Sub { visible: !!root.info && root.info.modes.length > 0; height: 30; text: "режим:" }
                Chips {
                    visible: !!root.info && root.info.modes.length > 0
                    model: root.info ? root.info.modes.map(m => ({ value: m[0], label: m[1] })) : []
                    current: root.it ? root.it.mode : ""
                    onPicked: v => root.grid.setMode(root.it.id, v)
                }
                Sep { visible: !!root.info && root.info.modes.length > 0 }

                // часы: стиль и цвет (у виджета, поверх общих clock.*)
                Sub { visible: !!root.it && root.it.id === "clock"; height: 30; text: "стиль:" }
                Chips {
                    visible: !!root.it && root.it.id === "clock"
                    model: WidgetTypes.clockStyles
                    current: root.it ? (root.it.style || Settings.get("clock.style", "ios")) : ""
                    onPicked: v => root.grid.setStyle("clock", v)
                }
                Sub { visible: !!root.it && root.it.id === "clock"; height: 30; text: "цвет:" }
                Chips {
                    visible: !!root.it && root.it.id === "clock"
                    model: WidgetTypes.clockColors
                    current: root.it ? (root.it.color || Settings.get("clock.color", "white")) : ""
                    onPicked: v => root.grid.setColor("clock", v)
                }
                // «Длинные» часы: ширина цифр
                Sub { visible: root.tallClock; height: 30; text: "ширина цифр:" }
                Slider {
                    visible: root.tallClock
                    width: 150
                    height: 30
                    from: 0.35; to: 0.95
                    value: root.it ? Number(root.it.tallWidth ?? Settings.get("clock.tallWidth", 0.62)) : 0.62
                    onReleased: v => root.grid.setTallWidth(root.it.id, v)
                }
                Sep { visible: !!root.it && root.it.id === "clock" }

                // погода: город
                Sub { visible: !!root.it && root.it.id === "weather"; height: 30; text: "город:" }
                Field {
                    id: city
                    visible: !!root.it && root.it.id === "weather"
                    width: 170
                    height: 30
                    icon: "search"
                    placeholder: "Например, Москва"
                    text: Settings.get("weather.city", "")
                    onAccepted: v => { Settings.set("weather.city", v.trim()); root.grid.forceActiveFocus(); }
                }
                Btn {
                    visible: !!root.it && root.it.id === "weather"
                    implicitHeight: 30
                    text: "Найти"
                    onClicked: { Settings.set("weather.city", city.text.trim()); root.grid.forceActiveFocus(); }
                }
                Sub {
                    visible: !!root.it && root.it.id === "weather"
                    height: 30
                    text: Weather.loading ? "Ищем…"
                        : Weather.error.length ? Weather.error
                        : Weather.hasData ? Weather.place.name + (Weather.place.country ? ", " + Weather.place.country : "")
                        : Weather.city.length ? "" : "Укажите город"
                }
                Sep { visible: !!root.it && root.it.id === "weather" }

                // прозрачность — у любого виджета
                Sub { visible: !!root.it; height: 30; text: "прозрачность:" }
                Slider {
                    visible: !!root.it
                    width: 150
                    height: 30
                    from: 0.15; to: 1
                    // слева прозрачнее, справа — как есть
                    value: root.it ? Number(root.it.opacity ?? 1) : 1
                    onReleased: v => root.grid.setOpacity(root.it.id, v)
                }
                Sep { visible: !!root.it }

                // фон
                Sub { visible: !!root.it; height: 30; text: "фон:" }
                Chips {
                    visible: !!root.it
                    model: [{ value: true, label: "С фоном" }, { value: false, label: "Без фона" }]
                    current: root.it ? root.it.bg : true
                    onPicked: v => root.grid.setBg(root.it.id, v)
                }
                Sep { visible: !!root.it }

                // размер
                Sub { visible: !!root.it; height: 30; text: "размер:" }
                Chips {
                    visible: !!root.it
                    model: root.it ? WidgetTypes.presets(root.place, root.it.id, root.it.mode) : []
                    current: root.it ? root.it.w + "×" + root.it.h : ""
                    onPicked: v => {
                        const p = v.split("×").map(Number);
                        root.grid.resizeTo(root.it.id, p[0], p[1]);
                    }
                }
                Label { visible: !!root.it; height: 30; text: "или тяните за уголок"; size: "caption"; tone: 3 }
            }

            Label {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 6
                text: root.grid.caption || "Перетаскивайте по сетке · Esc — готово"
                size: "caption"
                tone: root.grid.caption ? 1 : 3
                color: root.grid.caption ? Theme.accents[4] : Theme.fg3
            }
        }
    }
}
