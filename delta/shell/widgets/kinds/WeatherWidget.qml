pragma ComponentBehavior: Bound

import QtQuick
import qs.common
import qs.common.ui
import qs.services
import qs.widgets.parts

// Погода: «Компакт» (2×2) и «Подробно» (от 4×2) на рабочем столе,
// строка «иконка · температура · состояние» на экране блокировки.
Base {
    id: root

    WeatherUser { active: root.visible }

    readonly property bool noCity: Weather.city.length === 0
    readonly property var cur: Weather.hasData ? Weather.current : null
    readonly property string place: Weather.place && Weather.hasData ? Weather.place.name : (noCity ? "Погода" : Weather.city)
    readonly property string iconName: cur ? cur.icon : noCity ? "globe" : "cloud"
    readonly property string tempText: cur ? Weather.temp(cur.temp) : "—"
    readonly property string stateText: cur ? cur.text
        : noCity ? (editing ? "Укажите город ниже" : "Город не указан")
        : Weather.loading ? "Загрузка…" : Weather.error.length ? Weather.error : "нет данных"

    // ---- рабочий стол, «Компакт» ----
    Item {
        anchors.fill: parent
        visible: !root.lock && root.mode !== "wide"

        WCaption { id: cCap; cm: root.cm; text: root.place; color: root.pal.c2; width: parent.width }
        Sym {
            anchors { top: cCap.bottom; topMargin: (parent.height - cCap.height - size - cBottom.height) / 2 }
            name: root.iconName
            size: Math.round(28 * root.cm)
            color: Weather.iconColor(root.iconName, root.pal.c1)
        }
        Column {
            id: cBottom
            anchors.bottom: parent.bottom
            width: parent.width
            WText { text: root.tempText; px: 24 * root.cm; display: true; color: root.pal.c1 }
            WText { text: root.stateText; px: 8 * root.cm; color: root.pal.c3; width: parent.width }
        }
    }

    // ---- рабочий стол, «Подробно» ----
    Item {
        id: wide
        anchors.fill: parent
        visible: !root.lock && root.mode === "wide"

        // часов в строке тем больше, чем шире виджет относительно высоты —
        // при пропорциональном растягивании содержимое просто растёт
        readonly property int hours: Math.max(3, Math.min(8, Math.round(root.width / root.height * 2.5)))

        Column {
            id: topCol
            anchors { left: parent.left; top: parent.top; right: wIcon.left }
            WCaption { cm: root.cm; text: root.place; color: root.pal.c2; width: parent.width }
            WText { text: root.tempText; px: Math.min(30 * root.ch, 14 * root.cw); display: true; color: root.pal.c1 }
            WText {
                width: parent.width
                text: root.cur ? root.cur.text + " · ощущается как " + Weather.temp(root.cur.feels) : root.stateText
                px: Math.min(8.5 * root.ch, 4 * root.cw)
                color: root.pal.c3
            }
        }
        Sym {
            id: wIcon
            anchors { right: parent.right; top: parent.top }
            name: root.iconName
            size: Math.round(Math.min(34 * root.ch, 16 * root.cw))
            color: Weather.iconColor(root.iconName, root.pal.c1)
        }
        // если по высоте остаётся место — ещё и прогноз по дням, чтобы середина не пустовала
        Row {
            id: daysRow
            anchors { left: parent.left; right: parent.right; bottom: hoursRow.top; bottomMargin: 5 * root.ch }
            // высота считается по формуле, а не по implicitHeight: у скрытого Row она 0 и зациклилась бы
            readonly property real need: 2.5 * Math.min(6.5 * root.ch, 3.4 * root.cw) + Math.min(11 * root.ch, 5 * root.cw) + 3 * root.ch
            visible: root.cur !== null && hoursRow.y - topCol.height >= need + 10 * root.ch
            Repeater {
                model: root.cur ? Weather.daily.slice(0, wide.hours) : []
                delegate: Column {
                    id: dcol
                    required property var modelData
                    width: wide.width / wide.hours
                    spacing: 1.5 * root.ch
                    WText { anchors.horizontalCenter: parent.horizontalCenter; text: dcol.modelData.name; px: Math.min(6.5 * root.ch, 3.4 * root.cw); color: root.pal.c3 }
                    Sym { anchors.horizontalCenter: parent.horizontalCenter; name: dcol.modelData.icon; size: Math.round(Math.min(11 * root.ch, 5 * root.cw)); color: Weather.iconColor(name, root.pal.c1) }
                    WText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Weather.temp(dcol.modelData.max) + " " + Weather.temp(dcol.modelData.min)
                        px: Math.min(6.5 * root.ch, 3.4 * root.cw)
                        color: root.pal.c2
                    }
                }
            }
        }
        Row {
            id: hoursRow
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            visible: root.cur !== null
            Repeater {
                model: root.cur ? Weather.hourly.filter((h, i) => i > 0 && i % 2 === 0).slice(0, wide.hours) : []
                delegate: Column {
                    id: hcol
                    required property var modelData
                    width: wide.width / wide.hours
                    WText { anchors.horizontalCenter: parent.horizontalCenter; text: hcol.modelData.hour; px: Math.min(7.5 * root.ch, 3.4 * root.cw); color: root.pal.c3 }
                    WText { anchors.horizontalCenter: parent.horizontalCenter; text: Weather.temp(hcol.modelData.temp); px: Math.min(9.5 * root.ch, 4.2 * root.cw); font.weight: Font.Bold; color: root.pal.c1 }
                }
            }
        }
    }

    // ---- экран блокировки ----
    Item {
        anchors.fill: parent
        visible: root.lock

        // «Строка»: значок в стеклянном круге · температура · город и состояние.
        // Без данных — не «—», а что сделать: указать город
        Row {
            id: lockRow
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            visible: root.mode !== "block"
            spacing: 6 * root.cm
            readonly property real chip: Math.min(62 * root.ch, 26 * root.cw)
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: lockRow.chip; height: width
                radius: width / 2
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.24) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.08) }
                }
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.22)
                Sym {
                    anchors.centerIn: parent
                    name: root.cur ? root.iconName : "cloud-sun"
                    size: Math.round(parent.width * 0.56)
                    color: root.cur ? Weather.iconColor(root.iconName, root.pal.c1) : root.pal.c1
                    // солнце за тучей чуть покачивается
                    SequentialAnimation on rotation {
                        running: root.visible && root.lock
                        loops: Animation.Infinite
                        NumberAnimation { from: -4; to: 4; duration: 2600; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 4; to: -4; duration: 2600; easing.type: Easing.InOutSine }
                    }
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - lockRow.chip - parent.spacing
                spacing: 1 * root.ch
                WText {
                    width: parent.width
                    text: root.cur ? root.tempText : root.noCity ? I18n.tr("Погода") : root.place
                    px: root.cur ? Math.min(34 * root.ch, 14 * root.cw) : Math.min(22 * root.ch, 9 * root.cw)
                    display: root.cur !== null
                    font.weight: Font.ExtraBold
                    color: root.pal.c1
                }
                WText {
                    width: parent.width
                    text: root.cur ? root.place + " · " + root.cur.text
                        : root.noCity ? I18n.tr("Укажите город") : root.stateText
                    px: Math.min(14 * root.ch, 5.6 * root.cw)
                    color: root.pal.c1
                    opacity: 0.78
                }
            }
        }

        // «Блок»: крупная иконка и температура сверху, место и состояние снизу
        Item {
            anchors.fill: parent
            visible: root.mode === "block"

            Sym {
                id: bIcon
                anchors { left: parent.left; top: parent.top }
                name: root.iconName
                size: Math.round(Math.min(30 * root.ch, 13 * root.cw))
                color: Weather.iconColor(root.iconName, root.pal.c1)
            }
            WText {
                anchors { left: bIcon.right; leftMargin: 4 * root.cw; right: parent.right; top: parent.top }
                text: root.tempText
                px: Math.min(40 * root.ch, 17 * root.cw)
                display: true
                font.weight: Font.ExtraBold
                color: root.pal.c1
            }
            WText {
                id: bState
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                text: root.cur ? root.stateText + " · ощущается как " + Weather.temp(root.cur.feels) : root.stateText
                px: Math.min(14 * root.ch, 5.5 * root.cw)
                color: root.pal.c1
                opacity: 0.8
            }
            WText {
                anchors { left: parent.left; right: parent.right; bottom: bState.top; bottomMargin: 2 * root.cm }
                text: root.place
                px: Math.min(12 * root.ch, 4.8 * root.cw)
                font.weight: Font.Bold
                color: root.pal.c1
                opacity: 0.9
            }
        }
    }
}
