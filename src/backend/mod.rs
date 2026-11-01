//! Откуда берутся экран и ввод.
//!
//! - winit — окно внутри текущей сессии (Hyprland, GNOME): для разработки.
//! - udev — настоящая сессия: DRM/KMS, libinput, libseat (следующий шаг).

pub mod winit;
