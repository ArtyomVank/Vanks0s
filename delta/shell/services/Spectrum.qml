pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Спектр звука для виджета «Полосы»: cava слушает выход PipeWire и печатает
// высоты столбиков (0–100) строкой на кадр. Работает, только пока на него
// кто-то смотрит (acquire/release) — без зрителей cava не запущена.
//     Spectrum.acquire(); … Spectrum.values … Spectrum.release()
Singleton {
    id: root

    // столбиков на канал; стерео — левый канал зеркально, затем правый
    readonly property int bars: 32
    property var values: []
    property int users: 0
    readonly property bool active: users > 0
    // нет cava — виджет покажет подсказку
    property bool missing: false

    function acquire() { users++; }
    function release() { users = Math.max(0, users - 1); }

    onActiveChanged: if (!active) values = []

    Process {
        id: proc
        running: root.active && !root.missing
        command: ["sh", "-c",
            "command -v cava >/dev/null || { echo MISSING; exit 0; }; " +
            "c=$(mktemp -t delta-cava.XXXXXX); " +
            "printf '%s\\n' '[general]' \"bars = $1\" 'framerate = 40' 'autosens = 1' " +
            "'[input]' 'method = pipewire' 'source = auto' " +
            "'[output]' 'method = raw' 'raw_target = /dev/stdout' 'data_format = ascii' " +
            "'ascii_max_range = 100' 'bar_delimiter = 59' 'frame_delimiter = 10' 'channels = stereo' " +
            "'[smoothing]' 'noise_reduction = 70' > \"$c\"; " +
            // cava читает настройки при запуске — потом файл не нужен;
            // exec — чтобы при остановке сигнал получила сама cava
            "(sleep 3; rm -f \"$c\") & exec cava -p \"$c\"",
            "sh", String(root.bars * 2)]
        stdout: SplitParser {
            onRead: line => {
                if (line === "MISSING") { root.missing = true; return; }
                const parts = line.split(";");
                const out = [];
                for (const p of parts) if (p.length) out.push(Math.min(100, Number(p) || 0));
                if (out.length) root.values = out;
            }
        }
    }
}
