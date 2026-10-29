pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common
import qs.common.ui
import qs.settings
import qs.settings.parts

// Приложения по умолчанию: xdg-mime default (пишет ~/.config/mimeapps.list),
// терминал — ~/.config/xdg-terminals.list (его читает xdg-terminal-exec,
// которым Delta открывает терминал). Обе записи — только в домашней папке.
ColumnLayout {
    id: root

    property string title: "Приложения по умолчанию"
    property string icon: "apps"
    property string keywords: "браузер почта файлы терминал изображения видео музыка текст mime открывать"
    spacing: 18

    readonly property var kinds: [
        { id: "browser",  title: "Браузер",      icon: "globe",    mimes: ["x-scheme-handler/http", "x-scheme-handler/https", "text/html"] },
        { id: "mail",     title: "Почта",        icon: "bell",     mimes: ["x-scheme-handler/mailto"] },
        { id: "files",    title: "Файлы",        icon: "folder",   mimes: ["inode/directory"] },
        { id: "terminal", title: "Терминал",     icon: "terminal", mimes: [] },
        { id: "images",   title: "Изображения",  icon: "image",    mimes: ["image/png", "image/jpeg", "image/webp", "image/gif"] },
        { id: "video",    title: "Видео",        icon: "video",    mimes: ["video/mp4", "video/x-matroska", "video/webm"] },
        { id: "music",    title: "Музыка",       icon: "music",    mimes: ["audio/mpeg", "audio/flac", "audio/ogg"] },
        { id: "text",     title: "Текст",        icon: "file",     mimes: ["text/plain"] }
    ]
    // { browser: { default: "x.desktop", apps: [...] }, … }
    property var appState: ({})

    // byId не обновляется, когда список приложений догрузится, — держим свою карту
    readonly property var entries: {
        const m = {};
        for (const e of DesktopEntries.applications.values) m[e.id] = e;
        return m;
    }
    function entry(id) { return entries[String(id).replace(/\.desktop$/, "")] || null; }
    function appName(id) { const e = entry(id); return e ? e.name : String(id).replace(/\.desktop$/, ""); }
    function appIcon(id) { const e = entry(id); return e ? e.icon : ""; }

    function refresh() {
        const all = [].concat(...kinds.map(k => k.mimes));
        Exec.read(["bash", Exec.helper("mime-apps")].concat(all), (code, out) => {
            let m = {};
            try { m = JSON.parse(out); } catch (e) { return; }
            const s = Object.assign({}, root.appState);
            for (const k of root.kinds) {
                if (!k.mimes.length) continue;
                const apps = [];
                for (const mime of k.mimes) for (const a of (m[mime] ? m[mime].apps : [])) if (apps.indexOf(a) === -1) apps.push(a);
                s[k.id] = { default: m[k.mimes[0]] ? m[k.mimes[0]].default : "", apps: apps };
            }
            root.appState = s;
        });
        Exec.read(["bash", Exec.helper("mime-apps"), "--terminals"], (code, out) => {
            try { const s = Object.assign({}, root.appState); s.terminal = JSON.parse(out); root.appState = s; } catch (e) {}
        });
    }
    Component.onCompleted: refresh()

    function choose(kind, app) {
        const k = kinds.find(x => x.id === kind);
        if (!k) return;
        const done = code => {
            if (code !== 0) { Nav.toast("Не удалось выбрать приложение"); return; }
            const s = Object.assign({}, appState);
            s[kind] = Object.assign({}, s[kind] || { apps: [] }, { default: app });
            appState = s;
            Nav.toast(k.title + ": " + appName(app));
        };
        if (kind === "terminal")
            Exec.run(["sh", "-c", "mkdir -p \"${XDG_CONFIG_HOME:-$HOME/.config}\" && printf '%s\\n' \"$1\" > \"${XDG_CONFIG_HOME:-$HOME/.config}/xdg-terminals.list\"", "sh", app],
                     { label: "терминал по умолчанию " + app, home: true, toast: false, done: done });
        else
            Exec.run(["xdg-mime", "default", app].concat(k.mimes), { label: k.title + " по умолчанию " + app, home: true, toast: false, done: done });
    }

    Card {
        title: "Чем открывать"
        Rows {
            Repeater {
                model: root.kinds
                delegate: SettingRow {
                    id: krow
                    required property var modelData
                    readonly property var st: root.appState[modelData.id] || ({ default: "", apps: [] })
                    icon: modelData.icon
                    title: modelData.title
                    subtitle: st.apps.length === 0 ? "Нет подходящих приложений" : st.apps.length === 1 ? "Установлено одно подходящее приложение" : "Подходящих приложений: " + st.apps.length
                    Select {
                        text: krow.st.default ? root.appName(krow.st.default) : "Не выбрано"
                        icon: krow.st.default ? root.appIcon(krow.st.default) : ""
                        enabled: krow.st.apps.length > 0
                        onClicked: { picker.kind = krow.modelData.id; picker.title = krow.modelData.title; picker.openWith(); }
                    }
                }
            }
        }
    }

    Picker {
        id: picker
        property string kind: ""
        searchHint: "Приложение"
        readonly property var st: root.appState[kind] || ({ default: "", apps: [] })
        current: st.default
        model: st.apps.map(a => ({ value: a, label: root.appName(a), sub: a, icon: root.appIcon(a) }))
        onPicked: v => root.choose(kind, v)
    }

    Connections {
        target: Nav
        function onAction(name, arg) {
            if (name === "defaultapps.pick") { picker.kind = arg; picker.title = (root.kinds.find(k => k.id === arg) || {}).title || ""; picker.openWith(); }
            else if (name === "defaultapps.set") { const p = arg.split(" "); root.choose(p[0], p[1]); }
        }
    }
}
