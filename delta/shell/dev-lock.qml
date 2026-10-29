import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.common
import qs.common.ui
import qs.wallpaper
import qs.lock
// разделы «Настроек» берут Exec из qs.settings — модуль должен быть известен с запуска
import qs.settings

// Отладка модуля B: блокировка, меню питания, простой.
//   DELTA_DEV_NAME=lock DELTA_DEV_HIDDEN=1 DELTA_SHELL_ENTRY=delta/shell/dev-lock.qml tools/delta-dev.sh nested 300
//   DELTA_DEV_NAME=lock tools/delta-dev.sh ipc call dev lock
// Во вложенной сессии действия питания только пишутся в журнал (PowerActions.dryRun).
ShellRoot {
    id: shellRoot
    Variants {
        model: Quickshell.screens
        delegate: Wallpaper { required property ShellScreen modelData; screen: modelData }
    }

    Lock { id: lockRoot }

    // выпадающее меню питания — без дока, просто на стекле в углу
    LazyLoader {
        id: menuLoader
        active: false
        PanelWindow {
            WlrLayershell.namespace: "delta-dev-menu"
            anchors { top: true; right: true }
            margins { top: 16; right: 16 }
            implicitWidth: 360 + 32
            implicitHeight: m.implicitHeight + 32
            color: "transparent"
            Glass {
                anchors.fill: parent
                strong: true
                Loader {
                    id: m
                    anchors { fill: parent; margins: 16 }
                    source: Quickshell.shellDir + "/menus/PowerMenu.qml"
                }
            }
        }
    }

    // раздел «Настроек» в окне на стекле: ipc call dev section Lock | Power | ""
    property string section: ""
    LazyLoader {
        active: shellRoot.section.length > 0
        PanelWindow {
            WlrLayershell.namespace: "delta-dev-section"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors { top: true; bottom: true }
            implicitWidth: 720
            color: "transparent"
            Glass {
                anchors { fill: parent; margins: 12 }
                strong: true
                Flickable {
                    id: fl
                    anchors { fill: parent; margins: 20 }
                    contentHeight: sec.implicitHeight
                    contentY: devScroll
                    clip: true
                    Loader {
                        id: sec
                        width: fl.width
                        source: shellRoot.section ? Quickshell.shellDir + "/settings/sections/" + shellRoot.section + ".qml" : ""
                        onLoaded: item.width = Qt.binding(() => fl.width)
                    }
                }
            }
        }
    }
    property real devScroll: 0

    IpcHandler {
        target: "dev"

        function section(name: string): void { shellRoot.section = name; shellRoot.devScroll = 0; }
        function scroll(y: real): void { shellRoot.devScroll = y; }

        function lock(): void { lockRoot.lock(); }
        function unlock(): void { lockRoot.devUnlock(); }
        function password(text: string): void { lockRoot.devSubmit(text); }
        function error(text: string): void { lockRoot.devError(text); }
        function confirm(action: string): void { lockRoot.devConfirm(action); }
        function overlay(): void { ShellState.toggleOverlay("power"); }
        function menu(): void { menuLoader.active = !menuLoader.active; }
        function edit(): void { ShellState.lockEditing = !ShellState.lockEditing; }
        function clock(style: string, color: string): void {
            Settings.set("lock.clock.style", style);
            Settings.set("lock.clock.color", color);
        }
        function dnd(on: bool): void { Settings.set("notifications.dnd", on); ShellState.dnd = on; }
        function notifs(): void {
            const now = Date.now();
            ShellState.notifications = [
                { id: 1, app: "Telegram", appIcon: "telegram", summary: "Аня", body: "Встречаемся в 19:00 у входа?", time: now - 120000 },
                { id: 2, app: "Почта", appIcon: "mail-unread", summary: "Сборка ISO завершена", body: "vankos-0.1-x86_64.iso — 1,9 ГБ, <b>проверка пройдена</b>", time: now - 900000 },
                { id: 3, app: "Delta", appIcon: "", summary: "Доступны обновления", body: "12 пакетов, в том числе ядро", time: now - 3600000 }
            ];
        }
        function idle(lockAfter: int, offAfter: int): void {
            Settings.set("power.lockAfter", lockAfter);
            Settings.set("power.screenOffAfter", offAfter);
        }
        function state(): string {
            return JSON.stringify({ locked: ShellState.locked, unlocking: ShellState.unlocking, secure: lockRoot.secure,
                canHibernate: PowerActions.canHibernate, dryRun: PowerActions.dryRun,
                layout: Keyboard.layout, caps: Keyboard.capsLock, user: Account.name, avatar: Account.avatar });
        }
    }
}
