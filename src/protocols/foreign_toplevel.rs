//! wlr-foreign-toplevel-management — список окон для дока Delta (Quickshell
//! ToplevelManager): название, состояние, «поднять», «закрыть». И
//! hyprland_toplevel_mapping_v1 — какое окно Hyprland IPC стоит за записью списка.
//!
//! Список сверяется с окнами после каждого прохода цикла и рассылает только
//! изменения.

use smithay::{
    desktop::Window,
    output::Output,
    reexports::{
        wayland_protocols_wlr::foreign_toplevel::v1::server::{
            zwlr_foreign_toplevel_handle_v1::{self, ZwlrForeignToplevelHandleV1},
            zwlr_foreign_toplevel_manager_v1::{self, ZwlrForeignToplevelManagerV1},
        },
        wayland_server::{backend::ClientId, Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource},
    },
    utils::SERIAL_COUNTER,
};

use super::generated::toplevel_mapping::{
    hyprland_toplevel_mapping_manager_v1::{self, HyprlandToplevelMappingManagerV1},
    hyprland_toplevel_window_mapping_handle_v1::{self, HyprlandToplevelWindowMappingHandleV1},
};
use crate::{
    workspaces::{class_title, data, Mode, SPECIAL},
    Shell,
};

#[derive(Clone, Default, PartialEq)]
struct Info {
    title: String,
    app_id: String,
    /// массив u32 состояний — как его ждёт протокол
    states: Vec<u8>,
    output: Option<String>,
}

struct Entry {
    window: Window,
    info: Info,
    handles: Vec<ZwlrForeignToplevelHandleV1>,
}

#[derive(Default)]
pub struct ForeignToplevelState {
    managers: Vec<ZwlrForeignToplevelManagerV1>,
    entries: Vec<Entry>,
}

impl ForeignToplevelState {
    pub fn new(dh: &DisplayHandle) -> Self {
        dh.create_global::<Shell, ZwlrForeignToplevelManagerV1, _>(3, ());
        dh.create_global::<Shell, HyprlandToplevelMappingManagerV1, _>(1, ());
        Self::default()
    }
}

impl Shell {
    fn toplevel_info(&self, window: &Window) -> Info {
        let (app_id, title) = class_title(window);
        let (mode, workspace) = {
            let d = data(window);
            (d.mode, d.workspace)
        };
        let mut states = Vec::new();
        let mut push = |s: zwlr_foreign_toplevel_handle_v1::State| states.extend_from_slice(&(s as u32).to_ne_bytes());
        match mode {
            Mode::Maximized => push(zwlr_foreign_toplevel_handle_v1::State::Maximized),
            Mode::Fullscreen => push(zwlr_foreign_toplevel_handle_v1::State::Fullscreen),
            Mode::Normal => {}
        }
        if self.focused_window().as_ref() == Some(window) {
            push(zwlr_foreign_toplevel_handle_v1::State::Activated);
        }
        if workspace == SPECIAL {
            push(zwlr_foreign_toplevel_handle_v1::State::Minimized);
        }
        Info { title, app_id, states, output: self.workspaces.monitor_of.get(&workspace).cloned() }
    }

    /// Сверить список с окнами: новые, закрытые и изменившиеся.
    pub fn foreign_toplevel_refresh(&mut self) {
        let mut state = std::mem::take(&mut self.foreign_toplevels);
        state.entries.retain(|e| {
            let open = self.windows.contains(&e.window);
            if !open {
                e.handles.iter().for_each(|h| h.closed());
            }
            open
        });
        for window in &self.windows {
            let info = self.toplevel_info(window);
            if let Some(entry) = state.entries.iter_mut().find(|e| &e.window == window) {
                if entry.info != info {
                    for handle in &entry.handles {
                        self.send_toplevel(handle, Some(&entry.info), &info);
                    }
                    entry.info = info;
                }
            } else {
                let mut entry = Entry { window: window.clone(), info, handles: Vec::new() };
                for manager in &state.managers {
                    self.new_toplevel_handle(manager, &mut entry);
                }
                state.entries.push(entry);
            }
        }
        self.foreign_toplevels = state;
    }

    fn new_toplevel_handle(&self, manager: &ZwlrForeignToplevelManagerV1, entry: &mut Entry) {
        let Some(client) = manager.client() else { return };
        let Ok(handle) =
            client.create_resource::<ZwlrForeignToplevelHandleV1, _, Shell>(&self.display_handle, manager.version(), ())
        else {
            return;
        };
        manager.toplevel(&handle);
        self.send_toplevel(&handle, None, &entry.info);
        entry.handles.push(handle);
    }

    /// Изменившееся (old = None — всё) и done.
    fn send_toplevel(&self, handle: &ZwlrForeignToplevelHandleV1, old: Option<&Info>, new: &Info) {
        if old.map(|o| &o.title) != Some(&new.title) {
            handle.title(new.title.clone());
        }
        if old.map(|o| &o.app_id) != Some(&new.app_id) {
            handle.app_id(new.app_id.clone());
        }
        if old.map(|o| &o.states) != Some(&new.states) {
            handle.state(new.states.clone());
        }
        if old.map(|o| &o.output) != Some(&new.output) {
            if let Some(client) = handle.client() {
                if let Some(output) = old.and_then(|o| self.output_named(o.output.as_deref())) {
                    output.client_outputs(&client).for_each(|o| handle.output_leave(&o));
                }
                if let Some(output) = self.output_named(new.output.as_deref()) {
                    output.client_outputs(&client).for_each(|o| handle.output_enter(&o));
                }
            }
        }
        handle.done();
    }

    fn output_named(&self, name: Option<&str>) -> Option<Output> {
        let name = name?;
        self.space.outputs().find(|o| o.name() == name).cloned()
    }

    pub fn window_of_handle(&self, handle: &ZwlrForeignToplevelHandleV1) -> Option<Window> {
        self.foreign_toplevels.entries.iter().find(|e| e.handles.contains(handle)).map(|e| e.window.clone())
    }
}

impl GlobalDispatch<ZwlrForeignToplevelManagerV1, ()> for Shell {
    fn bind(
        state: &mut Self,
        _dh: &DisplayHandle,
        _client: &Client,
        resource: New<ZwlrForeignToplevelManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        let manager = data_init.init(resource, ());
        let mut toplevels = std::mem::take(&mut state.foreign_toplevels);
        for entry in &mut toplevels.entries {
            state.new_toplevel_handle(&manager, entry);
        }
        toplevels.managers.push(manager);
        state.foreign_toplevels = toplevels;
    }
}

impl Dispatch<ZwlrForeignToplevelManagerV1, ()> for Shell {
    fn request(
        state: &mut Self,
        _client: &Client,
        manager: &ZwlrForeignToplevelManagerV1,
        request: zwlr_foreign_toplevel_manager_v1::Request,
        _data: &(),
        _dh: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        if let zwlr_foreign_toplevel_manager_v1::Request::Stop = request {
            state.foreign_toplevels.managers.retain(|m| m != manager);
            manager.finished();
        }
    }

    fn destroyed(state: &mut Self, _client: ClientId, manager: &ZwlrForeignToplevelManagerV1, _data: &()) {
        state.foreign_toplevels.managers.retain(|m| m != manager);
    }
}

impl Dispatch<ZwlrForeignToplevelHandleV1, ()> for Shell {
    fn request(
        state: &mut Self,
        _client: &Client,
        handle: &ZwlrForeignToplevelHandleV1,
        request: zwlr_foreign_toplevel_handle_v1::Request,
        _data: &(),
        _dh: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        use zwlr_foreign_toplevel_handle_v1::Request;
        let Some(window) = state.window_of_handle(handle) else { return };
        match request {
            Request::SetMaximized => state.window_mode(&window, Mode::Maximized, true),
            Request::UnsetMaximized => state.window_mode(&window, Mode::Maximized, false),
            Request::SetFullscreen { .. } => state.window_mode(&window, Mode::Fullscreen, true),
            Request::UnsetFullscreen => state.window_mode(&window, Mode::Fullscreen, false),
            Request::SetMinimized => state.move_to_workspace(&window, SPECIAL, false),
            Request::UnsetMinimized | Request::Activate { .. } => state.activate_window(&window, SERIAL_COUNTER.next_serial()),
            Request::Close => crate::workspaces::close(&window),
            _ => {}
        }
    }

    fn destroyed(state: &mut Self, _client: ClientId, handle: &ZwlrForeignToplevelHandleV1, _data: &()) {
        for entry in &mut state.foreign_toplevels.entries {
            entry.handles.retain(|h| h != handle);
        }
    }
}

// --- адрес окна для записи списка ---
impl GlobalDispatch<HyprlandToplevelMappingManagerV1, ()> for Shell {
    fn bind(
        _state: &mut Self,
        _dh: &DisplayHandle,
        _client: &Client,
        resource: New<HyprlandToplevelMappingManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<HyprlandToplevelMappingManagerV1, ()> for Shell {
    fn request(
        state: &mut Self,
        _client: &Client,
        _manager: &HyprlandToplevelMappingManagerV1,
        request: hyprland_toplevel_mapping_manager_v1::Request,
        _data: &(),
        _dh: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        use hyprland_toplevel_mapping_manager_v1::Request;
        match request {
            Request::GetWindowForToplevelWlr { handle, toplevel } => {
                let mapping = data_init.init(handle, ());
                match state.window_of_handle(&toplevel) {
                    Some(window) => {
                        let address = data(&window).address;
                        mapping.window_address((address >> 32) as u32, address as u32);
                    }
                    None => mapping.failed(),
                }
            }
            // ext-foreign-toplevel-list мы не предлагаем
            Request::GetWindowForToplevel { handle, .. } => data_init.init(handle, ()).failed(),
            _ => {}
        }
    }
}

impl Dispatch<HyprlandToplevelWindowMappingHandleV1, ()> for Shell {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _mapping: &HyprlandToplevelWindowMappingHandleV1,
        _request: hyprland_toplevel_window_mapping_handle_v1::Request,
        _data: &(),
        _dh: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
    }
}
