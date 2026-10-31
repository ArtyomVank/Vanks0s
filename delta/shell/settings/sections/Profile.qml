pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.common
import qs.common.ui
import qs.settings
import qs.settings.parts

// Профиль: имя и аватар (AccountsService + ~/.face), пароль, вход.
//
// Аватар: картинка обрезается по кругу в предпросмотре, а в файл уходит
// квадрат 512×512 того же кадра (экран входа и блокировки сами скругляют).
// Файл пишется в ~/.face (домашняя папка), путь передаётся в AccountsService
// SetIconFile — это изменение системы, в проверках оно только в журнале.
ColumnLayout {
    id: root

    property string title: I18n.tr("Профиль")
    property string icon: "user"
    property string keywords: "имя аватар фото пароль автовход вход без пароля блокировка"
    spacing: 18

    readonly property var me: Accounts.me
    readonly property string home: Quickshell.env("HOME") || ""

    // --- шапка ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 132
        radius: Theme.radius - 2
        color: Theme.soft
        border.color: Theme.line

        RowLayout {
            anchors { fill: parent; margins: 20 }
            spacing: 20
            Item {
                implicitWidth: 92; implicitHeight: 92
                Avatar { id: bigAvatar; anchors.fill: parent; size: 92; source: Accounts.icon; name: Accounts.displayName }
                Rectangle {
                    anchors { right: parent.right; bottom: parent.bottom }
                    width: 30; height: 30; radius: 15
                    color: Theme.accent
                    border.width: 3; border.color: Theme.base
                    Sym { anchors.centerIn: parent; name: "edit"; size: 14; color: Theme.onAccent }
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: avatarDlg.openDlg() }
            }
            ColumnLayout {
                spacing: 4
                Layout.fillWidth: true
                Label { text: Accounts.displayName; size: "h1"; Layout.fillWidth: true }
                Label { text: root.me.userName + (root.me.admin ? " · администратор" : " · обычный пользователь"); tone: 3 }
            }
            Btn { text: I18n.tr("Сменить фото"); icon: "image"; onClicked: avatarDlg.openDlg() }
        }
    }

    Card {
        title: I18n.tr("Учётная запись")
        SettingRow {
            icon: "user"
            title: I18n.tr("Имя")
            subtitle: I18n.tr("Так вас видно на экране входа")
            RowLayout {
                spacing: 8
                Field {
                    id: nameField
                    implicitWidth: 240
                    placeholder: root.me.userName
                    text: root.me.realName || ""
                    onAccepted: root.saveName()
                }
                Btn {
                    text: I18n.tr("Сохранить")
                    kind: "accent"
                    visible: nameField.text !== (root.me.realName || "")
                    onClicked: root.saveName()
                }
            }
        }
        SettingRow {
            icon: "key"
            title: I18n.tr("Пароль")
            subtitle: I18n.tr("Для входа и важных изменений")
            Btn { text: I18n.tr("Сменить…"); onClicked: pwDlg.open() }
        }
    }

    Card {
        title: I18n.tr("Вход")
        SettingRow {
            icon: "unlock"
            title: I18n.tr("Входить без пароля")
            subtitle: I18n.tr("При включении — «Добро пожаловать» и сразу экран блокировки, без экрана входа. Браузер может один раз спросить пароль")
            Toggle {
                checked: root.autologinUser === root.me.userName
                onToggled: v => root.setAutologin(v)
            }
        }
        SettingRow {
            icon: "lock"
            title: I18n.tr("Блокировать при входе")
            subtitle: root.autologinUser === root.me.userName ? "При автовходе сначала показывается экран блокировки" : "Показывать экран блокировки сразу после входа"
            Toggle { checked: Settings.get("lock.onStart", false); onToggled: v => Settings.set("lock.onStart", v) }
        }
    }

    // Автовход — это блок [initial_session] в конфиге greetd; правит его
    // delta-autologin от root через pkexec (окно пароля — агент polkit Delta).
    property string autologinUser: ""
    Component.onCompleted: readAutologin()
    function readAutologin() {
        Exec.read(["delta-autologin", "status"], (code, out) => root.autologinUser = code === 0 ? out.trim() : "");
    }
    function setAutologin(on) {
        const cmd = ["pkexec", "/usr/bin/delta-autologin", on ? "enable" : "disable"].concat(on ? [root.me.userName] : []);
        Exec.run(cmd, {
            label: on ? "включить автовход" : "выключить автовход",
            done: (code, out, err) => {
                if (code !== 0) {
                    // 126/127 — окно пароля закрыли или polkit отказал
                    Nav.toast(code === 126 || code === 127 ? "Автовход не изменён" : "Не удалось: " + (err.trim() || "код " + code));
                    return;
                }
                Settings.set("session.autologin", on);
                // автовход без блокировки — компьютер открыт любому
                if (on) Settings.set("lock.onStart", true);
                if (Exec.dryRun) root.autologinUser = on ? root.me.userName : "";
                else root.readAutologin();
                if (!Exec.dryRun) Nav.toast(on ? "Автовход включён — при входе покажется экран блокировки" : "Автовход выключен");
            }
        });
    }

    function saveName() {
        const n = nameField.text.trim();
        if (n === (me.realName || "")) return;
        Accounts.callUser(me.path, "SetRealName", "s", [n], "имя пользователя: " + n, code => {
            if (code === 0) { Nav.toast(Exec.dryRun ? "Пробный режим: имя не записано" : "Имя сохранено"); if (!Exec.dryRun) Accounts.refresh(); }
            else Nav.toast("Не удалось сохранить имя");
        });
    }

    PasswordDialog { id: pwDlg }

    // ------------------------------------------------------------ аватар
    Dialog {
        id: avatarDlg
        title: I18n.tr("Фото профиля")
        subtitle: I18n.tr("Картинка или готовый аватар")
        cardWidth: 560

        // "" — текущее; "color:<hex>" — инициалы на цвете; иначе путь к файлу
        property string choice: ""
        property var images: []

        function openDlg() { choice = ""; findImages.running = true; open(); }

        RowLayout {
            spacing: 18
            Layout.fillWidth: true

            // то, что уйдёт в файл: квадрат, круг — только маской предпросмотра
            Item {
                implicitWidth: 150; implicitHeight: 150
                Avatar {
                    id: shot
                    anchors.fill: parent
                    size: 150
                    square: true
                    visible: false
                    name: Accounts.displayName
                    tint: avatarDlg.choice.startsWith("color:") ? avatarDlg.choice.slice(6) : Theme.accent
                    source: avatarDlg.choice.length === 0 ? Accounts.icon : avatarDlg.choice.startsWith("color:") ? "" : avatarDlg.choice
                }
                Avatar {
                    anchors.fill: parent
                    size: 150
                    name: shot.name
                    tint: shot.tint
                    source: shot.source
                }
            }

            ColumnLayout {
                spacing: 10
                Layout.fillWidth: true
                Label { text: I18n.tr("Стандартные"); size: "small"; tone: 3 }
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: Theme.accents
                        delegate: Item {
                            id: def
                            required property string modelData
                            readonly property bool sel: avatarDlg.choice === "color:" + modelData
                            width: 44; height: 44
                            Avatar { anchors.fill: parent; size: 44; name: Accounts.displayName; tint: def.modelData }
                            Rectangle { anchors.centerIn: parent; width: 52; height: 52; radius: 26; color: "transparent"; border.width: 2; border.color: Theme.fg; visible: def.sel }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: avatarDlg.choice = "color:" + def.modelData }
                        }
                    }
                }
                Label { text: I18n.tr("Картинки"); size: "small"; tone: 3; visible: avatarDlg.images.length > 0 }
                Flickable {
                    Layout.fillWidth: true
                    implicitHeight: Math.min(110, imgFlow.implicitHeight)
                    contentHeight: imgFlow.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    visible: avatarDlg.images.length > 0
                    Flow {
                        id: imgFlow
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: avatarDlg.images
                            delegate: Item {
                                id: pic
                                required property string modelData
                                readonly property bool sel: avatarDlg.choice === modelData
                                width: 44; height: 44
                                Avatar { anchors.fill: parent; size: 44; source: pic.modelData }
                                Rectangle { anchors.centerIn: parent; width: 52; height: 52; radius: 26; color: "transparent"; border.width: 2; border.color: Theme.fg; visible: pic.sel }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: avatarDlg.choice = pic.modelData }
                            }
                        }
                    }
                }
            }
        }

        Field {
            id: pathField
            Layout.fillWidth: true
            icon: "folder"
            placeholder: I18n.tr("Или путь к файлу: ~/Изображения/я.jpg")
            onAccepted: {
                const p = text.trim().replace(/^~(?=\/)/, root.home);
                if (p.length) avatarDlg.choice = p;
            }
        }

        buttons: [
            Btn { text: I18n.tr("Отмена"); onClicked: avatarDlg.close() },
            Btn { text: I18n.tr("Сохранить"); kind: "accent"; enabled: avatarDlg.choice.length > 0 && (shot.hasImage || avatarDlg.choice.startsWith("color:")); onClicked: root.saveAvatar() }
        ]

        Process {
            id: findImages
            command: ["sh", "-c", "for d in \"$HOME/Изображения\" \"$HOME/Pictures\" \"$HOME/Загрузки\" \"$HOME/Downloads\" /usr/share/pixmaps/faces; do " +
                      "[ -d \"$d\" ] && find \"$d\" -maxdepth 2 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\) 2>/dev/null; done | head -n 48"]
            stdout: StdioCollector { onStreamFinished: avatarDlg.images = text.split("\n").filter(l => l.length) }
        }
    }

    // снимок квадрата 512×512 → ~/.face → AccountsService
    function saveAvatar() {
        const face = home + "/.face";
        const finish = () => {
            Accounts.callUser(me.path, "SetIconFile", "s", [face], "аватар в AccountsService", code => {
                if (code !== 0) { Nav.toast("Не удалось сохранить аватар"); return; }
                Accounts.pendingIcon = "";
                Accounts.pendingIcon = face;
                Nav.toast(Exec.dryRun ? "Пробный режим: аватар записан только в " + face : "Аватар сохранён");
                avatarDlg.close();
            });
        };
        if (!Exec.homeWritable) {
            Exec.note("аватар в ~/.face", ["grab", face], true, []);
            finish();
            return;
        }
        shot.visible = true;
        shot.grabToImage(result => {
            shot.visible = false;
            if (!result.saveToFile(face + ".png")) { Nav.toast("Не удалось записать " + face); return; }
            // .face без расширения: Qt выбирает формат по имени, поэтому сначала .png
            Exec.run(["mv", "-f", face + ".png", face], { label: "~/.face", home: true, toast: false, done: finish });
        }, Qt.size(512, 512));
    }

    Connections {
        target: Nav
        function onAction(name, arg) {
            if (name === "profile.avatar") { avatarDlg.openDlg(); if (arg) avatarDlg.choice = arg; }
            else if (name === "profile.avatar.save") root.saveAvatar();
            else if (name === "profile.password") pwDlg.open();
            else if (name === "profile.password.fill") { pwDlg.open(); const p = arg.split(" "); pwDlg.fill(p[0] || "", p[1] || ""); }
            else if (name === "profile.password.submit") pwDlg.submit();
            else if (name === "profile.name") { nameField.text = arg; root.saveName(); }
        }
    }
}
