-- Delta — базовый конфиг Hyprland.
--
-- Этот файл принадлежит пакету delta и перезаписывается при обновлении.
-- Не правьте его: всё, что меняется в «Настройках», delta-apply пишет в
--   ~/.config/delta/hypr/generated.lua
-- а свои правки можно положить в
--   ~/.config/delta/hypr/user.lua
-- Оба файла подключаются в конце и перекрывают значения отсюда.

local home   = os.getenv("HOME") or ""
local cfgdir = (os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")) .. "/delta"
local data   = os.getenv("DELTA_DATA") or "/usr/share/delta"

local function include(path)
    local f = io.open(path, "r")
    if not f then return false end
    f:close()
    dofile(path)
    return true
end

------------------
---- МОНИТОРЫ ----
------------------

-- Запасное правило для любого монитора. Сохранённые режимы конкретных
-- мониторов приходят из generated.lua.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

-------------------
---- ОКРУЖЕНИЕ ----
-------------------

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
-- оформление Qt-программ: theme-apply пишет qt6ct.conf и палитру из темы Delta
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-------------------
---- ВНЕШНИЙ ВИД ----
-------------------

hl.config({
    general = {
        gaps_in     = 6,
        gaps_out    = 14,
        border_size = 2,
        col = {
            active_border   = "rgba(7c5cffee)",
            inactive_border = "rgba(ffffff1a)",
        },
        resize_on_border = true,
        layout = "dwindle",
    },

    decoration = {
        rounding       = 16,
        rounding_power = 2.4,
        shadow = {
            enabled      = true,
            range        = 18,
            render_power = 3,
            color        = 0x55000000,
        },
        blur = {
            enabled  = true,
            size     = 6,
            passes   = 3,
            vibrancy = 0.17,
            popups   = true,
        },
    },

    animations = { enabled = true },

    misc = {
        force_default_wallpaper  = 0,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        background_color         = 0x14141a,
        -- оболочка сама показывает экран блокировки; если она упадёт,
        -- разрешаем перезапустить её, не теряя сессию
        allow_session_lock_restore = true,
        focus_on_activate        = true,
        -- XDG_CURRENT_DESKTOP=Delta:Hyprland задаёт delta-session намеренно
        disable_xdg_env_checks   = true,
        animate_manual_resizes   = true,
    },

    ecosystem = {
        no_update_news    = true,
        no_donation_nag   = true,
    },

    dwindle = { preserve_split = true },
})

-- Кривые Delta: пружины для окон, мягкий bezier для затухания.
hl.curve("deltaOut",   { type = "bezier", points = { {0.22, 1},    {0.36, 1} } })
hl.curve("deltaInOut", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1} } })
hl.curve("linear",     { type = "bezier", points = { {0, 0},       {1, 1}    } })
hl.curve("deltaSpring",{ type = "spring", mass = 1, stiffness = 260, dampening = 22 })
hl.curve("deltaSoft",  { type = "spring", mass = 1, stiffness = 180, dampening = 20 })

hl.animation({ leaf = "global",        enabled = true, speed = 8,   bezier = "deltaOut" })
hl.animation({ leaf = "border",        enabled = true, speed = 5,   bezier = "deltaOut" })
hl.animation({ leaf = "windows",       enabled = true, speed = 5,   spring = "deltaSpring" })
-- «окно собирается»: появляется из 80 % с пружиной
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.2, spring = "deltaSoft",  style = "popin 80%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.6, bezier = "deltaInOut", style = "popin 85%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.8, bezier = "deltaOut" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.5, bezier = "deltaOut" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 3,   spring = "deltaSpring", style = "slide" })
-- слои оболочки анимирует сама оболочка (капли, морфинг), поэтому у
-- них анимации Hyprland выключены правилом ниже
hl.animation({ leaf = "layers",        enabled = true, speed = 3,   bezier = "deltaOut", style = "fade" })

-- Все поверхности оболочки называются delta-*.
hl.layer_rule({
    name  = "delta-shell-surfaces",
    match = { namespace = "^delta-" },
    blur         = true,
    ignore_alpha = 0.35,
    no_anim      = true,
})
-- обои без размытия и без анимации
hl.layer_rule({
    name  = "delta-wallpaper",
    match = { namespace = "^delta-wallpaper$" },
    blur    = false,
    no_anim = true,
})

-- снимок окна при сворачивании: без размытия под ним, иначе мутный ореол
hl.layer_rule({
    name  = "delta-genie",
    match = { namespace = "^delta-genie$" },
    blur    = false,
    no_anim = true,
})

-- кнопки окна: прозрачный слой во весь экран, размытие ему не нужно
hl.layer_rule({
    name  = "delta-window-controls",
    match = { namespace = "^delta-window-controls$" },
    blur    = false,
    no_anim = true,
})

---------------
---- ВВОД ----
---------------

hl.config({
    input = {
        kb_layout    = "us,ru",
        kb_options   = "grp:alt_shift_toggle",
        repeat_rate  = 30,
        repeat_delay = 300,
        follow_mouse = 1,
        sensitivity  = 0,
        touchpad = {
            natural_scroll = true,
            tap_to_click   = true,
        },
    },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-----------------
---- КЛАВИШИ ----
-----------------

local mod = "SUPER"

-- Окна оболочки вызываются через глобальные сочетания (протокол
-- hyprland-global-shortcuts): без запуска процессов, без задержки.
-- Super, отпущенный без других клавиш — окно приложений.
hl.bind(mod .. " + SUPER_L", hl.dsp.global("delta:launcher"), { release = true })
hl.bind(mod .. " + S",       hl.dsp.global("delta:wallpapers"))
hl.bind(mod .. " + N",       hl.dsp.global("delta:notifications"))
hl.bind(mod .. " + W",       hl.dsp.global("delta:widgets"))
hl.bind(mod .. " + I",       hl.dsp.global("delta:settings"))
hl.bind(mod .. " + L",       hl.dsp.global("delta:lock"))
hl.bind(mod .. " + ESCAPE",  hl.dsp.global("delta:power"))

hl.bind(mod .. " + RETURN",  hl.dsp.exec_cmd("xdg-terminal-exec || kitty"))
hl.bind(mod .. " + E",       hl.dsp.exec_cmd("xdg-open " .. home))
hl.bind(mod .. " + Q",       hl.dsp.window.close())
hl.bind(mod .. " + H",       hl.dsp.global("delta:minimize"))
hl.bind(mod .. " + F",       hl.dsp.window.fullscreen())
hl.bind(mod .. " + V",       hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + J",       hl.dsp.layout("togglesplit"))

hl.bind(mod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + down",  hl.dsp.focus({ direction = "down" }))

for i = 1, 10 do
    local key = i % 10
    hl.bind(mod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end
hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Громкость и яркость: оболочка сама меняет значение и показывает OSD.
hl.bind("XF86AudioRaiseVolume",  hl.dsp.global("delta:volume-up"),      { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.global("delta:volume-down"),    { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.global("delta:volume-mute"),    { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.global("delta:mic-mute"),       { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.global("delta:brightness-up"),  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.global("delta:brightness-down"),{ locked = true, repeating = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("Print",          hl.dsp.global("delta:screenshot"))

-------------------------
---- ПРАВИЛА ОКОН ----
-------------------------

-- свёрнутые окна живут на скрытом спецстоле
hl.workspace_rule({ workspace = "special:minimized", gaps_out = 0 })

hl.window_rule({
    name  = "delta-settings",
    match = { class = "^delta-settings$" },
    float = true,
    size  = "1100 720",
    center = true,
    -- появление и закрытие рисует оболочка: капля из верхнего дока (SettingsGhost)
    no_anim = true,
})
hl.window_rule({
    name  = "delta-welcome",
    match = { class = "^delta-welcome$" },
    float = true,
    size  = "1000 680",
    center = true,
})
hl.window_rule({
    name  = "calamares",
    match = { class = "^(calamares|io.calamares.calamares)$" },
    float = true,
    size  = "1100 720",
    center = true,
})
hl.window_rule({
    name  = "dialogs-float",
    match = { class = "^(org.gnome.FileRoller|pavucontrol|blueman-manager|nm-connection-editor|xdg-desktop-portal-gtk)$" },
    float = true,
})

-------------------
---- АВТОЗАПУСК ----
-------------------

local nested = (os.getenv("DELTA_NESTED") or "") ~= ""

hl.on("hyprland.start", function()
    -- Вложенная сессия (разработка) не должна трогать окружение основной:
    -- иначе службы и порталы пользователя переедут на её дисплей, а
    -- автозапуск откроет вторые копии программ.
    if not nested then
        -- порталы и службы systemd --user должны знать про эту сессию
        hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE DELTA_DATA QT_QPA_PLATFORMTHEME")
        -- Hyprland сам не запускает XDG-автозапуск (~/.config/autostart, /etc/xdg/autostart)
        hl.exec_cmd("dex -a")
    end
    hl.exec_cmd("delta-shell")
    -- помощник первого запуска: после того как стол проявился; сам решает,
    -- нужно ли показываться (закрывали, live-ISO, вложенная сессия)
    hl.exec_cmd("sh -c 'sleep 3; exec delta-welcome --first-run'")
end)

----------------------------------
---- НАСТРОЙКИ ПОЛЬЗОВАТЕЛЯ ----
----------------------------------

include(cfgdir .. "/hypr/generated.lua")
include(cfgdir .. "/hypr/user.lua")
