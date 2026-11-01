//! hyprland_global_shortcuts_v1 — глобальные сочетания: программа заводит
//! сочетание по имени («delta» + «launcher-key»), оболочка сообщает, когда
//! его нажали. Так Delta получает Super, Super+S, Super+L, клавиши громкости…
//! (Quickshell GlobalShortcut). Какие клавиши — решает оболочка (input.rs).

use smithay::reexports::wayland_server::{
    backend::ClientId, Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};

use super::generated::global_shortcuts::{
    hyprland_global_shortcut_v1::{self, HyprlandGlobalShortcutV1},
    hyprland_global_shortcuts_manager_v1::{self, HyprlandGlobalShortcutsManagerV1},
};
use crate::Shell;

/// Заведённое сочетание.
pub struct Shortcut {
    /// «delta:launcher-key» — как пишут в hl.dsp.global
    pub name: String,
    pub resource: HyprlandGlobalShortcutV1,
}

#[derive(Default)]
pub struct GlobalShortcutsState {
    pub shortcuts: Vec<Shortcut>,
}

impl GlobalShortcutsState {
    pub fn new(dh: &DisplayHandle) -> Self {
        dh.create_global::<Shell, HyprlandGlobalShortcutsManagerV1, _>(1, ());
        Self::default()
    }
}

impl GlobalDispatch<HyprlandGlobalShortcutsManagerV1, ()> for Shell {
    fn bind(
        _state: &mut Self,
        _dh: &DisplayHandle,
        _client: &Client,
        resource: New<HyprlandGlobalShortcutsManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<HyprlandGlobalShortcutsManagerV1, ()> for Shell {
    fn request(
        state: &mut Self,
        _client: &Client,
        manager: &HyprlandGlobalShortcutsManagerV1,
        request: hyprland_global_shortcuts_manager_v1::Request,
        _data: &(),
        _dh: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            hyprland_global_shortcuts_manager_v1::Request::RegisterShortcut { shortcut, id, app_id, .. } => {
                let name = format!("{app_id}:{id}");
                let resource = data_init.init(shortcut, ());
                if state.global_shortcuts.shortcuts.iter().any(|s| s.name == name && s.resource.is_alive()) {
                    manager.post_error(
                        hyprland_global_shortcuts_manager_v1::Error::AlreadyTaken,
                        format!("сочетание {name} уже занято"),
                    );
                    return;
                }
                tracing::debug!(name, "глобальное сочетание");
                state.global_shortcuts.shortcuts.push(Shortcut { name, resource });
            }
            hyprland_global_shortcuts_manager_v1::Request::Destroy => {}
        }
    }
}

impl Dispatch<HyprlandGlobalShortcutV1, ()> for Shell {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &HyprlandGlobalShortcutV1,
        request: hyprland_global_shortcut_v1::Request,
        _data: &(),
        _dh: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        if let hyprland_global_shortcut_v1::Request::Destroy = request {
            state.global_shortcuts.shortcuts.retain(|s| &s.resource != resource);
        }
    }

    fn destroyed(state: &mut Self, _client: ClientId, resource: &HyprlandGlobalShortcutV1, _data: &()) {
        state.global_shortcuts.shortcuts.retain(|s| &s.resource != resource);
    }
}

impl Shell {
    /// Сочетание «app:id» нажато (pressed) или отпущено. Нет такого — false.
    pub fn trigger_global(&mut self, name: &str, pressed: bool) -> bool {
        let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default();
        let (hi, lo, ns) = ((now.as_secs() >> 32) as u32, now.as_secs() as u32, now.subsec_nanos());
        let mut found = false;
        for s in self.global_shortcuts.shortcuts.iter().filter(|s| s.name == name && s.resource.is_alive()) {
            found = true;
            if pressed {
                s.resource.pressed(hi, lo, ns);
            } else {
                s.resource.released(hi, lo, ns);
            }
        }
        if !found && pressed {
            tracing::debug!(name, "сочетание никем не заведено");
        }
        found
    }
}
