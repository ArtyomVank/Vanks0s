pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Единое хранилище настроек Delta.
//
// Читает значения по умолчанию из пакета и ~/.config/delta/settings.json,
// отдаёт объединённый объект `s`. Любой модуль читает `Settings.s.<раздел>`
// и пишет через `Settings.set("раздел.ключ", значение)`. Файл отслеживается:
// правка руками или из приложения «Настройки» сразу видна оболочке.
Singleton {
    id: root

    readonly property string dataDir: Quickshell.env("DELTA_DATA") || "/usr/share/delta"
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/delta"
    readonly property string path: configDir + "/settings.json"

    property var defaults: ({})
    property var user: ({})
    readonly property var s: merge(defaults, user)
    property bool ready: false

    // Разделы, которые влияют на Hyprland: после записи нужно delta-apply.
    readonly property var hyprSections: ["monitors", "display", "windows", "input", "appearance"]
    property bool pendingApply: false

    function isObject(v) {
        return v !== null && typeof v === "object" && !Array.isArray(v);
    }

    function merge(a, b) {
        if (!isObject(a)) return isObject(b) ? clone(b) : (b === undefined ? a : b);
        if (!isObject(b)) return clone(a);
        const out = clone(a);
        for (const k in b)
            out[k] = isObject(out[k]) && isObject(b[k]) ? merge(out[k], b[k]) : clone(b[k]);
        return out;
    }

    function clone(v) {
        return v === undefined ? undefined : JSON.parse(JSON.stringify(v));
    }

    function parse(text, what) {
        try {
            const v = JSON.parse(text);
            if (isObject(v)) return v;
        } catch (e) {
            console.warn("[delta] не удалось разобрать " + what + ": " + e);
        }
        return null;
    }

    // Settings.get("docks.apps.edge", "bottom")
    function get(key, fallback) {
        let v = s;
        for (const part of key.split(".")) {
            if (!isObject(v) || !(part in v)) return fallback;
            v = v[part];
        }
        return v;
    }

    // Settings.set("appearance.accent", "#2BC4F0")
    function set(key, value) {
        const parts = key.split(".");
        const next = clone(user) || {};
        let node = next;
        for (let i = 0; i < parts.length - 1; i++) {
            if (!isObject(node[parts[i]])) node[parts[i]] = {};
            node = node[parts[i]];
        }
        node[parts[parts.length - 1]] = clone(value);
        user = next;
        if (hyprSections.indexOf(parts[0]) !== -1) pendingApply = true;
        saveTimer.restart();
    }

    FileView {
        id: defaultsFile
        path: root.dataDir + "/defaults/settings.json"
        blockLoading: true
        onLoaded: root.defaults = root.parse(text(), path) || {}
        onLoadFailed: console.warn("[delta] нет файла значений по умолчанию: " + path)
    }

    FileView {
        id: userFile
        path: root.path
        watchChanges: true
        blockLoading: true
        onFileChanged: reload()
        onLoaded: {
            const v = root.parse(text(), path);
            // повреждённый файл не затираем: работаем на прежних значениях
            if (v !== null) root.user = v;
            root.ready = true;
        }
        onLoadFailed: {
            // первый запуск без delta-session: создаём файл из значений по умолчанию
            root.user = root.clone(root.defaults) || {};
            root.ready = true;
            saveTimer.restart();
        }
    }

    // Несколько быстрых изменений (ползунок) — одна запись на диск.
    Timer {
        id: saveTimer
        interval: 250
        onTriggered: {
            userFile.setText(JSON.stringify(root.user, null, 2) + "\n");
            if (root.pendingApply) {
                root.pendingApply = false;
                applyProc.running = true;
            }
        }
    }

    Process {
        id: applyProc
        command: ["delta-apply"]
        stderr: StdioCollector {
            onStreamFinished: if (text.length) console.info(text.trim())
        }
    }
}
