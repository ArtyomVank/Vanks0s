pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.common
import qs.common.ui
import qs.settings.parts

// Окно «Как открыть программу?» для .exe/.msi: обычно (Wine системы) или
// через лаунчер — Proton CachyOS (Авто — самый свежий) или Wine в отдельном
// префиксе. «Всегда так» запоминает выбор для этой программы (exe.excluded /
// exe.always), поменять — «Настройки» → «Рекомендации». Запускает delta-exe --run.
// Установщик (setup.exe, .msi) через лаунчер ставит программу в свой префикс:
// delta-exe --install — её ярлыки потом появляются в меню приложений.
FloatingWindow {
    id: win

    readonly property string file: Quickshell.env("DELTA_EXE_FILE") || ""
    readonly property string fileName: file.split("/").pop()
    readonly property string key: fileName.toLowerCase()

    property string mode: "launcher"      // normal · launcher
    property string runner: "auto"        // auto · proton · wine
    property string protonPath: ""
    property bool always: false
    // похоже на установщик — по умолчанию ставим программу, а не просто запускаем
    readonly property bool looksInstaller: /(setup|install|инстал|\.msi$)/i.test(fileName)
    property bool install: looksInstaller
    // имя программы: без расширения, «setup», версий и подчёркиваний; у
    // безликого setup.exe — по папке, в которой он лежит («REPO v0.4 by X»)
    function cleanName(n) {
        return n.replace(/\.(exe|msi)$/i, "")
            .replace(/[_.]+/g, " ")
            .replace(/\b(setup|installer|install|win(32|64)?|x(64|86)|v?\d+(\s\d+)*)\b/gi, " ")
            .replace(/\b(by|repack)\b.*$/i, " ")
            .replace(/[()\[\]]/g, " ")
            .replace(/\s+/g, " ").replace(/^[\s-]+|[\s-]+$/g, "");
    }
    property string appName: cleanName(fileName) || cleanName(file.split("/").slice(-2, -1)[0] || "") || fileName
    property var info: ({ protons: [], wine: false, umu: false })
    readonly property bool canRun: file.length > 0 && (mode === "normal" || runner === "wine" ? info.wine
        : runner === "proton" ? protonPath.length > 0 : true)

    title: I18n.tr("Как открыть программу?")
    implicitWidth: 600
    implicitHeight: 680
    minimumSize: Qt.size(520, 600)
    color: "transparent"

    onClosed: Qt.quit()

    Process {
        running: true
        command: ["delta-exe", "--runners"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { win.info = JSON.parse(text); } catch (e) {}
                if (win.info.protons.length > 0) win.protonPath = win.info.protons[0].path;
            }
        }
    }

    function launch() {
        if (!canRun) return;
        let cmd;
        if (mode === "normal") {
            cmd = ["delta-exe", "--run", "normal", file];
            if (always) {
                const list = (Settings.get("exe.excluded", []) || []).filter(n => n.toLowerCase() !== key);
                list.push(key);
                Settings.set("exe.excluded", list);
            }
        } else if (install) {
            const r = runner === "proton" ? "proton:" + protonPath : runner;
            cmd = ["delta-exe", "--install", r, file, appName.trim() || fileName];
        } else {
            const r = runner === "proton" ? "proton:" + protonPath : runner;
            cmd = ["delta-exe", "--run", "launcher", r, file];
            if (always) {
                const map = Object.assign({}, Settings.get("exe.always", {}) || {});
                map[key] = r;
                Settings.set("exe.always", map);
            }
        }
        Settings.flush();
        Sounds.play("oobe-step", 0);
        Quickshell.execDetached(cmd);
        Qt.callLater(Qt.quit);
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.glass2
        border.width: 1
        border.color: Theme.line

        ColumnLayout {
            anchors { fill: parent; margins: 26 }
            spacing: 16

            // --- что открываем ---
            RowLayout {
                spacing: 14
                Layout.fillWidth: true
                Rectangle {
                    implicitWidth: 52; implicitHeight: 52; radius: 16
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2)
                    Sym { anchors.centerIn: parent; name: "gamepad"; size: 26; color: Theme.accent }
                }
                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true
                    Label { text: I18n.tr("Как открыть программу?"); size: "h1"; Layout.fillWidth: true }
                    Label { text: win.fileName; tone: 2; font.family: Theme.fontMono; Layout.fillWidth: true }
                }
            }

            // --- обычно или через лаунчер ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Repeater {
                    model: [
                        { id: "normal", icon: "file", name: "Открыть обычно", hint: "Wine системы, как любую программу" },
                        { id: "launcher", icon: "rocket", name: "Через лаунчер", hint: "Proton CachyOS — лучше для игр" }
                    ]
                    delegate: Rectangle {
                        id: opt
                        required property var modelData
                        readonly property bool on: win.mode === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: 108
                        radius: 20
                        color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : optTap.containsMouse ? Theme.soft2 : Theme.soft
                        border.width: on ? 2 : 1
                        border.color: on ? Theme.accent : Theme.line
                        scale: optTap.pressed ? 0.96 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }
                        Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
                        ColumnLayout {
                            anchors { fill: parent; margins: 16 }
                            spacing: 4
                            Sym { name: opt.modelData.icon; size: 24; color: opt.on ? Theme.accent : Theme.fg2 }
                            Label { text: I18n.tr(opt.modelData.name); font.weight: Font.DemiBold; Layout.fillWidth: true; Layout.topMargin: 4 }
                            Label { text: I18n.tr(opt.modelData.hint); tone: 3; size: "small"; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }
                        MouseArea {
                            id: optTap
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { win.mode = opt.modelData.id; Sounds.play("oobe-select", 60); }
                        }
                    }
                }
            }

            // --- чем запускать ---
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10
                opacity: win.mode === "launcher" ? 1 : 0.35
                enabled: win.mode === "launcher"
                Behavior on opacity { NumberAnimation { duration: Theme.anim.normal } }

                Label { text: I18n.tr("Чем запускать"); font.weight: Font.DemiBold }
                Chips {
                    Layout.fillWidth: true
                    model: [
                        { value: "auto", label: I18n.tr("Авто") },
                        { value: "proton", label: "Proton CachyOS" },
                        { value: "wine", label: "Wine" }
                    ]
                    current: win.runner
                    onPicked: v => { win.runner = v; Sounds.play("oobe-select", 60); }
                }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    tone: 3
                    size: "small"
                    text: win.runner === "auto"
                        ? (win.info.protons.length > 0
                            ? I18n.tr("Самый свежий Proton CachyOS:") + " " + win.info.protons[0].name
                            : I18n.tr("Последний Proton CachyOS скачается с GitHub при первом запуске (около 500 МБ)"))
                        : win.runner === "wine"
                            ? (win.info.wine ? I18n.tr("Wine системы, у программы свой префикс") : I18n.tr("Wine не установлен"))
                            : win.info.protons.length === 0 ? I18n.tr("Proton CachyOS ещё не скачан — выберите «Авто»") : ""
                }
                // установленные версии Proton CachyOS
                Chips {
                    Layout.fillWidth: true
                    visible: win.runner === "proton" && win.info.protons.length > 0
                    model: win.info.protons.map(p => ({ value: p.path, label: p.name }))
                    current: win.protonPath
                    onPicked: v => win.protonPath = v
                }
                RowLayout {
                    visible: !win.info.umu && win.runner !== "wine"
                    Layout.fillWidth: true
                    spacing: 10
                    Label {
                        text: I18n.tr("Без umu-launcher Proton запустится напрямую — с ним совместимость лучше")
                        tone: 3; size: "small"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    Btn {
                        text: I18n.tr("Поставить")
                        icon: "download"
                        onClicked: Quickshell.execDetached(["pkexec", "delta-setup", "install", "umu-launcher"])
                    }
                }
            }

            // --- установить программу ---
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: win.mode === "launcher"
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true
                        Label { text: I18n.tr("Это установщик — поставить программу"); font.weight: Font.DemiBold; Layout.fillWidth: true }
                        Label {
                            text: I18n.tr("Программа получит свою папку Windows, её ярлыки появятся в меню приложений")
                            tone: 3; size: "small"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                        }
                    }
                    Toggle { checked: win.install; onToggled: v => { win.install = v; Sounds.play("pop", 60); } }
                }
                Field {
                    Layout.fillWidth: true
                    visible: win.install
                    icon: "edit"
                    placeholder: I18n.tr("Название программы")
                    text: win.appName
                    onTextChanged: win.appName = text
                }
            }

            Item { Layout.fillHeight: true }

            // --- «всегда так» и кнопки ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                // установщик запускают один раз — запоминать нечего
                visible: !(win.mode === "launcher" && win.install)
                Rectangle {
                    implicitWidth: 22; implicitHeight: 22; radius: 7
                    color: win.always ? Theme.accent : "transparent"
                    border.width: win.always ? 0 : 2
                    border.color: Theme.fg3
                    Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
                    Sym { anchors.centerIn: parent; name: "check"; size: 14; color: Theme.onAccent; visible: win.always; scale: win.always ? 1 : 0
                          Behavior on scale { NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.OutBack; easing.overshoot: 3 } } }
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: { win.always = !win.always; Sounds.play("pop", 40); } }
                }
                Label {
                    text: I18n.tr("Всегда так для этой программы")
                    Layout.fillWidth: true
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { win.always = !win.always; Sounds.play("pop", 40); } }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Btn {
                    text: I18n.tr("Все программы")
                    icon: "apps"
                    kind: "ghost"
                    onClicked: { Quickshell.execDetached(["delta-exe", "--manager"]); Qt.quit(); }
                }
                Item { Layout.fillWidth: true }
                Btn { text: I18n.tr("Отмена"); kind: "ghost"; onClicked: Qt.quit() }
                Btn {
                    text: win.mode === "launcher" && win.install ? I18n.tr("Установить") : I18n.tr("Запустить")
                    icon: win.mode === "launcher" && win.install ? "download" : "play"
                    kind: "accent"
                    enabled: win.canRun
                    onClicked: win.launch()
                }
            }
        }
    }

    Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
    Shortcut { sequences: ["Return", "Enter"]; onActivated: win.launch() }
}
