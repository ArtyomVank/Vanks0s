//! Протоколы Hyprland (hyprland-protocols, BSD-3 — protocols/LICENSE.hyprland-protocols),
//! которыми пользуется Quickshell и Delta. Код протокола генерирует
//! wayland-scanner из XML; поведение — в соседних модулях.

pub mod focus_grab;
pub mod foreign_toplevel;
pub mod global_shortcuts;
pub mod idle_notify;

pub mod generated {
    pub mod global_shortcuts {
        use wayland_server;

        pub mod __interfaces {
            wayland_scanner::generate_interfaces!("protocols/hyprland-global-shortcuts-v1.xml");
        }
        use self::__interfaces::*;

        wayland_scanner::generate_server_code!("protocols/hyprland-global-shortcuts-v1.xml");
    }

    pub mod focus_grab {
        use wayland_server;
        use wayland_server::protocol::*;

        pub mod __interfaces {
            use wayland_server::protocol::__interfaces::*;
            wayland_scanner::generate_interfaces!("protocols/hyprland-focus-grab-v1.xml");
        }
        use self::__interfaces::*;

        wayland_scanner::generate_server_code!("protocols/hyprland-focus-grab-v1.xml");
    }

    pub mod toplevel_mapping {
        use smithay::reexports::wayland_protocols::ext::foreign_toplevel_list::v1::server::*;
        use smithay::reexports::wayland_protocols_wlr::foreign_toplevel::v1::server::*;
        use wayland_server;

        pub mod __interfaces {
            use smithay::reexports::wayland_protocols::ext::foreign_toplevel_list::v1::server::__interfaces::*;
            use smithay::reexports::wayland_protocols_wlr::foreign_toplevel::v1::server::__interfaces::*;
            wayland_scanner::generate_interfaces!("protocols/hyprland-toplevel-mapping-v1.xml");
        }
        use self::__interfaces::*;

        wayland_scanner::generate_server_code!("protocols/hyprland-toplevel-mapping-v1.xml");
    }
}
