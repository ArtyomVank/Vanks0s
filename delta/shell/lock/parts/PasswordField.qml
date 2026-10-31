import QtQuick
import qs.common
import qs.common.ui

// Поле пароля экрана блокировки и входа: «пилюля» с точками и кнопкой «Войти».
// shake() — встряхнуть при ошибке, busy — идёт проверка (вместо стрелки крутится круг).
//     PasswordField { onSubmitted: pw => auth.submit(pw) }
Rectangle {
    id: root

    property bool busy: false
    property string placeholder: I18n.tr("Пароль")
    property bool echo: false       // PAM может попросить ввод, который видно (например, код)
    readonly property alias text: input.text
    signal submitted(string text)

    function clear() { input.text = ""; }
    function focusInput() { input.forceActiveFocus(); }
    function shake() { shakeAnim.restart(); }

    implicitWidth: 300
    implicitHeight: 46
    radius: height / 2
    color: Qt.rgba(1, 1, 1, input.activeFocus ? 0.18 : 0.14)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, input.activeFocus ? 0.32 : 0.18)
    Behavior on color { ColorAnimation { duration: Theme.anim.fast } }

    // смещение для встряски — отдельно от x, чтобы не спорить с раскладкой
    transform: Translate { id: shift }
    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: shift; property: "x"; to: -14; duration: 50; easing.type: Easing.OutQuad }
        NumberAnimation { target: shift; property: "x"; to: 12; duration: 80; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shift; property: "x"; to: -8; duration: 70; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shift; property: "x"; to: 5; duration: 60; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shift; property: "x"; to: 0; duration: 60; easing.type: Easing.OutQuad }
    }

    TextInput {
        id: input
        anchors { left: parent.left; right: go.left; verticalCenter: parent.verticalCenter; leftMargin: 20; rightMargin: 10 }
        echoMode: root.echo ? TextInput.Normal : TextInput.Password
        passwordCharacter: "•"
        passwordMaskDelay: 0
        color: "#ffffff"
        selectionColor: Theme.accent
        font.family: Theme.font
        font.pixelSize: root.echo ? 17 : 20
        font.letterSpacing: root.echo ? 0 : 3
        clip: true
        focus: true
        readOnly: root.busy
        cursorDelegate: Rectangle {
            width: 2
            color: "#ffffff"
            visible: input.activeFocus && !root.busy
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: input.activeFocus
                NumberAnimation { to: 0; duration: 500 * Theme.anim.k; easing.type: Easing.InQuad }
                NumberAnimation { to: 1; duration: 500 * Theme.anim.k; easing.type: Easing.OutQuad }
            }
        }
        onAccepted: if (!root.busy && text.length) root.submitted(text)
        Keys.onEscapePressed: text = ""

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text.length === 0
            leftPadding: 4
            text: root.placeholder
            color: Qt.rgba(1, 1, 1, 0.55)
            font.family: Theme.font
            font.pixelSize: 15
        }
    }

    // кнопка «Войти»: белый круг со стрелкой
    Rectangle {
        id: go
        anchors { right: parent.right; rightMargin: 7; verticalCenter: parent.verticalCenter }
        width: 32
        height: 32
        radius: 16
        color: "#ffffff"
        opacity: input.text.length || root.busy ? 1 : 0.55
        scale: goTap.pressed ? 0.9 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.anim.fast } }
        Behavior on scale { NumberAnimation { duration: Theme.anim.fast } }

        Sym {
            anchors.centerIn: parent
            visible: !root.busy
            name: "arrow-right"
            size: 16
            color: Theme.inv
        }
        // круг ожидания
        Rectangle {
            anchors.centerIn: parent
            visible: root.busy
            width: 16
            height: 16
            radius: 8
            color: "transparent"
            border.width: 2
            border.color: Qt.rgba(0, 0, 0, 0.18)
            Rectangle {
                width: 6; height: 6; radius: 3
                color: Theme.inv
                x: 5 + 6 * Math.cos(spin.a)
                y: 5 + 6 * Math.sin(spin.a)
            }
            QtObject {
                id: spin
                property real a: 0
                NumberAnimation on a { from: 0; to: Math.PI * 2; duration: 900 * Theme.anim.k; loops: Animation.Infinite; running: root.busy }
            }
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler {
            id: goTap
            onTapped: if (!root.busy && input.text.length) root.submitted(input.text)
        }
    }
}
