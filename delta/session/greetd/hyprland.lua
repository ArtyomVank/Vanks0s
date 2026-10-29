-- Delta — Hyprland только для экрана входа (greetd → этот конфиг → greeter.qml).
--
-- Ставится в /usr/share/delta/session/greetd/hyprland.lua. Работает от пользователя
-- greeter: никаких привязок, кроме самых нужных, никаких приложений, кроме greeter'а.
-- Когда greeter запускает сессию и выходит, выходит и этот Hyprland —
-- только тогда greetd стартует выбранную сессию.

local data = os.getenv("DELTA_DATA") or "/usr/share/delta"

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("DELTA_DATA", data)
-- сюда greeter кладёт settings.json выбранного пользователя (тема, акцент, обои, часы);
-- каталог создаёт tmpfiles (session/greetd/tmpfiles.conf), владелец — greeter
hl.env("XDG_CONFIG_HOME", "/var/cache/delta-greeter/config")

hl.config({
    general = { gaps_in = 0, gaps_out = 0, border_size = 0 },
    decoration = {
        rounding = 0,
        shadow = { enabled = false },
        blur = { enabled = true, size = 6, passes = 3 },
    },
    animations = { enabled = false },
    misc = {
        force_default_wallpaper  = 0,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        disable_watchdog_warning = true,
        background_color         = 0x000000,
        -- курсор и клавиатура будят экран входа, если он погас
        mouse_move_enables_dpms  = true,
        key_press_enables_dpms   = true,
    },
    ecosystem = {
        no_update_news  = true,
        no_donation_nag = true,
    },
    input = {
        kb_layout    = "us,ru",
        kb_options   = "grp:alt_shift_toggle",
        numlock_by_default = true,
        follow_mouse = 1,
        touchpad = { tap_to_click = true, natural_scroll = true },
    },
})

-- стекло greeter'а размывается, как в оболочке
hl.layer_rule({
    name  = "delta-greeter",
    match = { namespace = "^delta-" },
    blur  = true,
    ignore_alpha = 0.35,
    no_anim = true,
})

-- Единственные привязки: громкость и яркость (на ноутбуке без них неудобно).
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })

hl.on("hyprland.start", function()
    -- greeter завершился (сессия запущена или он упал) — завершаем и композитор,
    -- иначе greetd будет ждать вечно; при падении greetd просто покажет экран входа снова
    hl.exec_cmd("sh -c 'qs -p " .. data .. "/shell/greeter.qml; hyprctl dispatch \"hl.dsp.exit()\"'")
end)
