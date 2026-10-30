pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.common
import qs.common.ui
import qs.lock.parts
import qs.widgets.kinds

// Содержимое экрана блокировки — общее для блокировки (WlSessionLockSurface),
// экрана входа (greeter.qml) и предпросмотра при редактировании виджетов.
//
//   mode: "lock" · "greeter" · "edit"
//   auth: объект проверки пароля (см. Lock.qml и greeter/Backend.qml):
//         busy, message, isError, prompt, echo, submit(text), сигнал failed()
//
// Анимация входа (enter) и разблокировки (playExit) — как в концепте:
// кольцо от поля пароля, часы улетают вверх, вход уезжает вниз, размытие тает.
Item {
    id: root

    property string mode: "lock"
    property var screen: null
    property QtObject auth: null
    property bool showLogin: true            // поле пароля — только на одном мониторе
    property string userName: ""
    property string avatar: ""
    property int avatarRevision: 0
    property bool canSwitchUser: false
    property Component loginExtra: null      // дополнительные чипы под полем (сессии на экране входа)
    property var powerButtons: ["suspend", "reboot", "poweroff"]
    // перед появлением видно рабочий стол (session_lock_xray): чёткие обои проявляются, а не стоят сразу
    property bool fromDesktop: false
    // в конце разблокировки чёткие обои тоже гаснут — под ними уже рабочий стол
    property bool toDesktop: false

    signal prevUser()
    signal nextUser()
    signal power(string action)
    signal editDone()

    readonly property bool editing: mode === "edit"
    // низкий экран (ноутбук с масштабом 200 %) — аватар меньше, чтобы не наезжать на часы
    readonly property int avatarSize: height < 600 ? 56 : 80
    readonly property bool greeter: mode === "greeter"

    // ---------- настройки ----------
    readonly property string clockStyle: Settings.get("lock.clock.style", Settings.get("clock.style", "ios"))
    readonly property string clockTint: Settings.get("lock.clock.color", Settings.get("clock.color", "white"))
    readonly property bool notifOn: mode === "lock" && Settings.get("notifications.onLock", true)
    readonly property bool gridOn: !greeter || Settings.get("greeter.widgets", true)
    readonly property var lockWidgets: Settings.get("widgets.lock", [])

    // ---------- сетка виджетов (модуль D) ----------
    // Файла может ещё не быть — тогда сетки просто нет. FileView без ошибок в журнале
    // говорит, существует ли он, и следит за появлением.
    readonly property string gridUrl: Quickshell.shellDir + "/widgets/WidgetGrid.qml"
    FileView {
        id: gridFile
        path: root.gridUrl
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
    }
    readonly property bool gridReady: gridLoader.status === Loader.Ready
    // часы рисует сетка, если в раскладке экрана блокировки есть виджет «clock»
    readonly property bool gridHasClock: gridReady && Array.isArray(lockWidgets) && lockWidgets.some(w => w && w.id === "clock")
    readonly property bool gridHasNotifs: gridReady && Array.isArray(lockWidgets) && lockWidgets.some(w => w && (w.id === "notifs" || w.id === "notifications"))

    function focusField() { if (field.visible) field.focusInput(); }

    // ---------- фон ----------
    LockBackground {
        id: bg
        anchors.fill: parent
        blurred: 0
        sharp: root.fromDesktop ? 0 : 1
    }

    // клик мимо элементов — вернуть фокус в поле пароля
    TapHandler { onTapped: root.focusField() }

    // ---------- сетка виджетов ----------
    Loader {
        id: gridLoader
        anchors.fill: parent
        active: root.gridOn && gridFile.loaded
        asynchronous: true
        visible: status === Loader.Ready
        // place: "lock" — раскладка widgets.lock; unlocking — для своей анимации часов в сетке
        Component.onCompleted: setSource(root.gridUrl, { place: "lock" })
        onLoaded: {
            if ("screen" in item) item.screen = Qt.binding(() => root.screen);
            if ("unlocking" in item) item.unlocking = Qt.binding(() => exitAnim.running);
            // редактор сетки (панель и «Готово») рисует сама сетка
            if ("editing" in item) item.editing = Qt.binding(() => root.editing);
            if (item.finished) item.finished.connect(root.editDone);
        }
        transform: [
            Scale { id: gridScale; origin.x: gridLoader.width / 2; origin.y: gridLoader.height / 2 },
            Translate { id: gridShift }
        ]
        layer.enabled: exitAnim.running
        layer.effect: MultiEffect { blurEnabled: true; blur: gridBlur.v; blurMax: 20 }
        QtObject { id: gridBlur; property real v: 0 }
    }

    // ---------- часы (если их нет в сетке) ----------
    Item {
        id: clockBox
        visible: !root.gridHasClock
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(root.height * 0.095)
        width: bigClock.implicitWidth
        height: bigClock.implicitHeight
        transform: [
            Scale { id: clockScale; origin.x: clockBox.width / 2; origin.y: clockBox.height / 2 },
            Translate { id: clockShift }
        ]
        BigClock {
            id: bigClock
            anchors.horizontalCenter: parent.horizontalCenter
            style: root.clockStyle
            tint: root.clockTint
            tallWidth: Number(Settings.get("lock.clock.tallWidth", Settings.get("clock.tallWidth", 0.62))) || 0.62
            tallKind: Settings.get("lock.clock.tallKind", Settings.get("clock.tallKind", "line"))
            tallThick: Number(Settings.get("lock.clock.tallThick", Settings.get("clock.tallThick", 1))) || 1
            size: Math.min(152, root.width * 0.105, root.height * 0.19)
        }
    }

    // ---------- уведомления ----------
    // виджета «Уведомления» на сетке нет — тот же виджет без карточки, по
    // центру под часами, как в iOS; вид (стопкой, списком, числом) —
    // notifications.lockView. Высота — по содержимому, но не до поля пароля.
    NotifsWidget {
        id: notes
        visible: root.notifOn && !root.gridHasNotifs && !root.editing && list.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(root.height * 0.38)
        width: Math.min(420, root.width * 0.34)
        height: Math.max(80, Math.min(implicitHeight, login.y - y - 24))
        fixedRow: 64
        item: ({ id: "notifs", mode: Settings.get("notifications.lockView", "stack") })
    }

    // ---------- вход ----------
    Item {
        id: login
        visible: root.showLogin && !root.editing
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Math.round(root.height * 0.09) }
        width: 420
        height: loginCol.implicitHeight
        transform: [
            Scale { id: loginScale; origin.x: login.width / 2; origin.y: login.height / 2 },
            Translate { id: loginShift }
        ]

        Column {
            id: loginCol
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.avatarSize + 2 * 56
                height: root.avatarSize
                GlassBtn {
                    visible: root.canSwitchUser
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    icon: "chevron-left"; size: 34
                    onClicked: root.prevUser()
                }
                Avatar {
                    anchors.centerIn: parent
                    size: root.avatarSize
                    ring: 3
                    source: root.avatar
                    name: root.userName
                    revision: root.avatarRevision
                }
                GlassBtn {
                    visible: root.canSwitchUser
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    icon: "chevron-right"; size: 34
                    onClicked: root.nextUser()
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.userName
                color: "#ffffff"
                font.family: Theme.font
                font.pixelSize: 18
                font.weight: Font.Bold
            }

            PasswordField {
                id: field
                anchors.horizontalCenter: parent.horizontalCenter
                busy: root.auth ? root.auth.busy === true : false
                echo: root.auth ? root.auth.echo === true : false
                placeholder: root.auth && root.auth.prompt ? root.auth.prompt : "Пароль"
                onSubmitted: text => { if (root.auth) root.auth.submit(text); }
                Keys.onReleased: e => {
                    if (e.key === Qt.Key_CapsLock) Keyboard.refreshSoon();
                }
            }

            // сообщение PAM / ошибка / Caps Lock
            Text {
                id: msg
                anchors.horizontalCenter: parent.horizontalCenter
                width: 380
                height: 18
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                readonly property string pam: root.auth && root.auth.message ? root.auth.message : ""
                text: pam.length ? pam : Keyboard.capsLock ? "Включён Caps Lock" : ""
                color: root.auth && root.auth.isError && pam.length ? "#ffb3b3" : "#ffffff"
                opacity: text.length ? 0.9 : 0
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.Medium
                Behavior on opacity { NumberAnimation { duration: Theme.anim.fast } }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                GlassBtn {
                    visible: Keyboard.layout.length > 0
                    icon: "keyboard"
                    text: Keyboard.layout
                    onClicked: { Keyboard.next(); root.focusField(); }
                }
                GlassBtn {
                    visible: Keyboard.capsLock
                    icon: "caps-lock"
                    text: "Caps"
                    active: true
                }
                Loader {
                    active: root.loginExtra !== null
                    sourceComponent: root.loginExtra
                }
            }
        }
    }

    // кольцо разблокировки — из центра поля пароля
    // Растёт сам размер, а не scale: увеличенный в 90 раз круг 20 px рисуется
    // многоугольником, а настоящий круг большого радиуса остаётся гладким.
    Rectangle {
        id: ring
        property point c: Qt.point(0, 0)      // центр задаёт playExit(): mapToItem не пересчитывается сам
        property real r: 10
        x: c.x - r
        y: c.y - r
        width: r * 2
        height: r * 2
        radius: r
        color: "transparent"
        border.width: r / 5                  // толщина растёт вместе с кругом, как scale в концепте
        border.color: "#ffffff"
        opacity: 0
        antialiasing: true
    }

    // ---------- питание ----------
    property string confirm: ""

    Row {
        id: powerRow
        visible: !root.editing && root.showLogin
        anchors { right: parent.right; bottom: parent.bottom; margins: 28 }
        spacing: 12
        Repeater {
            model: root.powerButtons.filter(a => a !== "hibernate" || PowerActions.canHibernate)
            delegate: GlassBtn {
                required property string modelData
                icon: modelData === "suspend" ? "sleep" : modelData === "reboot" ? "restart" : modelData === "poweroff" ? "power" : modelData
                label: PowerActions.labels[modelData] || ""
                active: root.confirm === modelData
                onClicked: {
                    if (PowerActions.needsConfirm(modelData)) root.confirm = root.confirm === modelData ? "" : modelData;
                    else { root.confirm = ""; root.power(modelData); }
                }
            }
        }
    }

    // подтверждение над кнопками
    Rectangle {
        id: confirmBox
        visible: opacity > 0
        opacity: root.confirm.length ? 1 : 0
        scale: root.confirm.length ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: Theme.anim.fast } }
        Behavior on scale { NumberAnimation { duration: Theme.anim.normal; easing.type: Theme.anim.springCurve } }
        anchors { right: powerRow.right; bottom: powerRow.top; bottomMargin: 16 }
        width: confirmCol.implicitWidth + 36
        height: confirmCol.implicitHeight + 32
        radius: 20
        color: Qt.rgba(0.04, 0.03, 0.08, 0.55)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)

        readonly property var questions: ({
            reboot: "Перезагрузить компьютер?", poweroff: "Выключить компьютер?", logout: "Выйти из системы?"
        })
        Column {
            id: confirmCol
            anchors.centerIn: parent
            spacing: 12
            Text {
                text: confirmBox.questions[root.confirm] || ""
                color: "#ffffff"
                font.family: Theme.font
                font.pixelSize: 15
                font.weight: Font.Bold
            }
            Text {
                visible: root.mode === "lock"
                text: I18n.tr("Несохранённые данные в программах пропадут")
                color: "#ffffff"
                opacity: 0.75
                font.family: Theme.font
                font.pixelSize: 12
            }
            Row {
                spacing: 8
                GlassBtn { text: I18n.tr("Отмена"); onClicked: root.confirm = "" }
                GlassBtn {
                    text: PowerActions.labels[root.confirm] || ""
                    active: true
                    onClicked: { const a = root.confirm; root.confirm = ""; root.power(a); }
                }
            }
        }
    }

    // ---------- редактор виджетов экрана блокировки ----------
    // запасная панель — только если сетки виджетов нет (у сетки своя панель редактора)
    Rectangle {
        visible: root.editing && !root.gridReady
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 18 }
        width: editRow.implicitWidth + 24
        height: 48
        radius: 24
        color: Theme.glass2
        border.width: 1
        border.color: Theme.line
        Row {
            id: editRow
            anchors.centerIn: parent
            spacing: 14
            Label { anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Экран блокировки"); font.weight: Font.Bold; leftPadding: 6 }
            Label { anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("сетка виджетов недоступна"); tone: 3; size: "small" }
            Btn { text: I18n.tr("Готово"); kind: "accent"; onClicked: root.editDone() }
        }
    }

    Keys.onEscapePressed: {
        if (root.editing) root.editDone();
        else root.confirm = "";
    }
    // печать в любом месте экрана попадает в поле пароля
    Keys.onPressed: e => {
        if (!root.editing && e.text.length && !field.activeFocus) {
            root.focusField();
            field.forceActiveFocus();
        }
    }
    focus: true

    // ---------- появление ----------
    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: bg; property: "sharp"; to: 1; duration: 320; easing.type: Easing.OutCubic }
        NumberAnimation { target: bg; property: "blurred"; from: 0; to: 1; duration: 620; easing.type: Easing.OutCubic }
        // часы «въезжают» снизу с лёгкой пружиной, как .clockin
        NumberAnimation { target: clockShift; property: "y"; from: 70; to: 0; duration: 900; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
        NumberAnimation { target: clockScale; properties: "xScale,yScale"; from: 1.25; to: 1; duration: 900; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
        NumberAnimation { target: clockBox; property: "opacity"; from: 0; to: 1; duration: 500; easing.type: Easing.OutCubic }
        NumberAnimation { target: gridLoader; property: "opacity"; from: 0; to: 1; duration: 600; easing.type: Easing.OutCubic }
        SequentialAnimation {
            PropertyAction { target: login; property: "opacity"; value: 0 }
            PauseAnimation { duration: 160 }
            ParallelAnimation {
                NumberAnimation { target: login; property: "opacity"; to: 1; duration: 420; easing.type: Easing.OutCubic }
                NumberAnimation { target: loginShift; property: "y"; from: 40; to: 0; duration: 520; easing.type: Easing.OutCubic }
            }
        }
    }

    // ---------- разблокировка: ~820 мс ----------
    // кривая концепта cubic-bezier(.65, 0, .3, 1) ≈ InOutCubic
    readonly property int curve: Easing.InOutCubic
    ParallelAnimation {
        id: exitAnim
        // размытие тает
        NumberAnimation { target: bg; property: "blurred"; to: 0; duration: 850; easing.type: Easing.InOutQuad }
        // под ним — рабочий стол (если композитор показывает его сквозь блокировку)
        SequentialAnimation {
            PauseAnimation { duration: root.toDesktop ? 420 : 0 }
            NumberAnimation { target: bg; property: "sharp"; to: root.toDesktop ? 0 : 1; duration: root.toDesktop ? 420 : 0; easing.type: Easing.InOutQuad }
        }
        // часы улетают вверх и уменьшаются
        NumberAnimation { target: clockShift; property: "y"; to: -200; duration: 850; easing.type: root.curve }
        NumberAnimation { target: clockScale; properties: "xScale,yScale"; to: 0.35; duration: 850; easing.type: root.curve }
        SequentialAnimation {
            PauseAnimation { duration: 200 }
            NumberAnimation { target: clockBox; property: "opacity"; to: 0; duration: 600; easing.type: Easing.InOutQuad }
        }
        // вход уезжает вниз
        NumberAnimation { target: loginShift; property: "y"; to: 170; duration: 700; easing.type: root.curve }
        NumberAnimation { target: loginScale; properties: "xScale,yScale"; to: 0.9; duration: 700; easing.type: root.curve }
        NumberAnimation { target: login; property: "opacity"; to: 0; duration: 450; easing.type: Easing.InOutQuad }
        // виджеты сжимаются и расплываются
        NumberAnimation { target: gridScale; properties: "xScale,yScale"; to: 0.6; duration: 600; easing.type: root.curve }
        NumberAnimation { target: gridShift; property: "y"; to: -40; duration: 600; easing.type: root.curve }
        NumberAnimation { target: gridLoader; property: "opacity"; to: 0; duration: 450; easing.type: Easing.InOutQuad }
        NumberAnimation { target: gridBlur; property: "v"; to: 1; duration: 500 }
        NumberAnimation { targets: [notes, powerRow]; property: "opacity"; to: 0; duration: 300 }
        // кольцо расходится от поля пароля
        NumberAnimation { target: ring; property: "r"; from: 10; to: 900; duration: 900; easing.type: Easing.OutQuad }
        NumberAnimation { target: ring; property: "opacity"; from: 0.9; to: 0; duration: 900; easing.type: Easing.OutQuad }
    }

    function playEnter() { enterAnim.restart(); }
    function playExit() {
        enterAnim.stop();
        confirm = "";
        ring.c = login.visible ? field.mapToItem(root, field.width / 2, field.height / 2) : Qt.point(width / 2, height * 0.8);
        exitAnim.restart();
    }
    // вернуть всё на место (после предпросмотра анимации или неудачного запуска сессии)
    function reset() {
        exitAnim.stop();
        enterAnim.stop();
        bg.blurred = 1; bg.sharp = 1;
        clockShift.y = 0; clockScale.xScale = 1; clockScale.yScale = 1; clockBox.opacity = 1;
        loginShift.y = 0; loginScale.xScale = 1; loginScale.yScale = 1; login.opacity = 1;
        gridScale.xScale = 1; gridScale.yScale = 1; gridShift.y = 0; gridLoader.opacity = 1; gridBlur.v = 0;
        notes.opacity = 1; powerRow.opacity = 1; ring.opacity = 0; ring.r = 10;
        field.clear();
        focusField();
    }

    Connections {
        target: root.auth
        ignoreUnknownSignals: true
        function onFailed() { field.shake(); field.clear(); root.focusField(); }
    }

    Component.onCompleted: {
        Keyboard.refresh();
        playEnter();
        focusField();
    }
}
