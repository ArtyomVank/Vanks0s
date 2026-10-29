import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.common
import qs.common.ui
import qs.settings

// Смена своего пароля.
//
// Как устроено: обычный `passwd` (PAM, pwquality — всё как в терминале)
// запускается в псевдотерминале через `script` с LC_ALL=C, чтобы подсказки
// были предсказуемыми. Пароли отдаются в stdin только в ответ на свою
// подсказку: passwd сбрасывает ввод, набранный заранее. Пароли не попадают
// ни в командную строку, ни в журнал. Ошибки PAM переводятся на русский.
// В пробном режиме passwd не запускается — диалог проходит весь путь
// с имитацией ответа (текущий пароль «wrong» имитирует отказ).
Dialog {
    id: root

    property string error: ""
    property bool done: false
    property string stage: ""
    property string output: ""

    title: done ? "Пароль изменён" : "Сменить пароль"
    subtitle: done ? "Используйте новый пароль при следующем входе и для разблокировки." : "Пароль нужен для входа, разблокировки экрана и действий администратора."
    busy: proc.running

    function reset() {
        error = ""; done = false; stage = ""; output = "";
        oldF.text = ""; newF.text = ""; repF.text = "";
    }
    onShownChanged: if (shown) { reset(); oldF.focusInput(); }

    readonly property string strength: {
        const p = newF.text;
        if (!p.length) return "";
        let s = 0;
        if (p.length >= 8) s++;
        if (p.length >= 12) s++;
        if (/[a-zа-я]/.test(p) && /[A-ZА-Я]/.test(p)) s++;
        if (/\d/.test(p)) s++;
        if (/[^\w\sа-яА-Я]/.test(p)) s++;
        return p.length < 8 ? "Слишком короткий — нужно хотя бы 8 символов" : s <= 2 ? "Простой пароль" : s <= 3 ? "Неплохой пароль" : "Надёжный пароль";
    }

    function explain(text) {
        const t = text.toLowerCase();
        if (/authentication token manipulation|authentication failure|current password|incorrect/.test(t) && !/bad password/.test(t))
            return "Текущий пароль неверен";
        if (/do not match/.test(t)) return "Пароли не совпадают";
        if (/shorter than/.test(t)) return "Слишком короткий пароль";
        if (/same as the old|unchanged/.test(t)) return "Новый пароль совпадает со старым";
        if (/too similar/.test(t)) return "Новый пароль слишком похож на старый";
        if (/palindrome/.test(t)) return "Пароль читается одинаково с обеих сторон";
        if (/dictionary/.test(t)) return "Пароль основан на словарном слове";
        if (/too simplistic|systematic|fewer than|monotonic/.test(t)) return "Слишком простой пароль";
        if (/contains the user name/.test(t)) return "Пароль содержит имя пользователя";
        if (/wait longer/.test(t)) return "Пароль меняли недавно — попробуйте позже";
        if (/bad password/.test(t)) return "Слишком простой пароль";
        return "Не удалось сменить пароль" + (text.trim().length ? ": " + text.trim().split("\n").pop() : "");
    }

    function submit() {
        error = "";
        if (!oldF.text.length) { error = "Введите текущий пароль"; return; }
        if (newF.text.length < 8) { error = "Слишком короткий пароль: нужно хотя бы 8 символов"; return; }
        if (newF.text !== repF.text) { error = "Пароли не совпадают"; return; }
        Exec.note("смена пароля", ["passwd"], Exec.dryRun, []);
        if (Exec.dryRun) {
            console.info("[delta-settings] пробный режим, не выполняю: passwd (в псевдотерминале)");
            simulate.start();
            return;
        }
        output = ""; stage = "";
        proc.running = true;
    }

    // пробный режим: пауза, как у PAM, и результат
    Timer {
        id: simulate
        interval: 700
        onTriggered: {
            if (oldF.text === "wrong") root.error = root.explain("passwd: Authentication token manipulation error");
            else { root.done = true; Nav.toast("Пробный режим: пароль не менялся"); }
        }
    }
    property bool simulating: simulate.running

    Process {
        id: proc
        command: ["script", "-qefc", "passwd", "/dev/null"]
        environment: ({ LC_ALL: "C", LANG: "C", LANGUAGE: "" })
        stdinEnabled: true
        stdout: SplitParser {
            // подсказки passwd без перевода строки — разбираем поток целиком
            splitMarker: ""
            onRead: data => {
                root.output += data;
                const tail = root.output.slice(-80).toLowerCase();
                if (/retype new password: *$|re-enter new password: *$/.test(tail) && root.stage !== "rep") {
                    root.stage = "rep"; proc.write(repF.text + "\n");
                } else if (/new password: *$/.test(tail) && root.stage !== "new" && root.stage !== "rep") {
                    root.stage = "new"; proc.write(newF.text + "\n");
                } else if (/(current|old|\(current\) unix) password: *$|^password: *$/.test(tail) && root.stage === "") {
                    root.stage = "old"; proc.write(oldF.text + "\n");
                }
            }
        }
        onExited: code => {
            if (code === 0 && /success|updated/i.test(root.output)) { root.done = true; Nav.toast("Пароль изменён"); }
            else root.error = root.explain(root.output.replace(/^.*password: */gim, ""));
        }
    }

    ColumnLayout {
        visible: !root.done
        spacing: 10
        Layout.fillWidth: true
        Field { id: oldF; Layout.fillWidth: true; password: true; placeholder: "Текущий пароль"; icon: "lock"; onAccepted: newF.focusInput() }
        Field { id: newF; Layout.fillWidth: true; password: true; placeholder: "Новый пароль"; icon: "key"; onAccepted: repF.focusInput() }
        Field { id: repF; Layout.fillWidth: true; password: true; placeholder: "Новый пароль ещё раз"; icon: "key"
                error: text.length > 0 && text !== newF.text; onAccepted: root.submit() }
        Label { visible: root.strength.length > 0 && !root.error.length; text: root.strength; size: "small"; tone: 3 }
        Label {
            visible: root.error.length > 0
            text: root.error
            color: "#ff6b6b"
            size: "small"
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }
    Sym { visible: root.done; name: "check"; size: 40; color: "#3FB37A"; Layout.alignment: Qt.AlignHCenter }

    buttons: [
        Btn { visible: !root.done; text: "Отмена"; enabled: !root.busy; onClicked: root.close() },
        Btn { visible: !root.done; text: proc.running || root.simulating ? "Проверка…" : "Сменить"; kind: "accent"
              enabled: !proc.running && !root.simulating; onClicked: root.submit() },
        Btn { visible: root.done; text: "Готово"; kind: "accent"; onClicked: root.close() }
    ]

    // для проверки состояний через IPC
    function fill(oldPw, newPw) { oldF.text = oldPw; newF.text = newPw; repF.text = newPw; }
}
