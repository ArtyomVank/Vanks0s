pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui
import qs.settings
import qs.settings.parts

// Пользователи компьютера (AccountsService). Добавить и удалить может только
// администратор: AccountsService сам спросит пароль через polkit-агент.
// В проверках команды только пишутся в журнал (пробный режим).
ColumnLayout {
    id: root

    property string title: "Пользователи"
    property string icon: "users"
    property string keywords: "учётные записи добавить удалить администратор пользователь"
    spacing: 18

    readonly property bool admin: Accounts.me.admin === true

    Card {
        title: "На этом компьютере"
        Rows {
            Repeater {
                model: Accounts.users
                delegate: SettingRow {
                    id: urow
                    required property var modelData
                    icon: modelData.admin ? "shield" : "user"
                    title: (modelData.realName || modelData.userName) + (modelData.me ? " (вы)" : "")
                    subtitle: modelData.userName + " · " + (modelData.admin ? "администратор" : "обычный пользователь") + (modelData.autologin ? " · автовход" : "")
                    RowLayout {
                        spacing: 10
                        Avatar { size: 34; source: urow.modelData.me ? Accounts.icon : urow.modelData.icon; name: urow.modelData.realName || urow.modelData.userName }
                        Btn {
                            icon: "trash"
                            kind: "danger"
                            iconSize: 16
                            implicitHeight: 32
                            visible: !urow.modelData.me
                            enabled: root.admin
                            onClicked: delDlg.ask(urow.modelData)
                        }
                    }
                }
            }
            SettingRow {
                visible: Accounts.loaded && Accounts.users.length === 0
                title: "AccountsService недоступен"
                subtitle: "Список пользователей сейчас недоступен"
            }
            SettingRow {
                icon: "plus"
                title: "Добавить пользователя"
                subtitle: root.admin ? "Понадобится пароль администратора" : "Доступно только администратору"
                Btn { text: "Добавить…"; icon: "plus"; enabled: root.admin; onClicked: addDlg.open() }
            }
        }
    }

    // ----------------------------------------------------------- добавить
    Dialog {
        id: addDlg
        title: "Новый пользователь"
        subtitle: "Латиницей, с маленькой буквы"
        property string error: ""
        property bool isAdmin: false
        onShownChanged: if (shown) { error = ""; fullF.text = ""; loginF.text = ""; pwF.text = ""; isAdmin = false; fullF.focusInput(); }

        readonly property bool loginOk: /^[a-z_][a-z0-9_-]{0,31}$/.test(loginF.text)

        Field {
            id: fullF; Layout.fillWidth: true; placeholder: "Полное имя: Мария Иванова"; icon: "user"
            onEdited: if (!loginF.edited2) loginF.text = root.suggestLogin(text)
        }
        Field {
            id: loginF; Layout.fillWidth: true; placeholder: "Имя для входа: maria"; icon: "users"
            property bool edited2: false
            error: text.length > 0 && !addDlg.loginOk
            onEdited: edited2 = true
        }
        Field { id: pwF; Layout.fillWidth: true; placeholder: "Пароль (не меньше 8 символов)"; icon: "key"; password: true }
        RowLayout {
            Layout.fillWidth: true
            Label { text: "Администратор"; Layout.fillWidth: true }
            Toggle { checked: addDlg.isAdmin; onToggled: v => addDlg.isAdmin = v }
        }
        Label { visible: addDlg.error.length > 0; text: addDlg.error; color: "#ff6b6b"; size: "small"; wrapMode: Text.WordWrap; Layout.fillWidth: true }

        buttons: [
            Btn { text: "Отмена"; onClicked: addDlg.close() },
            Btn { text: "Создать"; kind: "accent"; enabled: addDlg.loginOk && pwF.text.length >= 8 && !addDlg.busy; onClicked: root.create() }
        ]
    }

    // транслитерация для подсказки имени входа
    function suggestLogin(full) {
        const map = { а: "a", б: "b", в: "v", г: "g", д: "d", е: "e", ё: "e", ж: "zh", з: "z", и: "i", й: "y", к: "k", л: "l", м: "m",
                      н: "n", о: "o", п: "p", р: "r", с: "s", т: "t", у: "u", ф: "f", х: "h", ц: "ts", ч: "ch", ш: "sh", щ: "sch",
                      ъ: "", ы: "y", ь: "", э: "e", ю: "yu", я: "ya" };
        const first = String(full).trim().split(/\s+/)[0] || "";
        return first.toLowerCase().split("").map(c => map[c] ?? c).join("").replace(/[^a-z0-9_-]/g, "").replace(/^[^a-z_]+/, "").slice(0, 32);
    }

    function create() {
        const login = loginF.text, full = fullF.text.trim(), type = addDlg.isAdmin ? "1" : "0", pw = pwF.text;
        addDlg.busy = true;
        Exec.run(["busctl", "--json=short", "call", "org.freedesktop.Accounts", "/org/freedesktop/Accounts", "org.freedesktop.Accounts",
                  "CreateUser", "ssi", login, full, type], {
            label: "создать пользователя " + login,
            dryOut: JSON.stringify({ type: "o", data: ["/org/freedesktop/Accounts/User9999"] }),
            done: (code, out, err) => {
                if (code !== 0) { addDlg.busy = false; addDlg.error = root.explainBus(err); return; }
                let path = "";
                try { path = JSON.parse(out).data[0]; } catch (e) {}
                root.setPassword(path, pw, login);
            }
        });
    }

    // пароль в AccountsService — только хешем (SHA-512 crypt); хеш считает openssl
    function setPassword(path, pw, login) {
        const apply = hash => Exec.run(["busctl", "call", "org.freedesktop.Accounts", path, "org.freedesktop.Accounts.User",
                                        "SetPassword", "ss", hash, ""], {
            label: "пароль пользователя " + login, redact: [7], toast: false,
            done: code => {
                addDlg.busy = false;
                if (code !== 0) { addDlg.error = "Пользователь создан, но пароль не задан"; return; }
                addDlg.close();
                Nav.toast(Exec.dryRun ? "Пробный режим: пользователь " + login + " не создавался" : "Пользователь " + login + " создан");
                Accounts.refresh();
            }
        });
        if (Exec.dryRun) { apply("‹хеш›"); return; }
        Exec.spawn(["openssl", "passwd", "-6", "-stdin"], (code, out) => {
            if (code !== 0 || !out.trim().startsWith("$6$")) { addDlg.busy = false; addDlg.error = "Не удалось подготовить пароль (нужен openssl)"; return; }
            apply(out.trim());
        }, pw + "\n");
    }

    function explainBus(err) {
        const e = String(err);
        if (/not authorized|NotAuthorized|AccessDenied|dismissed/i.test(e)) return "Нет прав или пароль администратора не введён";
        if (/already exists|UserExists/i.test(e)) return "Такой пользователь уже есть";
        return "Не получилось: " + (e.trim().split("\n").pop() || "ошибка AccountsService");
    }

    // ----------------------------------------------------------- удалить
    Dialog {
        id: delDlg
        property var user: ({})
        property bool removeFiles: false
        property string error: ""
        function ask(u) { user = u; removeFiles = false; error = ""; open(); }

        title: "Удалить «" + (user.realName || user.userName || "") + "»?"
        subtitle: "Его файлы и вход пропадут насовсем"

        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true
                Label { text: "Удалить и его файлы" }
                Label { text: "Домашняя папка /home/" + (delDlg.user.userName || ""); size: "small"; tone: 3 }
            }
            Toggle { checked: delDlg.removeFiles; onToggled: v => delDlg.removeFiles = v }
        }
        Label { visible: delDlg.error.length > 0; text: delDlg.error; color: "#ff6b6b"; size: "small"; Layout.fillWidth: true; wrapMode: Text.WordWrap }

        buttons: [
            Btn { text: "Отмена"; onClicked: delDlg.close() },
            Btn {
                text: "Удалить"; kind: "danger"; enabled: !delDlg.busy
                onClicked: {
                    delDlg.busy = true;
                    Exec.run(["busctl", "call", "org.freedesktop.Accounts", "/org/freedesktop/Accounts", "org.freedesktop.Accounts",
                              "DeleteUser", "xb", String(delDlg.user.uid), delDlg.removeFiles ? "true" : "false"], {
                        label: "удалить пользователя " + delDlg.user.userName,
                        done: (code, out, err) => {
                            delDlg.busy = false;
                            if (code !== 0) { delDlg.error = root.explainBus(err); return; }
                            delDlg.close();
                            Accounts.refresh();
                        }
                    });
                }
            }
        ]
    }

    Connections {
        target: Nav
        function onAction(name, arg) {
            if (name === "users.add") { addDlg.open(); if (arg) { fullF.text = arg; loginF.text = root.suggestLogin(arg); if (Exec.dryRun) pwF.text = "test-pass-1"; } }
            else if (name === "users.create") root.create();
            else if (name === "users.delete") delDlg.ask(Accounts.users.find(u => u.userName === arg) || { userName: arg, uid: 0 });
        }
    }
}
