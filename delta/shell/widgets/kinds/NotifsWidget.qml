pragma ComponentBehavior: Bound

import QtQuick
import qs.common
import qs.common.ui
import qs.widgets.parts

// Уведомления на экране блокировки и рабочем столе: последние из ShellState.notifications
// (их публикует notify/). Три вида (item.mode):
//   stack — стопкой, как в iOS: видна верхняя карточка, под ней края
//           следующих; нажатие раскладывает стопку в список и обратно;
//   list  — списком, карточки друг под другом;
//   count — числом: «3 уведомления» и от каких приложений.
// Снизу маленькая кнопка «Очистить». item.quiet — без уведомлений виджета
// не видно совсем (надпись «Новых нет» не показываем).
Base {
    id: root

    // на экране блокировки — если их там разрешили показывать
    readonly property bool allowed: !lock || Settings.get("notifications.onLock", true)
    // цвет карточек: на стекле рабочего стола — из темы, иначе белый
    readonly property color ink: pal.c1
    readonly property var list: allowed ? (ShellState.notifications || []) : []
    readonly property bool quiet: !!item && item.quiet === true
    // для WidgetCard: показывать нечего — карточка прячется
    readonly property bool empty: quiet && list.length === 0
    readonly property bool counter: mode === "count"
    readonly property bool stacked: mode === "stack" || (mode !== "list" && mode !== "count")

    // без карточки (экран блокировки сам по себе) строка задаётся снаружи —
    // тогда и высоту виджета можно взять по содержимому (implicitHeight)
    property real fixedRow: 0
    readonly property real rowH: fixedRow > 0 ? fixedRow : Math.max(44, Math.min(25 * ch, 18 * cw, 96))
    readonly property real gap: rowH * 0.12
    // край карточки под верхней в стопке
    readonly property real peek: rowH * 0.14
    readonly property real clearH: list.length > 0 && !editing ? Math.max(20, rowH * 0.4) : 0
    // у «Числом» кнопка справа, у карточек — снизу
    readonly property real cardsH: height - head.height - gap - (clearH > 0 && !counter ? clearH + gap : 0)
    readonly property int fit: Math.max(1, Math.floor((cardsH + gap) / (rowH + gap)))

    // стопка разложена
    property bool open: false
    readonly property bool spread: !stacked || open
    onListChanged: if (list.length < 2) open = false
    onModeChanged: open = false
    readonly property int shown: spread ? Math.min(list.length, fit) : Math.min(list.length, 3)
    readonly property int more: Math.max(0, list.length - (spread ? fit : 1))
    implicitHeight: counter ? rowH * 1.4
        : head.height + gap + (spread ? Math.min(list.length, 6) * (rowH + gap) + rowH * 0.3 : rowH + 2 * peek + gap)
          + (clearH > 0 ? clearH + gap : 0)

    function plain(t) { return String(t || "").replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim(); }
    function ago(t) {
        const m = Math.round((Date.now() - (t || Date.now())) / 60000);
        if (m < 1) return I18n.tr("сейчас");
        if (m < 60) return m + " " + I18n.tr("мин");
        const h = Math.round(m / 60);
        return h < 24 ? h + " " + I18n.tr("ч") : Qt.formatDate(new Date(t), "d.MM");
    }
    // 1 уведомление, 3 уведомления, 7 уведомлений
    function noun(n) {
        const a = n % 10, b = n % 100;
        return I18n.tr(a === 1 && b !== 11 ? "уведомление" : a >= 2 && a <= 4 && (b < 12 || b > 14) ? "уведомления" : "уведомлений");
    }
    // «Telegram, Firefox и ещё 2»
    readonly property string apps: {
        const names = [];
        for (const n of list) {
            const a = n.app || n.summary || "";
            if (a && names.indexOf(a) < 0) names.push(a);
        }
        if (names.length <= 2) return names.join(", ");
        return names.slice(0, 2).join(", ") + " " + I18n.tr("и ещё") + " " + (names.length - 2);
    }
    // цвет значка приложения — из имени, чтобы у каждого был свой
    function hue(name) { let h = 0; for (const c of String(name)) h = (h * 31 + c.charCodeAt(0)) % 360; return h / 360; }

    function toggle() {
        if (!stacked || list.length < 2) return;
        open = !open;
        Sounds.play(open ? "pop" : "drop", 60);
    }

    // шапка: колокольчик, «Уведомления», счётчик; в разложенной стопке — «свернуть»
    Row {
        id: head
        visible: !root.counter && !root.empty
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
    // «свернуть» — справа от шапки
    Rectangle {
        anchors { right: parent.right; verticalCenter: head.verticalCenter }
        visible: root.stacked && root.open && !root.editing
        width: fold.implicitWidth + height * 0.9
        height: root.rowH * 0.4
        radius: height / 2
        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, foldTap.pressed ? 0.3 : 0.16)
        WText { id: fold; anchors.centerIn: parent; text: I18n.tr("Свернуть"); px: parent.height * 0.48; font.weight: Font.DemiBold; color: root.pal.c1 }
        TapHandler { id: foldTap; onTapped: root.toggle() }
    }

    // карточки: и стопка, и список — одни и те же, меняется только раскладка
    Item {
        id: cards
        visible: !root.counter
        anchors { left: parent.left; right: parent.right; top: head.bottom; topMargin: root.gap }
        height: root.cardsH

        TapHandler {
            enabled: !root.editing && root.stacked && !root.open && root.list.length > 1
            onTapped: root.toggle()
        }

        Repeater {
            model: root.list.slice(0, Math.max(root.fit, 3))
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property string app: row.modelData.app || "?"
                readonly property bool inStack: !root.spread
                readonly property bool live: row.index < root.shown

                width: cards.width
                height: root.rowH
                z: -row.index
                radius: Math.min(height * 0.32, 22)
                transformOrigin: Item.Bottom
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, row.inStack && row.index > 0 ? 0.16 : 0.22) }
                    GradientStop { position: 1; color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, row.inStack && row.index > 0 ? 0.10 : 0.13) }
                }
                border.width: 1
                border.color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.16)

                // стопка: карточки под верхней выглядывают краем снизу
                y: row.inStack ? row.index * root.peek : row.index * (root.rowH + root.gap)
                scale: row.inStack ? 1 - row.index * 0.06 : 1
                opacity: (row.live ? (row.inStack ? 1 - row.index * 0.22 : 1) : 0) * row.enter
                Behavior on y { NumberAnimation { duration: 420 + row.index * 45; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }
                Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 260 } }

                // въезжают по очереди
                property real enter: 0
                transform: Translate { id: rowShift; x: 24 }
                Component.onCompleted: rowIn.start()
                ParallelAnimation {
                    id: rowIn
                    NumberAnimation { target: row; property: "enter"; to: 1; duration: 380; easing.type: Easing.OutCubic }
                    SequentialAnimation {
                        PauseAnimation { duration: 60 * row.index }
                        NumberAnimation { target: rowShift; property: "x"; to: 0; duration: 560; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
                    }
                }

                Item {
                    anchors.fill: parent
                    // у нижних карточек стопки видна только кромка
                    opacity: row.inStack && row.index > 0 ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 220 } }

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
                            text: row.inStack && root.list.length > 1
                                ? I18n.tr("Ещё") + " " + (root.list.length - 1) + " · " + I18n.tr("нажмите, чтобы раскрыть")
                                : root.plain(row.modelData.body)
                            px: root.rowH * 0.21
                            color: root.pal.c1
                            opacity: 0.78
                        }
                    }
                }
            }
        }

        WText {
            visible: root.spread && root.more > 0
            y: Math.min(root.fit, root.list.length) * (root.rowH + root.gap) - root.gap * 0.5
            text: "+" + root.more + " " + I18n.tr("ещё")
            px: root.rowH * 0.2
            color: root.pal.c1
            opacity: 0.7
        }
        WText {
            visible: root.list.length === 0 && !root.quiet
            text: root.allowed ? I18n.tr("Новых уведомлений нет") : I18n.tr("Скрыты в настройках")
            px: root.rowH * 0.24
            color: root.pal.c1
            opacity: 0.75
        }
    }

    // «Числом»: «3 уведомления» и от кого
    Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - (clearBtn.visible ? clearBtn.width + root.gap : 0)
        visible: root.counter && !root.empty
        spacing: 1.5 * root.cm

        Row {
            id: countRow
            spacing: 3 * root.cm
            Sym {
                id: countIcon
                anchors.verticalCenter: parent.verticalCenter
                name: root.list.length ? "bell" : "bell-off"
                size: Math.round(Math.min(22 * root.ch, 9 * root.cw))
                color: root.pal.c1
            }
            WText {
                anchors.verticalCenter: parent.verticalCenter
                text: !root.allowed ? I18n.tr("Скрыты в настройках")
                    : root.list.length ? root.list.length + " " + root.noun(root.list.length)
                    : I18n.tr("Новых уведомлений нет")
                px: Math.min(20 * root.ch, 7.5 * root.cw)
                width: Math.min(implicitWidth, countRow.parent.width - countIcon.width - countRow.spacing)
                elide: Text.ElideRight
                display: true
                font.weight: Font.Bold
                color: root.pal.c1
            }
        }
        WText {
            width: parent.width
            visible: root.list.length > 0
            text: root.apps
            px: Math.min(12 * root.ch, 4.6 * root.cw)
            color: root.pal.c1
            opacity: 0.72
        }
    }

    // маленькая «Очистить» почти у нижнего края
    Rectangle {
        id: clearBtn
        anchors.horizontalCenter: root.counter ? undefined : parent.horizontalCenter
        anchors.bottom: root.counter ? undefined : parent.bottom
        anchors.right: root.counter ? parent.right : undefined
        anchors.verticalCenter: root.counter ? parent.verticalCenter : undefined
        visible: root.clearH > 0
        width: clearRow.implicitWidth + height * 1.1
        height: root.clearH
        radius: height / 2
        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, clearTap.pressed ? 0.32 : 0.16)
        border.width: 1
        border.color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.14)
        Row {
            id: clearRow
            anchors.centerIn: parent
            spacing: parent.height * 0.2
            Sym { anchors.verticalCenter: parent.verticalCenter; name: "close"; size: Math.round(parent.parent.height * 0.42); color: root.pal.c1 }
            WText { anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Очистить"); px: parent.parent.height * 0.46; font.weight: Font.DemiBold; color: root.pal.c1 }
        }
        TapHandler {
            id: clearTap
            onTapped: {
                root.open = false;
                ShellState.clearNotifications();
                Sounds.play("swoosh", 60);
            }
        }
    }
}
