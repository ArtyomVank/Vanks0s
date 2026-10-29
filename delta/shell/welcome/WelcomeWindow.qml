pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.common
import qs.common.ui
import qs.settings
import qs.settings.parts
import qs.welcome

// Помощник «Добро пожаловать»: при первом входе предлагает поставить
// библиотеки для игр, драйвер видеокарты этого компьютера и приложения.
// Всё ставится одним нажатием: pkexec delta-setup install … (пароль спрашивает
// окно polkit оболочки), ход установки виден внизу окна.
// Закрыли — при входе больше не появляется (welcome.done); открыть снова —
// «Настройки» → «Рекомендации» или delta-welcome.
FloatingWindow {
    id: win

    property bool quitOnClose: true
    property int tab: 0

    // установка
    property bool installing: false
    property string stage: ""
    property string lastLine: ""
    property string error: ""
    property bool needReboot: false
    property bool finished: false
    property var afterInstall: null

    readonly property var current: Catalog.tabs[tab]
    readonly property var planned: Catalog.plan(Catalog.chosen)
    readonly property int total: planned.pkgs.length + planned.aur.length

    title: I18n.tr("Добро пожаловать")
    implicitWidth: 1000
    implicitHeight: 680
    minimumSize: Qt.size(820, 560)
    color: "transparent"

    onClosed: dismiss()
    Component.onCompleted: openTab(Quickshell.env("DELTA_WELCOME_SECTION") || "")

    function openTab(name) {
        const i = Catalog.tabs.findIndex(t => t.id === name);
        if (i !== -1) tab = i;
    }
    // закрыли — больше не показываем при входе
    function dismiss() {
        Settings.set("welcome.done", true);
        Settings.flush();
        if (quitOnClose) Qt.callLater(Qt.quit);
        else visible = false;
    }
    function raise() {
        Hyprland.dispatch('hl.dsp.focus({ window = "class:^delta-welcome$" })');
    }

    function plural(n, one, few, many) {
        const a = n % 10, b = n % 100;
        return n + " " + (a === 1 && b !== 11 ? one : a >= 2 && a <= 4 && (b < 12 || b > 14) ? few : many);
    }

    function install(items, then) {
        if (installing) return;
        const p = Catalog.plan(items);
        if (p.pkgs.length + p.aur.length === 0) { if (then) then(); return; }
        const cmd = ["pkexec", "delta-setup", "install"].concat(p.pkgs, p.aur.length ? ["--aur"].concat(p.aur) : []);
        installing = true;
        finished = false;
        error = "";
        stage = "Ждём пароль администратора";
        lastLine = "";
        afterInstall = then || null;
        if (Exec.dryRun) {
            // пробный режим: весь путь интерфейса без установки
            Exec.run(cmd, { label: I18n.tr("установка рекомендованного"), done: () => finish(0, "") });
            return;
        }
        proc.command = cmd;
        proc.running = true;
    }
    function finish(code, err) {
        installing = false;
        if (code === 0) {
            finished = true;
            stage = "";
            Catalog.picked = ({});
            Catalog.refresh();
            Nav.toast(needReboot ? I18n.tr("Готово — перезагрузите компьютер") : I18n.tr("Всё установлено"));
            boom.burst(width / 2, height - 90);
            Sounds.play("oobe-done", 0);
            if (afterInstall) afterInstall();
        } else if (code === 126 || code === 127) {
            stage = "";
            Nav.toast("Установка отменена");
        } else {
            stage = "";
            error = err || "Установка не удалась";
        }
        afterInstall = null;
    }

    // магазин: GNOME Software с Flathub; нет — сначала ставим
    function openStore() {
        const launch = () => Quickshell.execDetached(["gnome-software"]);
        if (Catalog.isInstalled(Catalog.store)) launch();
        else install([Catalog.store], launch);
    }

    Process {
        id: proc
        property string errText: ""
        onStarted: errText = ""
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("::step:: ")) win.stage = line.slice(9);
                else if (line === "::reboot::") win.needReboot = true;
                else if (line.trim().length) win.lastLine = line.trim();
            }
        }
        stderr: SplitParser { onRead: line => { if (line.trim().length) proc.errText = line.trim(); } }
        onExited: code => win.finish(code, proc.errText)
    }

    Glass {
        anchors.fill: parent
        strong: true
        radius: 0
        border.width: 0
    }

    // мягкое свечение акцента за шапкой
    Rectangle {
        width: parent.width * 0.9
        height: 320
        x: -width * 0.25
        y: -height * 0.55
        radius: height / 2
        opacity: 0.22
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.accent }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    ColumnLayout {
        anchors { fill: parent; margins: 28; topMargin: 26; bottomMargin: 22 }
        spacing: 20

        // ---- шапка ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            Rectangle {
                implicitWidth: 56; implicitHeight: 56; radius: 18
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.25) }
                    GradientStop { position: 1; color: Theme.accent }
                }
                Label { anchors.centerIn: parent; text: "V"; size: "h1"; font.weight: Font.Black; color: Theme.onAccent }
            }
            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true
                Label { text: I18n.tr("Добро пожаловать в Vanks OS"); size: "h1"; Layout.fillWidth: true }
                Label {
                    text: I18n.tr("Отметьте, что поставить, — остальное система сделает сама. Вернуться сюда можно из «Настроек».")
                    tone: 2; Layout.fillWidth: true
                }
            }
            Btn { icon: "close"; onClicked: win.dismiss() }
        }

        // ---- разделы ----
        Item {
            Layout.fillWidth: true
            implicitHeight: 76

            // подсветка выбранного раздела переезжает с пружиной
            Rectangle {
                id: hl
                readonly property real w: (parent.width - 2 * 12) / 3
                width: w
                height: parent.height
                x: win.tab * (w + 12)
                radius: 20
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                border.width: 1.5
                border.color: Theme.accent
                Behavior on x { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
            }

            Row {
                anchors.fill: parent
                spacing: 12
                Repeater {
                    model: Catalog.tabs
                    delegate: Rectangle {
                        id: tabCard
                        required property var modelData
                        required property int index
                        readonly property bool cur: win.tab === index
                        readonly property int n: { void Catalog.picked; void Catalog.installed; return Catalog.count(modelData); }
                        width: hl.w
                        height: parent.height
                        radius: 20
                        color: cur ? "transparent" : tabTap.containsMouse ? Theme.soft2 : Theme.soft
                        border.width: cur ? 0 : 1
                        border.color: Theme.line
                        Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
                        scale: tabTap.pressed ? 0.97 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.anim.fast } }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                            spacing: 12
                            Rectangle {
                                implicitWidth: 42; implicitHeight: 42; radius: 14
                                color: tabCard.cur ? Theme.accent : Theme.soft2
                                Behavior on color { ColorAnimation { duration: Theme.anim.normal } }
                                Sym { anchors.centerIn: parent; name: tabCard.modelData.icon; size: 21; color: tabCard.cur ? Theme.onAccent : Theme.fg2 }
                            }
                            ColumnLayout {
                                spacing: 1
                                Layout.fillWidth: true
                                Label { text: tabCard.modelData.title; size: "title"; Layout.fillWidth: true }
                                Label {
                                    text: tabCard.n > 0 ? "Выбрано: " + tabCard.n : tabCard.modelData.items.every(it => Catalog.isInstalled(it)) ? "Всё на месте" : "Ничего не выбрано"
                                    tone: 3; size: "small"; Layout.fillWidth: true
                                }
                            }
                        }
                        MouseArea {
                            id: tabTap
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.tab = tabCard.index
                        }
                    }
                }
            }
        }

        // ---- пункты раздела ----
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 10
            boundsBehavior: Flickable.StopAtBounds
            // пересоздаём строки при смене раздела — они въезжают заново
            model: Catalog.detected ? win.current.items : []
            header: Loader {
                width: list.width
                sourceComponent: win.current.id === "drivers" ? gpuCard : win.current.id === "apps" ? storeCard : null
            }
            delegate: ItemRow {
                required property var modelData
                required property int index
                width: list.width
                item: modelData
                busy: win.installing
            }

            Label {
                anchors.centerIn: parent
                visible: !Catalog.detected
                text: I18n.tr("Смотрим, что за компьютер…")
                tone: 3
            }
        }

        // ---- низ: что будет установлено ----
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 64
            radius: 20
            color: Theme.soft
            border.color: Theme.line
            clip: true

            // бегущая полоса, пока идёт установка
            Rectangle {
                id: runner
                visible: win.installing
                anchors.bottom: parent.bottom
                width: parent.width * 0.3
                height: 3
                radius: 2
                color: Theme.accent
                NumberAnimation on x {
                    running: win.installing
                    from: -runner.width; to: runner.parent.width
                    duration: 1400; loops: Animation.Infinite
                    easing.type: Easing.InOutSine
                }
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 20; rightMargin: 12 }
                spacing: 12
                Sym {
                    name: win.error ? "warning" : win.installing ? "refresh" : win.finished ? "check" : "download"
                    size: 22
                    color: win.error ? "#E5484D" : win.finished && !win.installing ? "#3FB37A" : Theme.accent
                    RotationAnimation on rotation { running: win.installing; from: 0; to: 360; duration: 1200; loops: Animation.Infinite; alwaysRunToEnd: true }
                }
                ColumnLayout {
                    spacing: 1
                    Layout.fillWidth: true
                    Label {
                        Layout.fillWidth: true
                        font.weight: Font.DemiBold
                        text: win.installing ? win.stage
                            : win.error ? "Не получилось"
                            : win.total > 0 ? "Будет установлено: " + win.plural(win.total, "пакет", "пакета", "пакетов")
                            : win.finished ? (win.needReboot ? "Готово — нужна перезагрузка" : "Готово")
                            : "Всё выбранное уже стоит"
                    }
                    Label {
                        Layout.fillWidth: true
                        tone: 3; size: "small"
                        text: win.installing ? (win.lastLine || "Можно свернуть окно — установка продолжится")
                            : win.error ? win.error
                            : win.planned.aur.length ? "Драйвер NVIDIA соберётся из AUR — это несколько минут"
                            : win.total > 0 ? "Понадобится интернет и пароль администратора"
                            : "Что-то ещё всегда можно найти в магазине"
                    }
                }
                Btn {
                    text: I18n.tr("Перезагрузить")
                    visible: win.finished && win.needReboot && !win.installing
                    onClicked: Exec.run(["systemctl", "reboot"], { label: I18n.tr("перезагрузка") })
                }
                Btn {
                    text: win.total > 0 ? "Установить" : "Закрыть"
                    icon: win.total > 0 ? "download" : ""
                    kind: "accent"
                    enabled: !win.installing
                    onClicked: win.total > 0 ? win.install(Catalog.chosen) : win.dismiss()
                }
            }
        }
    }

    Component {
        id: gpuCard
        Item {
            implicitHeight: gpuBox.implicitHeight + 12
            Rectangle {
                id: gpuBox
                width: parent.width
                implicitHeight: gpuCol.implicitHeight + 28
                radius: 18
                color: "transparent"
                border.color: Theme.line
                RowLayout {
                    id: gpuCol
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 18; rightMargin: 18 }
                    spacing: 12
                    Sym { name: "monitor"; size: 20; color: Theme.fg2 }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: Catalog.gpus.length === 0 ? "Видеокарту определить не удалось — ниже то, что подойдёт любому компьютеру"
                            : (Catalog.gpus.length > 1 ? "Видеокарты: " : "Ваша видеокарта: ") + Catalog.gpus.map(g => g.name).join(" и ")
                        tone: 2
                    }
                }
            }
        }
    }

    Component {
        id: storeCard
        Item {
            implicitHeight: storeBox.height + 12
            Rectangle {
                id: storeBox
                width: parent.width
                height: 84
                radius: 18
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28) }
                    GradientStop { position: 1; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.06) }
                }
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.4)
                RowLayout {
                    anchors { fill: parent; leftMargin: 18; rightMargin: 16 }
                    spacing: 14
                    Rectangle {
                        implicitWidth: 48; implicitHeight: 48; radius: 16
                        color: Theme.accent
                        Sym { anchors.centerIn: parent; name: "store"; size: 24; color: Theme.onAccent }
                    }
                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true
                        Label { text: I18n.tr("Магазин приложений"); size: "title"; Layout.fillWidth: true }
                        Label {
                            text: Catalog.isInstalled(Catalog.store) ? "Тысячи программ из Arch и Flathub — ищите, ставьте, обновляйте"
                                                                     : "Тысячи программ из Arch и Flathub. Сначала поставим сам магазин"
                            tone: 2; size: "small"; Layout.fillWidth: true
                        }
                    }
                    Btn { text: I18n.tr("Открыть магазин"); kind: "accent"; icon: "store"; enabled: !win.installing; onClicked: win.openStore() }
                }
            }
        }
    }

    Item {
        anchors.fill: parent
        z: 50
        Component.onCompleted: Nav.overlay = this
        Toast {}
    }

    Shortcut { sequences: ["Ctrl+Q", "Ctrl+W", "Escape"]; onActivated: win.dismiss() }
    Shortcut { sequence: "Ctrl+Tab"; onActivated: win.tab = (win.tab + 1) % 3 }

    //   delta-welcome ipc call welcome open drivers
    IpcHandler {
        target: "welcome"

        function open(section: string): void {
            win.openTab(section);
            win.visible = true;
            win.raise();
        }
        function toggle(id: string): void {
            const it = Catalog.libs.concat(Catalog.drivers, Catalog.apps).find(x => x.id === id);
            if (it) Catalog.toggle(it);
        }
        function install(): void { if (win.total > 0) win.install(Catalog.chosen); }
        function store(): void { win.openStore(); }
        // как крестик: закрыть и больше не показывать при входе
        function close(): void { win.dismiss(); }
        function state(): string {
            return JSON.stringify({ tab: win.current.id, gpus: Catalog.gpus, kernels: Catalog.kernels, multilib: Catalog.multilib,
                                    plan: win.planned, installing: win.installing, finished: win.finished, dryRun: Exec.dryRun,
                                    journal: Exec.journal.map(j => j.cmd) });
        }
        function quit(): void { Qt.quit(); }
    }

    // установилось — залп конфетти
    Confetti { id: boom; anchors.fill: parent; z: 100 }
}
