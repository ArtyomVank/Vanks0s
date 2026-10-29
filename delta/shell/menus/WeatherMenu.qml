pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.services
import qs.widgets.parts

// Меню «Погода» верхнего дока: сейчас, по часам, на 5 дней.
// Фон рисует док. Город не указан — предлагаем ввести его здесь же.
Item {
    id: root

    implicitWidth: 360
    implicitHeight: column.implicitHeight
    signal close()

    WeatherUser { active: root.visible }

    readonly property var cur: Weather.hasData ? Weather.current : null
    property bool editCity: false

    ColumnLayout {
        id: column
        anchors { left: parent.left; right: parent.right }
        spacing: 14

        // ---- город ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: !root.editCity && Weather.city.length > 0
            Sym { name: "globe"; size: 16; color: Theme.fg3 }
            Label {
                Layout.fillWidth: true
                text: Weather.place && Weather.hasData
                    ? Weather.place.name + (Weather.place.admin && Weather.place.admin !== Weather.place.name ? ", " + Weather.place.admin : "")
                    : Weather.city
                tone: 2
            }
            Btn { icon: "edit"; implicitHeight: 28; iconSize: 14; kind: "ghost"; onClicked: { root.editCity = true; cityField.focusInput(); } }
            Btn { icon: "restart"; implicitHeight: 28; iconSize: 14; kind: "ghost"; onClicked: Weather.refresh(true) }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.editCity || Weather.city.length === 0
            Label { text: Weather.city.length ? "Другой город" : "Город не указан"; size: "title" }
            Label { text: I18n.tr("Прогноз Open-Meteo для вашего города"); size: "small"; tone: 3; visible: Weather.city.length === 0 }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Field {
                    id: cityField
                    Layout.fillWidth: true
                    icon: "search"
                    placeholder: I18n.tr("Например, Москва")
                    text: Weather.city
                    onAccepted: v => { Settings.set("weather.city", v.trim()); root.editCity = false; }
                }
                Btn { text: I18n.tr("Найти"); kind: "accent"; implicitHeight: 32; onClicked: { Settings.set("weather.city", cityField.text.trim()); root.editCity = false; } }
            }
        }

        Label {
            visible: Weather.city.length > 0 && !root.cur
            Layout.fillWidth: true
            text: Weather.loading ? "Загрузка…" : Weather.error.length ? Weather.error : "нет данных"
            tone: 3
            wrapMode: Text.WordWrap
        }

        // ---- сейчас ----
        RowLayout {
            visible: root.cur !== null
            Layout.fillWidth: true
            spacing: 14
            Sym {
                name: root.cur ? root.cur.icon : "cloud"
                size: 56
                color: Weather.iconColor(name, Theme.fg)
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                Label { text: root.cur ? Weather.temp(root.cur.temp) : ""; size: "display" }
                Label { text: root.cur ? root.cur.text : ""; tone: 2 }
            }
            ColumnLayout {
                spacing: 2
                Layout.alignment: Qt.AlignRight
                Label { Layout.alignment: Qt.AlignRight; text: root.cur ? "Ощущается " + Weather.temp(root.cur.feels) : ""; size: "small"; tone: 2 }
                Label { Layout.alignment: Qt.AlignRight; text: root.cur ? "Влажность " + Math.round(root.cur.humidity) + "%" : ""; size: "small"; tone: 3 }
                Label { Layout.alignment: Qt.AlignRight; text: root.cur ? "Ветер " + Math.round(root.cur.wind) + " " + Weather.windUnit : ""; size: "small"; tone: 3 }
            }
        }

        // ---- по часам ----
        Rectangle {
            visible: root.cur !== null
            Layout.fillWidth: true
            implicitHeight: hours.implicitHeight + 20
            radius: Theme.radius - 6
            color: Theme.soft
            border.color: Theme.line
            border.width: 1
            Row {
                id: hours
                anchors.centerIn: parent
                width: parent.width - 16
                Repeater {
                    model: Weather.hourly.filter((h, i) => i % 2 === 0).slice(0, 7)
                    delegate: Column {
                        id: hc
                        required property var modelData
                        required property int index
                        width: hours.width / 7
                        spacing: 6
                        Label { anchors.horizontalCenter: parent.horizontalCenter; text: hc.index === 0 ? "Сейчас" : hc.modelData.hour; size: "caption"; tone: 3 }
                        Sym { anchors.horizontalCenter: parent.horizontalCenter; name: hc.modelData.icon; size: 20; color: Weather.iconColor(name, Theme.fg) }
                        Label { anchors.horizontalCenter: parent.horizontalCenter; text: Weather.temp(hc.modelData.temp); size: "small"; font.weight: Font.DemiBold }
                    }
                }
            }
        }

        // ---- 5 дней ----
        ColumnLayout {
            id: days
            visible: root.cur !== null
            Layout.fillWidth: true
            spacing: 2
            readonly property var list: Weather.daily.slice(0, 5)
            readonly property real lo: Math.min.apply(null, list.map(d => d.min).concat([100]))
            readonly property real hi: Math.max.apply(null, list.map(d => d.max).concat([-100]))
            Repeater {
                model: days.list
                delegate: RowLayout {
                    id: dr
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10
                    Label { text: dr.modelData.name; Layout.preferredWidth: 72 }
                    Sym { name: dr.modelData.icon; size: 20; color: Weather.iconColor(name, Theme.fg) }
                    Label { text: Weather.temp(dr.modelData.min); tone: 3; size: "small"; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 38 }
                    // полоса диапазона температур дня на общей шкале пяти дней
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 6
                        Rectangle { anchors.fill: parent; radius: 3; color: Theme.soft2 }
                        Rectangle {
                            readonly property real span: Math.max(1, days.hi - days.lo)
                            x: parent.width * (dr.modelData.min - days.lo) / span
                            width: Math.max(height, parent.width * (dr.modelData.max - dr.modelData.min) / span)
                            height: parent.height
                            radius: 3
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: "#2BC4F0" }
                                GradientStop { position: 1; color: Theme.accents[4] }
                            }
                        }
                    }
                    Label { text: Weather.temp(dr.modelData.max); size: "small"; font.weight: Font.DemiBold; Layout.preferredWidth: 38 }
                }
            }
        }

        Label {
            visible: root.cur !== null
            text: I18n.tr("Данные: Open-Meteo")
            size: "caption"
            tone: 3
        }
    }
}
