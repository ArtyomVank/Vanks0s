import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Фоновая проверка обновлений: через несколько минут после входа и потом
// раз в 6 часов — delta-update check (систему не меняет). Нашлось — уведомление
// «Открыть» → «Настройки» → «Обновления», где ставится всё в одно нажатие.
// Об одном и том же наборе обновлений напоминает не чаще раза в сутки.
// Выключается в «Настройках» (updates.auto). Во вложенной сессии не работает.
//     UpdateCheck {}      (shell.qml)
Scope {
    id: root

    readonly property bool enabled: Settings.get("updates.auto", true) !== false
                                    && (Quickshell.env("DELTA_NESTED") || "") === ""

    Timer {
        // первая проверка — когда вход уже позади и сеть поднялась
        interval: 4 * 60 * 1000
        running: root.enabled
        onTriggered: check.running = true
    }
    Timer {
        interval: 6 * 60 * 60 * 1000
        running: root.enabled
        repeat: true
        onTriggered: check.running = true
    }

    Process {
        id: check
        command: ["delta-update", "check"]
        stdout: StdioCollector {
            id: out
            onStreamFinished: root.report(text)
        }
    }

    function report(text) {
        const list = [];
        for (const l of text.split("\n")) {
            const m = l.match(/^(\S+)\s+(\S+)\s+->\s+(\S+)/);
            if (m) list.push({ name: m[1], to: m[3] });
        }
        Settings.set("updates.lastCheck", new Date().toISOString());
        Settings.set("updates.available", list.length);
        if (list.length === 0) return;

        // тот же набор уже показывали сегодня — не надоедаем
        const key = list.map(u => u.name + "=" + u.to).join(",");
        const last = Settings.get("updates.notified", {}) || {};
        if (last.key === key && Date.now() - (last.at || 0) < 24 * 3600 * 1000) return;
        Settings.set("updates.notified", { key: key, at: Date.now() });

        const delta = list.find(u => u.name === "delta");
        const title = delta ? "Вышла Delta " + delta.to : "Доступны обновления";
        const n = list.length, a = n % 10, b = n % 100;
        const word = a === 1 && b !== 11 ? "пакет" : a >= 2 && a <= 4 && (b < 12 || b > 14) ? "пакета" : "пакетов";
        const body = n + " " + word + " можно обновить. Установка в одно нажатие — нужен только пароль.";
        // --wait: ответ на кнопку приходит в stdout notify-send
        Quickshell.execDetached(["sh", "-c",
            'a=$(notify-send -a "Обновления" -i system-software-update -A open="Открыть" --wait "$1" "$2"); ' +
            '[ "$a" = open ] && exec delta-settings updates', "sh", title, body]);
    }
}
