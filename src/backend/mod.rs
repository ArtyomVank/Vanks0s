//! Откуда берутся экран и ввод.
//!
//! - winit — окно внутри текущей сессии (Hyprland, GNOME): для разработки.
//! - udev — настоящая сессия: DRM/KMS, libinput, libseat.

pub mod udev;
pub mod winit;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Winit,
    Udev,
}

impl Kind {
    /// Внутри графической сессии — окно отладки, с консоли — настоящая сессия.
    pub fn detect() -> Self {
        if inside_session() { Kind::Winit } else { Kind::Udev }
    }

    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "winit" | "window" => Some(Kind::Winit),
            "udev" | "tty" | "drm" => Some(Kind::Udev),
            _ => None,
        }
    }
}

/// Уже идёт графическая сессия (Hyprland, Delta): видеокарту и ввод ведёт она.
pub fn inside_session() -> bool {
    std::env::var_os("WAYLAND_DISPLAY").is_some() || std::env::var_os("DISPLAY").is_some()
}
