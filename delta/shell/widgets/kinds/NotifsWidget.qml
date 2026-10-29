pragma ComponentBehavior: Bound

import QtQuick
import qs.common
import qs.common.ui
import qs.widgets.parts

// Уведомления на экране блокировки: последние из ShellState.notifications
// (их публикует notify/). Сколько строк влезает — зависит от высоты виджета.
Base {
    id: root

    readonly property bool allowed: Settings.get("notifications.onLock", true)
    readonly property var list: allowed ? (ShellState.notifications || []) : []
    readonly property real rowH: Math.max(44, Math.min(25 * ch, 15 * cw))
    readonly property real gap: rowH * 0.12
    readonly property int fit: Math.max(1, Math.floor((height - head.height - gap) / (rowH + gap)))
    readonly property int more: Math.max(0, list.length - fit)

    function plain(t) { return String(t || "").replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim(); }
    function ago(t) {
        const m = Math.round((Date.now() - (t || Date.now())) / 60000);
        if (m < 1) return I18n.tr("сейчас");
        if (m < 60) return m + " " + I18n.tr("мин");
        const h = Math.round(m / 60);
        return h < 24 ? h + " " + I18n.tr("ч") : Qt.formatDate(new Date(t), "d.MM");
    }
    // цвет значка приложения — из имени, чтобы у каждого был свой
    function hue(name) { let h = 0; for (const c of String(name)) h = (h * 31 + c.charCodeAt(0)) % 360; return h / 360; }

    Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        visible: root.mode !== "count"
        spacing: root.gap

        // шапка: колокольчик, «Уведомления», счётчик
        Row {
            id: head
            spacing: root.rowH * 0.14
            Sym {
                anchors.verticalCenter: parent.verticalCenter
                name: "bell"
                size: Math.round(root.rowH * 0.3)
                color: root.pal.c1
            }
            WText {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Уведомления")
                px: root.rowH * 0.26
                font.weight: Font.Bold
                color: root.pal.c1
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.list.length > 0
                width: Math.max(height, cnt.implicitWidth + height * 0.7)
                height: root.rowH * 0.36
                radius: height / 2
                color: Theme.accent
                WText { id: cnt; anchors.centerIn: parent; text: root.list.length; px: parent.height * 0.62; font.weight: Font.Bold; color: Theme.onAccent }
            }
        }

        Repeater {
            model: root.list.slice(0, root.fit)
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property string app: row.modelData.app || "?"
                width: parent.width
                height: root.rowH
                radius: Math.min(height * 0.32, 22)
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.20) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.11) }
                }
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.16)

                // въезжают по очереди
                opacity: 0
                transform: Translate { id: rowShift; x: 24 }
                Component.onCompleted: rowIn.start()
                ParallelAnimation {
                    id: rowIn
                    NumberAnimation { target: row; property: "opacity"; to: 1; duration: 380; easing.type: Easing.OutCubic }
                    SequentialAnimation {
                        PauseAnimation { duration: 60 * row.index }
                        NumberAnimation { target: rowShift; property: "x"; to: 0; duration: 560; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
                    }
                }

                // значок приложения: первая буква на своём цвете
                Rectangle {
                    id: badge
                    anchors { left: parent.left; leftMargin: root.rowH * 0.18; verticalCenter: parent.verticalCenter }
                    width: root.rowH * 0.56; height: width
                    radius: width * 0.3
                    color: Qt.hsla(root.hue(row.app), 0.55, 0.55, 1)
                    WText {
                        anchors.centerIn: parent
                        text: row.app.charAt(0).toUpperCase()
                        px: parent.height * 0.5
                        font.weight: Font.ExtraBold
                        color: "#ffffff"
                    }
                }
                Column {
                    anchors { left: badge.right; leftMargin: root.rowH * 0.18; right: parent.right; rightMargin: root.rowH * 0.22; verticalCenter: parent.verticalCenter }
                    spacing: root.rowH * 0.03
                    Item {
                        width: parent.width
                        height: sum.height
                        WText {
                            id: sum
                            anchors.left: parent.left
                            width: parent.width - when.width - root.rowH * 0.15
                            text: row.modelData.summary || row.app
                            px: root.rowH * 0.24
                            font.weight: Font.Bold
                            color: root.pal.c1
                        }
                        WText {
                            id: when
                            anchors { right: parent.right; verticalCenter: sum.verticalCenter }
                            text: root.ago(row.modelData.time)
                            px: root.rowH * 0.19
                            color: root.pal.c1
                            opacity: 0.6
                        }
                    }
                    WText {
                        width: parent.width
                        visible: text.length > 0
                        text: root.plain(row.modelData.body)
                        px: root.rowH * 0.21
                        color: root.pal.c1
                        opacity: 0.78
                    }
                }
            }
        }
        WText {
            visible: root.more > 0
            text: "+" + root.more + " " + I18n.tr("ещё")
            px: root.rowH * 0.2
            color: root.pal.c1
            opacity: 0.7
        }
        WText {
            visible: root.list.length === 0
            text: root.allowed ? I18n.tr("Новых уведомлений нет") : I18n.tr("Скрыты в настройках")
            px: root.rowH * 0.24
            color: root.pal.c1
            opacity: 0.75
        }
    }

    // «Счётчик»: крупное число и последнее уведомление
    Row {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        visible: root.mode === "count"
        spacing: 5 * root.cm

        WText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.list.length
            px: Math.min(40 * root.ch, 17 * root.cw)
            display: true
            font.weight: Font.ExtraBold
            color: root.pal.c1
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Math.min(40 * root.ch, 17 * root.cw) - parent.spacing
            WText {
                width: parent.width
                text: root.allowed ? I18n.tr("Уведомления") : I18n.tr("Скрыты")
                px: Math.min(12 * root.ch, 5 * root.cw)
                font.weight: Font.Bold
                color: root.pal.c1
                opacity: 0.85
            }
            WText {
                width: parent.width
                text: root.list.length
                    ? ((root.list[0].summary || root.list[0].app || "") + (root.list[0].body ? " · " + root.list[0].body : ""))
                    : I18n.tr("Новых нет")
                px: Math.min(11 * root.ch, 4.4 * root.cw)
                color: root.pal.c1
                opacity: 0.7
            }
        }
    }
}
