pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Polkit
import qs.common
import qs.common.ui
import qs.lock.parts

// Агент polkit в стиле Delta: окно «Нужно подтверждение», когда программа
// просит прав администратора (смена имени компьютера, установка, pkexec…).
//
// Агент на сеанс один. Во вложенной сессии он не регистрируется (сеанс logind
// общий с основной), если не задано DELTA_DEV_POLKIT=1; окно там проверяют
// пробным запросом: delta-shell ipc call polkit demo
Scope {
    id: root

    readonly property bool nested: (Quickshell.env("DELTA_NESTED") || "") !== ""
    readonly property bool register: !nested || Quickshell.env("DELTA_DEV_POLKIT") === "1"

    LazyLoader {
        id: agentLoader
        active: root.register
        component: PolkitAgent {}
    }
    readonly property var agent: agentLoader.item
    readonly property var real: agent && agent.isActive ? agent.flow : null
    readonly property var flow: demo.active ? demo : real
    readonly property bool open: flow !== null && !(flow.isCompleted ?? false)

    // --- пробный запрос (без polkit) ----------------------------------------
    QtObject {
        id: demo
        property bool active: false
        property string message: "Чтобы изменить имя компьютера, нужен пароль администратора."
        property string actionId: "org.freedesktop.hostname1.set-static-hostname"
        property string iconName: ""
        property var identities: [{ displayName: Quickshell.env("USER") || "user" }]
        property var selectedIdentity: identities[0]
        property bool isResponseRequired: true
        property string inputPrompt: "Пароль:"
        property bool responseVisible: false
        property string supplementaryMessage: ""
        property bool supplementaryIsError: false
        property bool isCompleted: false
        signal authenticationFailed()
        // пароль в пробном режиме — «delta»
        function submit(v) {
            if (v === "delta") { active = false; console.info("[delta] polkit (проверка): разрешено"); return; }
            supplementaryMessage = "Неверный пароль, попробуйте ещё раз";
            supplementaryIsError = true;
            authenticationFailed();
        }
        function cancelAuthenticationRequest() { active = false; console.info("[delta] polkit (проверка): отменено"); }
        function start() { supplementaryMessage = ""; supplementaryIsError = false; active = true; }
    }

    IpcHandler {
        target: "polkit"
        function demo(): void { demo.start(); }
        function submit(text: string): void { if (root.flow) win.submit(text); }
        function cancel(): void { win.cancel(); }
        function state(): string {
            return JSON.stringify({ registered: root.agent?.isRegistered ?? false, open: root.open,
                                    message: root.flow?.message ?? "", error: root.flow?.supplementaryMessage ?? "" });
        }
    }

    // --- окно ---------------------------------------------------------------

    PanelWindow {
        id: win

        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        visible: root.open || fade.running
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "delta-polkit"
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"

        property bool busy: false
        readonly property var flow: root.flow

        function submit(text) {
            if (!flow || busy) return;
            busy = true;
            flow.submit(text);
        }
        function cancel() {
            if (flow) flow.cancelAuthenticationRequest();
            busy = false;
        }

        Connections {
            target: win.flow
            ignoreUnknownSignals: true
            function onAuthenticationFailed() { win.busy = false; field.clear(); field.shake(); field.focusInput(); }
            function onIsResponseRequiredChanged() { if (win.flow.isResponseRequired) { win.busy = false; field.focusInput(); } }
        }
        onFlowChanged: { busy = false; field.clear(); if (flow) Qt.callLater(field.focusInput); }

        // затемнение под окном
        Rectangle {
            id: dim
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.38)
            opacity: root.open ? 1 : 0
            Behavior on opacity { NumberAnimation { id: fade; duration: Theme.anim.normal; easing.type: Theme.anim.outCurve } }
            MouseArea { anchors.fill: parent }   // клики мимо окна не проходят к столу
        }

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: win.cancel()

            Glass {
                id: card
                strong: true
                radius: Theme.radius + 6
                width: 420
                height: col.implicitHeight + 48
                anchors.centerIn: parent
                opacity: dim.opacity
                scale: 0.94 + 0.06 * dim.opacity

                // окно с паролем должно читаться на любых обоях — подложка плотнее стекла
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: Qt.rgba(Theme.base.r, Theme.base.g, Theme.base.b, 0.72)
                }

                ColumnLayout {
                    id: col
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                    spacing: 14

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 56; height: 56; radius: 28
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                        Sym { anchors.centerIn: parent; name: "shield"; size: 28; color: Theme.accent }
                    }
                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Нужно подтверждение"
                        size: "title"
                        font.weight: Font.DemiBold
                    }
                    Label {
                        Layout.fillWidth: true
                        text: win.flow?.message ?? ""
                        tone: 2
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Label {
                        Layout.fillWidth: true
                        readonly property var who: win.flow?.selectedIdentity ?? null
                        visible: who !== null
                        text: "От имени: " + (who?.displayName || who?.name || "")
                        size: "small"
                        tone: 3
                        horizontalAlignment: Text.AlignHCenter
                    }

                    PasswordField {
                        id: field
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        placeholder: (win.flow?.inputPrompt ?? "Пароль").replace(/:\s*$/, "") || "Пароль"
                        echo: win.flow?.responseVisible ?? false
                        busy: win.busy
                        onSubmitted: pw => win.submit(pw)
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: win.flow?.supplementaryMessage ?? ""
                        size: "small"
                        color: (win.flow?.supplementaryIsError ?? false) ? "#ff6b6b" : Theme.fg2
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 10
                        Btn { Layout.fillWidth: true; text: "Отмена"; kind: "ghost"; onClicked: win.cancel() }
                        Btn { Layout.fillWidth: true; text: "Подтвердить"; kind: "accent"; enabled: !win.busy; onClicked: win.submit(field.text) }
                    }

                    // какое право просят — для внимательных
                    Label {
                        Layout.fillWidth: true
                        text: win.flow?.actionId ?? ""
                        size: "caption"
                        tone: 3
                        font.family: Theme.fontMono
                        elide: Text.ElideMiddle
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }
}
