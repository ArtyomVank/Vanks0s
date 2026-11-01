//! Настройки. Пока — постоянные значения и переменные окружения; файл
//! настроек (общий с «Настройками» Delta) — в плане, docs/ROADMAP.md.

/// Терминал для Super+Enter и запуска без -c: DELTA_TERMINAL, иначе как в
/// Delta — терминал по умолчанию (xdg-terminal-exec), а нет его — kitty.
pub fn terminal() -> String {
    std::env::var("DELTA_TERMINAL").unwrap_or_else(|_| "xdg-terminal-exec || kitty".into())
}

/// Цвет фона, пока нет обоев: тёмный фиолетовый, как акцент Delta по умолчанию.
pub const BACKGROUND: [f32; 4] = [0.07, 0.06, 0.11, 1.0];

/// Новые окна — каскадом от центра, со сдвигом на столько точек.
pub const CASCADE_STEP: i32 = 32;

/// Есть ли программа в PATH.
pub fn in_path(program: &str) -> bool {
    std::env::var_os("PATH")
        .map(|p| std::env::split_paths(&p).any(|d| d.join(program).is_file()))
        .unwrap_or(false)
}

/// Что запустить при старте, если не сказано -c: Delta, как её запускает
/// hyprland.lua (оболочка под присмотром delta-shell и помощник первого
/// запуска), а нет Delta — терминал.
pub fn autostart(nested: bool) -> Vec<String> {
    if !in_path("delta-shell") {
        return vec![terminal()];
    }
    let mut list = Vec::new();
    // порталы и службы systemd --user должны знать про эту сессию — но не из
    // вложенной сессии разработчика, иначе они переедут к ней
    if !nested {
        list.push(
            "dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP \
             XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE DELTA_DATA QT_QPA_PLATFORMTHEME"
                .into(),
        );
    }
    list.push("delta-shell".into());
    list.push("sleep 3; exec delta-welcome --first-run".into());
    list
}
