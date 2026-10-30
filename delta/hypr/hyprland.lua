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

-- «желе» и подсветка края: слои во весь экран меняются каждый кадр —
-- с размытием под ними перетаскивание заметно подтормаживает
hl.layer_rule({
    name  = "delta-drag-layers",
    match = { namespace = "^delta-(jelly|snap)$" },
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
-- через оболочку: на время разворачивания она убирает «желе» (window/Motion.qml)
hl.bind(mod .. " + F",       hl.dsp.global("delta:fullscreen"))
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
    name  = "delta-exe",
    match = { class = "^delta-exe$" },
    float = true,
    size  = "600 600",
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

-----------------------------------------
---- ПЕРЕТАСКИВАНИЕ: «желе» и края ----
-----------------------------------------

-- Hyprland не сообщает, когда окно начали и перестали тащить. Поэтому левая
-- кнопка мыши (бинды не забирают щелчок у программ) запускает таймер: он
-- смотрит, едет ли активное плавающее окно. Пока едет, состояние пишется в
-- $XDG_RUNTIME_DIR/hypr/<экземпляр>/delta-drag.json — его читает оболочка:
-- window/Jelly.qml рисует «желе» (низ окна отстаёт), window/Snap.qml —
-- подсветку края. Отпустили у края — окно занимает половину или четверть
-- экрана, у верхнего края — весь (как в GNOME). Потащили такое окно снова —
-- оно возвращает прежний размер. Настройки — из generated.lua:
--     delta_drag.snap = true; delta_drag.gaps = 14
delta_drag = delta_drag or {}
if delta_drag.snap == nil then delta_drag.snap = true end

local drag = { addr = nil, moving = false, zone = "", seq = 0, snapped = {} }
local dragfile = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr/"
    .. (os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "") .. "/delta-drag.json"

local function drag_write(state, w, zone, z)
    drag.seq = drag.seq + 1
    local f = io.open(dragfile, "w")
    if not f then return end
    z = z or { x = 0, y = 0, w = 0, h = 0 }
    f:write(string.format(
        '{"seq":%d,"state":"%s","address":"%s","monitor":"%s","x":%d,"y":%d,"w":%d,"h":%d,"gx":%d,"gy":%d,"zone":"%s","zx":%d,"zy":%d,"zw":%d,"zh":%d}\n',
        drag.seq, state, w and w.address or "", w and w.monitor and w.monitor.name or "",
        w and w.at.x or 0, w and w.at.y or 0, w and w.size.x or 0, w and w.size.y or 0,
        drag.gx or 0, drag.gy or 0, zone or "", z.x, z.y, z.w, z.h))
    f:close()
end

-- ~/.local/state/delta/drag.log: замеченные перетаскивания и пропущенные
-- (окно уехало, а «begin» не было) — с причиной. Журнал оболочки живёт до
-- перезагрузки, этот остаётся: по нему и jelly.log видно, где теряется «желе»
local draglog = (os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")) .. "/delta/drag.log"
local function drag_note(text)
    local f = io.open(draglog, "a")
    if not f then return end
    if f:seek("end") > 65536 then
        f:close()
        f = io.open(draglog, "w")
        if not f then return end
    end
    f:write(os.date("%Y-%m-%d %H:%M:%S "), text, "\n")
    f:close()
end

-- зона у края под курсором: left/right — половины, tl/tr/bl/br — четверти,
-- max — весь экран; прямоугольник — с отступами, без мест доков
local function drag_zone(m, p)
    if not m or delta_drag.snap == false then return "", nil end
    local s = (m.scale and m.scale > 0) and m.scale or 1
    local mx, my, mw, mh = m.x, m.y, m.width / s, m.height / s
    local r = type(m.reserved) == "table" and m.reserved or {}
    local ax, ay = mx + (r.left or 0), my + (r.top or 0)
    local aw, ah = mw - (r.left or 0) - (r.right or 0), mh - (r.top or 0) - (r.bottom or 0)
    local edge, corner = 14, math.max(100, mh * 0.18)
    local left, right = p.x - mx <= edge, mx + mw - p.x <= edge
    local top, bottom = p.y - my <= edge, my + mh - p.y <= edge
    local g = delta_drag.gaps or 14
    local hw, hh = (aw - 3 * g) / 2, (ah - 3 * g) / 2
    local lx, rx = ax + g, ax + 2 * g + hw
    local ty, by = ay + g, ay + 2 * g + hh
    local zone
    if left or right then
        if p.y - my < corner then zone = left and "tl" or "tr"
        elseif my + mh - p.y < corner then zone = left and "bl" or "br"
        else zone = left and "left" or "right" end
    elseif top then zone = "max"
    elseif bottom then return "", nil
    else return "", nil end
    local rects = {
        left = { x = lx, y = ty, w = hw, h = ah - 2 * g }, right = { x = rx, y = ty, w = hw, h = ah - 2 * g },
        tl = { x = lx, y = ty, w = hw, h = hh }, tr = { x = rx, y = ty, w = hw, h = hh },
        bl = { x = lx, y = by, w = hw, h = hh }, br = { x = rx, y = by, w = hw, h = hh },
        max = { x = ax + g, y = ay + g, w = aw - 2 * g, h = ah - 2 * g },
    }
    local z = rects[zone]
    return zone, { x = math.floor(z.x), y = math.floor(z.y), w = math.floor(z.w), h = math.floor(z.h) }
end

local function drag_tick()
    local w, p = hl.get_active_window(), hl.get_cursor_pos()
    if not w or not p then return end
    if not drag.moving then
        -- первое касание этого окна: запоминаем, откуда оно поедет
        if drag.addr ~= w.address then
            drag.addr = w.address
            drag.x0, drag.y0, drag.w0, drag.h0 = w.at.x, w.at.y, w.size.x, w.size.y
            drag.cx0, drag.cy0 = p.x, p.y
            return
        end
        if not w.floating or w.fullscreen ~= 0 then return end
        local moved = math.abs(w.at.x - drag.x0) + math.abs(w.at.y - drag.y0)
        -- размер тот же — значит тащат, а не растягивают
        if moved < 3 or w.size.x ~= drag.w0 or w.size.y ~= drag.h0 then return end
        drag.moving = true
        drag.gx, drag.gy = drag.cx0 - drag.x0, drag.cy0 - drag.y0
        drag.zone = ""
        -- окно было прижато к краю — возвращаем ему прежний размер под курсором
        local old = drag.snapped[w.address]
        if old then
            drag.snapped[w.address] = nil
            local fx, fy = drag.gx / math.max(1, w.size.x), drag.gy / math.max(1, w.size.y)
            drag.gx, drag.gy = math.floor(old.w * fx), math.floor(old.h * fy)
            local sel = "address:" .. w.address
            hl.dispatch(hl.dsp.window.resize({ x = old.w, y = old.h, window = sel }))
            hl.dispatch(hl.dsp.window.move({ x = math.floor(p.x - drag.gx), y = math.floor(p.y - drag.gy), window = sel }))
        end
        drag_write("begin", w, "", nil)
        drag_note("начато " .. w.address .. " " .. (w.class or "?") .. (w.xwayland and " (XWayland)" or ""))
        return
    end
    local zone, z = drag_zone(w.monitor, p)
    -- окно стоит на месте — файл не трогаем, оболочке нечего пересчитывать
    if w.at.x == drag.lx and w.at.y == drag.ly and zone == drag.zone then return end
    drag.lx, drag.ly = w.at.x, w.at.y
    drag.zone, drag.rect = zone, z
    drag_write("move", w, zone, z)
end

-- таймер — раз в 4 мс (250 Гц): желе успевает за курсором и на 240 Гц.
-- Создаётся при первом щелчке: `Hyprland --verify-config` (delta-apply,
-- delta-dev check) падает, если создать его во время разбора конфига
local drag_timer = nil

-- delta_drag.press()/release() можно звать и через `hyprctl eval` —
-- так перетаскивание проверяют без мыши (tools/delta-dev.sh)
function delta_drag.press()
    drag.addr, drag.moving, drag.zone, drag.lx, drag.ly = nil, false, "", nil, nil
    if not drag_timer then drag_timer = hl.timer(drag_tick, { timeout = 4, type = "repeat" }) end
    drag_timer:set_enabled(true)
end

function delta_drag.release()
    if drag_timer then drag_timer:set_enabled(false) end
    if not drag.moving then
        local w = hl.get_active_window()
        if w and drag.x0 and w.address == drag.addr and math.abs(w.at.x - drag.x0) + math.abs(w.at.y - drag.y0) >= 3 then
            drag_note(string.format("пропущено %s %s: floating=%s fullscreen=%s размер %dx%d → %dx%d",
                w.address, w.class or "?", tostring(w.floating), tostring(w.fullscreen),
                drag.w0, drag.h0, w.size.x, w.size.y))
        end
        return
    end
    drag.moving = false
    local w = hl.get_active_window()
    local zone, z = drag.zone, drag.rect
    if w and zone ~= "" and z then
        local sel = "address:" .. w.address
        drag.snapped[w.address] = { w = w.size.x, h = w.size.y }
        if zone == "max" then
            hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", window = sel }))
        else
            -- resize держит центр окна, поэтому сначала размер, потом место
            hl.dispatch(hl.dsp.window.resize({ x = z.w, y = z.h, window = sel }))
            hl.dispatch(hl.dsp.window.move({ x = z.x, y = z.y, window = sel }))
        end
    end
    drag_write("end", w, zone, z)
end

hl.bind("mouse:272", function() delta_drag.press() end, { non_consuming = true, transparent = true, ignore_mods = true })
hl.bind("mouse:272", function() delta_drag.release() end, { release = true, non_consuming = true, transparent = true, ignore_mods = true })

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
