pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Громкость между входами. WirePlumber помнит её сам, но если его состояние не
// сохранилось (каталог ~/.local/state без прав, сессию закрыли раньше записи),
// после входа громкость — его 40 % по умолчанию. Поэтому Delta тоже помнит
// громкость и «без звука» для каждого выхода и микрофона (по имени узла,
// ~/.local/state/delta/volume.json) и при входе возвращает их.
// Во вложенной сессии (DELTA_NESTED) выключено: PipeWire там — настоящий.
Scope {
    id: root

    readonly property bool enabled: Quickshell.env("DELTA_NESTED") !== "1"

    readonly property string file: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/delta/volume.json"
    property var saved: ({})
    property bool loaded: false
    // имена узлов, которым громкость уже вернули — менять её дальше можно
    property var restored: ({})

    readonly property var nodes: enabled ? [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource].filter(n => n) : []
    PwObjectTracker { objects: root.nodes }

    FileView {
        id: store
        path: root.enabled ? root.file : ""
        printErrors: false
        onLoaded: {
            try { root.saved = JSON.parse(text()) || {}; } catch (e) { root.saved = {}; }
            root.loaded = true;
            root.restoreAll();
        }
        onLoadFailed: { root.loaded = true; root.restoreAll(); }
    }

    function restoreAll() { for (const n of nodes) restore(n); }
    function restore(n) {
        if (!loaded || !n || !n.ready || !n.audio || restored[n.name]) return;
        const s = saved[n.name];
        if (s && typeof s.volume === "number") {
            if (Math.abs(n.audio.volume - s.volume) > 0.004) {
                console.info("[delta] громкость " + n.name + ": " + Math.round(n.audio.volume * 100) + " % → " + Math.round(s.volume * 100) + " %");
                n.audio.volume = s.volume;
            }
            if (typeof s.muted === "boolean" && n.audio.muted !== s.muted) n.audio.muted = s.muted;
        }
        const r = Object.assign({}, restored);
        r[n.name] = true;
        restored = r;
    }
    onNodesChanged: restoreAll()

    // Первые 20 с после входа громкость, сама упавшая на 40 % (по умолчанию
    // WirePlumber'а — так делал экран входа, пока его звук ещё закрывался),
    // не запоминаем, а возвращаем сохранённую
    readonly property double startedAt: Date.now()
    function stray(n) {
        const s = saved[n.name];
        return Date.now() - startedAt < 20000 && s && typeof s.volume === "number"
            && Math.abs(n.audio.volume - 0.4) < 0.006 && Math.abs(s.volume - 0.4) > 0.01;
    }

    // изменения — в файл через полсекунды после последнего
    function remember(n) {
        if (!n || !n.ready || !n.audio || !restored[n.name]) return;
        if (stray(n)) {
            console.info("[delta] громкость " + n.name + " сама упала на 40 % — возвращаю " + Math.round(saved[n.name].volume * 100) + " %");
            n.audio.volume = saved[n.name].volume;
            return;
        }
        const s = Object.assign({}, saved);
        s[n.name] = { volume: Math.round(n.audio.volume * 1000) / 1000, muted: n.audio.muted };
        saved = s;
        writeLater.restart();
    }
    Timer {
        id: writeLater
        interval: 500
        onTriggered: { dir.running = true; store.setText(JSON.stringify(root.saved, null, 2) + "\n"); }
    }
    Process { id: dir; command: ["mkdir", "-p", root.file.replace(/\/[^/]*$/, "")] }

    Instantiator {
        model: root.nodes
        delegate: Connections {
            required property var modelData
            target: modelData?.audio ?? null
            function onVolumeChanged() { root.remember(modelData); }
            function onMutedChanged() { root.remember(modelData); }
        }
    }
    Instantiator {
        model: root.nodes
        delegate: Connections {
            required property var modelData
            target: modelData
            function onReadyChanged() { root.restore(modelData); }
        }
    }
}
