pragma Singleton

import QtQuick
import Quickshell
import qs.common

// Что может показывать оверлей в игре и как это сказать MangoHud.
//   catalog       [{ id, label, mango: [ключи MangoHud] }]
//   mangoActive   сессию запустили с MangoHud (delta-session: MANGOHUD=1 и
//                 MANGOHUD_CONFIGFILE — файл, который пишет PlayHud)
//   mangoConf(on, items, corner)  текст конфигурации MangoHud
// MangoHud перечитывает свой файл на лету: оверлей включается и меняется
// прямо в запущенной игре.
Singleton {
    readonly property var catalog: [
        { id: "fps",       label: "FPS",          mango: ["fps"] },
        { id: "frametime", label: "Время кадра",  mango: ["frametime", "frame_timing"] },
        { id: "cpu",       label: "Процессор",    mango: ["cpu_stats", "cpu_temp"] },
        { id: "gpu",       label: "Видеокарта",   mango: ["gpu_stats", "gpu_temp"] },
        { id: "ram",       label: "Память",       mango: ["ram"] },
        { id: "vram",      label: "Видеопамять",  mango: ["vram"] },
        { id: "time",      label: "Часы",         mango: ["time"] },
        { id: "battery",   label: "Батарея",      mango: ["battery"] }
    ]
    readonly property var defaults: ["fps", "cpu", "gpu", "ram"]

    readonly property string mangoFile: Quickshell.env("MANGOHUD_CONFIGFILE") || ""
    readonly property bool mangoActive: Quickshell.env("MANGOHUD") === "1" && mangoFile !== ""

    function hex(c) {
        const h = v => ("0" + Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16)).slice(-2);
        return (h(c.r) + h(c.g) + h(c.b)).toUpperCase();
    }
    function mangoConf(on, items, corner) {
        // выключен — MangoHud остаётся в игре, но ничего не рисует
        if (!on) return "no_display\n";
        const pos = { tl: "top-left", tr: "top-right", bl: "bottom-left", br: "bottom-right" }[corner] || "top-left";
        const lines = [
            "# пишет Delta (play/PlayHud.qml) — меняйте в игровой панели Super+G",
            "legacy_layout=0", "horizontal", "hud_compact", "hud_no_margin",
            "position=" + pos, "offset_x=14", "offset_y=14",
            "round_corners=12", "background_alpha=0.5", "background_color=" + hex(Theme.base),
            "font_size=20", "text_color=FFFFFF",
            "fps_color_change", "fps_value=30,60", "fps_color=FF6B6B,F09A2B," + hex(Theme.accent),
            "cpu_color=" + hex(Theme.accent), "gpu_color=" + hex(Theme.accent),
            "ram_color=" + hex(Theme.accent), "vram_color=" + hex(Theme.accent),
            "toggle_hud=Shift_R+F12"
        ];
        for (const it of catalog)
            if (items.indexOf(it.id) !== -1) for (const k of it.mango) lines.push(k);
        return lines.join("\n") + "\n";
    }
}
