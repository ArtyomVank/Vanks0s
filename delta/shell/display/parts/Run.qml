import QtQuick
import Quickshell.Io

// Одноразовый запуск команды с ответом: done(код возврата, вывод stdout+stderr).
// Создаётся динамически и сам себя удаляет:
//     runComp.createObject(root, { argv: ["hyprctl", "monitors", "-j"], done: (code, out) => … })
// Код возврата печатаем в конце потока, чтобы не зависеть от порядка сигналов
// exited и streamFinished.
Process {
    id: proc

    property var argv: []
    property var done: null

    command: ["sh", "-c", '"$@" 2>&1; printf "\\n\\036%d" "$?"', "sh"].concat(argv)
    running: true

    stdout: StdioCollector {
        onStreamFinished: {
            const i = text.lastIndexOf("\n\x1e");
            const code = i >= 0 ? parseInt(text.slice(i + 2)) : -1;
            const out = i >= 0 ? text.slice(0, i) : text;
            if (proc.done) proc.done(code, out);
            proc.destroy();
        }
    }
}
