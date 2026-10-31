import QtQuick
import Quickshell
import Quickshell.Io

// Выбор фото для виджета «Фото»: zenity (можно несколько), копии — в
// ~/.local/share/delta/photos, чтобы фото не пропадали вместе с оригиналом.
// По готовности — picked(список путей к копиям).
//     PhotoPicker { id: picker; onPicked: list => grid.patch(id, { photos: list }) }
//     picker.pick()
Process {
    id: root

    readonly property string store: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/delta/photos"
    signal picked(var list)

    function pick() { if (!running) running = true; }

    command: ["sh", "-c", `command -v zenity >/dev/null || { notify-send -a Delta "Нет zenity" "Поставьте пакет zenity, чтобы выбирать фото"; exit 3; }
        mkdir -p "$1" || exit 1
        zenity --file-selection --multiple --separator='\n' --title='Фото для виджета' \\
            --file-filter='Фото | *.jpg *.jpeg *.png *.webp *.bmp *.gif *.JPG *.JPEG *.PNG *.WEBP' | while IFS= read -r f; do
            [ -f "$f" ] || continue
            ext=\${f##*.}
            out="$1/$(date +%s%N).$(printf '%s' "$ext" | tr 'A-Z' 'a-z')"
            cp -- "$f" "$out" && printf '%s\\n' "$out"
        done`, "sh", store]
    stdout: StdioCollector {
        onStreamFinished: {
            const list = text.split("\n").filter(x => x);
            if (list.length) root.picked(list);
        }
    }
}
