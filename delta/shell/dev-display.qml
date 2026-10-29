import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.common
import qs.common.ui
import qs.wallpaper
import qs.display
import "settings/sections" as Sections

// Отладка модуля «Экран»: раздел настроек в отдельном окне.
//   DELTA_DEV_NAME=display DELTA_DEV_HIDDEN=1 DELTA_SHELL_ENTRY=delta/shell/dev-display.qml tools/delta-dev.sh nested 300
// С моком трёх мониторов (HDR, DDC, подсветка) — DELTA_DISPLAYS_MOCK=…/display/mock/monitors.json
// (переменную нужно передать вложенной сессии: она наследует окружение).
//
// Ввод мыши во вложенную сессию не подать, поэтому состояния — через IPC:
//   tools/delta-dev.sh ipc call display select DP-1
//   tools/delta-dev.sh ipc call display mode DP-1 2560x1440@143.97
//   tools/delta-dev.sh ipc call display apply      → окно «Оставить?»
//   tools/delta-dev.sh ipc call display countdown 4 · keep · revert · scroll 600
ShellRoot {
    id: root

    Variants {
        model: Quickshell.screens
        delegate: Wallpaper { required property ShellScreen modelData; screen: modelData }
    }

    // Вложенный Hyprland сам выбирает масштаб 2 для окна 1280×800 — тогда окно
    // 860×640 не помещается. Ставим 1, только во вложенной сессии и только
    // в её экземпляре (подпись из нашего окружения). Quickshell перезагружает
    // конфиг при каждой правке файлов в shell/ — если монитор уже сохранён
    // через раздел, его масштаб не трогаем.
    function fitScreen() {
        const sig = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "";
        const saved = Settings.get("monitors", []);
        if (Quickshell.env("DELTA_NESTED") && sig && Quickshell.screens.length > 0 && !(Array.isArray(saved) && saved.length > 0)) {
            const s = Quickshell.screens[0];
            Quickshell.execDetached(["hyprctl", "-i", sig, "-q", "eval",
                'hl.monitor({ output = "' + s.name + '", mode = "1280x800@60", position = "0x0", scale = 1 })']);
        }
    }
    // настройки читаются не мгновенно — решаем, когда они готовы
    Connections { target: Settings; function onReadyChanged() { if (Settings.ready) root.fitScreen(); } }
    Component.onCompleted: {
        if (Settings.ready) fitScreen();
        // ночной свет и яркость «просыпаются», только если на них ссылаются
        console.info("[delta] dev-display: мок=" + Displays.mock + ", hyprsunset=" + NightLight.installed + ", яркость=" + Brightness.available);
    }

    FloatingWindow {
        id: win
        title: "Delta — Экран"
        implicitWidth: 860
        implicitHeight: 640
        color: "transparent"

        Glass {
            anchors.fill: parent
            strong: true

            Flickable {
                id: flick
                anchors { fill: parent; margins: 1 }
                contentWidth: width
                contentHeight: holder.height + 48
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                Column {
                    id: holder
                    x: (flick.width - width) / 2
                    y: 20
                    width: Math.min(720, flick.width - 56)
                    spacing: 14

                    Label { text: sec.title; size: "h1" }
                    Sections.Display { id: sec; width: parent.width }
                }
            }
        }
    }

    IpcHandler {
        target: "display"

        function state(): string {
            return JSON.stringify({
                mock: Displays.mock, canWrite: Displays.canWrite, selected: sec.selected, dirty: sec.dirty,
                pending: Displays.pending, countdown: Displays.countdown, error: Displays.error,
                primary: Displays.primaryName, setKey: Displays.setKey,
                draft: sec.draft, monitors: Displays.monitors.map(m => ({ name: m.name, key: m.key, hdr: m.hdr.hdr, maxLum: m.hdr.maxLuminance,
                    w: m.width, h: m.height, hz: m.refreshRate, x: m.x, y: m.y, scale: m.scale, transform: m.transform, disabled: m.disabled, mirrorOf: m.mirrorOf })),
                brightness: Brightness.devices, nightLight: { installed: NightLight.installed, active: NightLight.active, zone: NightLight.zone, sun: NightLight.sunToday }
            });
        }
        function select(name: string): void { sec.selected = name; }
        function mode(name: string, mode: string): void {
            const p = /^(\d+)x(\d+)@([\d.]+)$/.exec(mode);
            if (p) sec.edit(name, { mode: { w: parseInt(p[1]), h: parseInt(p[2]), hz: parseFloat(p[3]) } });
        }
        function scale(name: string, s: real): void { sec.edit(name, { scale: s }); }
        function rotate(name: string, t: int): void { sec.edit(name, { transform: t }); }
        // произвольная правка черновика: patch display DP-1 '{"hdr":true}'
        function patch(name: string, json: string): void { sec.edit(name, JSON.parse(json)); }
        function drop(name: string, x: int, y: int): void { sec.dropAt(name, x, y); }
        function openResolution(): void { sec.openResolution(); }
        function apply(): void { sec.apply(); }
        function reset(): void { sec.reset(); }
        function keep(): void { Displays.keep(); }
        function revert(): void { Displays.revert(); }
        // показать отсчёт на нужной секунде (таймер продолжит с неё)
        function countdown(n: int): void { Displays.countdown = n; }
        function scroll(y: int): void { flick.contentY = Math.max(0, Math.min(y, flick.contentHeight - flick.height)); }
        function primary(name: string): void { Displays.setPrimary(name); }
        function brightness(name: string, v: real): void { Brightness.setFor(name, v); }
        function nightPretend(on: bool): void { NightLight.pretendInstalled = on; }
        function set(key: string, json: string): void { Settings.set(key, JSON.parse(json)); }
    }
}
