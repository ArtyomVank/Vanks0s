//! hyprland_focus_grab_v1 — «нажатие мимо закрывает». Delta (Quickshell
//! HyprlandFocusGrab) открывает меню и называет его поверхности; пока захват
//! активен, клавиатура у них, а щелчок мимо снимает захват — меню закрывается.
//! Сам щелчок идёт дальше как обычно: окно под ним тоже его получит.

use smithay::{
    reexports::wayland_server::{
        backend::ClientId, protocol::wl_surface::WlSurface, Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch,
        New, Resource,
    },
    utils::SERIAL_COUNTER,
    wayland::compositor::get_parent,
    desktop::{find_popup_root_surface, PopupKind},
};

use super::generated::focus_grab::{
    hyprland_focus_grab_manager_v1::{self, HyprlandFocusGrabManagerV1},
    hyprland_focus_grab_v1::{self, HyprlandFocusGrabV1},
};
use crate::Shell;

struct Grab {
    resource: HyprlandFocusGrabV1,
    pending: Vec<WlSurface>,
    active: Vec<WlSurface>,
}

#[derive(Default)]
pub struct FocusGrabState {
    grabs: Vec<Grab>,
}

impl FocusGrabState {
    pub fn new(dh: &DisplayHandle) -> Self {
        dh.create_global::<Shell, HyprlandFocusGrabManagerV1, _>(1, ());
        Self::default()
    }
}

impl Shell {
    /// Главная поверхность: у подповерхности — её родитель, у меню — окно или слой.
    fn grab_root(&self, surface: &WlSurface) -> WlSurface {
        let mut root = surface.clone();
        while let Some(parent) = get_parent(&root) {
            root = parent;
        }
        if let Some(popup) = self.popups.find_popup(&root) {
            if let Ok(owner) = find_popup_root_surface(&PopupKind::from(popup)) {
                return owner;
            }
        }
        root
    }

    fn grab_contains(&self, surface: &WlSurface) -> bool {
        let root = self.grab_root(surface);
        self.focus_grabs.grabs.iter().any(|g| g.active.iter().any(|s| *s == root || s == surface))
    }

    fn grab_active(&self) -> bool {
        self.focus_grabs.grabs.iter().any(|g| g.active.iter().any(Resource::is_alive))
    }

    /// Снять все захваты (меню закроются). Клавиатура была у них — верхнему окну.
    pub fn clear_focus_grabs(&mut self) {
        let focus = self.seat.get_keyboard().and_then(|k| k.current_focus());
        let had_focus = focus.and_then(|f| f.surface()).is_some_and(|f| self.grab_contains(&f));
        for grab in &mut self.focus_grabs.grabs {
            if !grab.active.is_empty() {
                grab.active.clear();
                grab.pending.clear();
                grab.resource.cleared();
            }
        }
        if had_focus {
            self.focus_top();
        }
    }

    /// Щелчок: мимо разрешённых поверхностей — захвата больше нет.
    pub fn focus_grab_click(&mut self, surface: Option<&WlSurface>) {
        if self.grab_active() && !surface.is_some_and(|s| self.grab_contains(s)) {
            self.clear_focus_grabs();
        }
    }

    /// Клавиатура уходит окну (открылось, выбрали в доке): если не из захвата, захват снимается.
    pub fn focus_grab_window(&mut self, surface: &WlSurface) {
        if self.grab_active() && !self.grab_contains(surface) {
            self.clear_focus_grabs();
        }
    }

    fn commit_grab(&mut self, resource: &HyprlandFocusGrabV1) {
        let Some(i) = self.focus_grabs.grabs.iter().position(|g| &g.resource == resource) else { return };
        let focus = self.seat.get_keyboard().and_then(|k| k.current_focus());
        let focus = focus.and_then(|f| f.surface());
        let had_focus = focus.as_ref().is_some_and(|f| self.grab_contains(f));
        let grab = &mut self.focus_grabs.grabs[i];
        grab.pending.retain(Resource::is_alive);
        let started = grab.active.is_empty() && !grab.pending.is_empty();
        grab.active = grab.pending.clone();
        let first = grab.active.first().cloned();

        // одновременно действует один захват
        if started {
            for (n, other) in self.focus_grabs.grabs.iter_mut().enumerate() {
                if n != i && !other.active.is_empty() {
                    other.active.clear();
                    other.pending.clear();
                    other.resource.cleared();
                }
            }
        }
        if self.is_locked() {
            return;
        }
        match first {
            // клавиатура — разрешённой поверхности, если она ещё не там
            Some(first) => {
                if !focus.is_some_and(|f| self.grab_contains(&f)) {
                    if let Some(kb) = self.seat.get_keyboard() {
                        kb.set_focus(self, Some(first.into()), SERIAL_COUNTER.next_serial());
                    }
                }
            }
            None if had_focus => self.focus_top(),
            None => {}
        }
    }
}

impl GlobalDispatch<HyprlandFocusGrabManagerV1, ()> for Shell {
    fn bind(
        _state: &mut Self,
        _dh: &DisplayHandle,
        _client: &Client,
        resource: New<HyprlandFocusGrabManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<HyprlandFocusGrabManagerV1, ()> for Shell {
    fn request(
        state: &mut Self,
        _client: &Client,
        _manager: &HyprlandFocusGrabManagerV1,
        request: hyprland_focus_grab_manager_v1::Request,
        _data: &(),
        _dh: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            hyprland_focus_grab_manager_v1::Request::CreateGrab { grab } => {
                let resource = data_init.init(grab, ());
                state.focus_grabs.grabs.push(Grab { resource, pending: Vec::new(), active: Vec::new() });
            }
            hyprland_focus_grab_manager_v1::Request::Destroy => {}
        }
    }
}

impl Dispatch<HyprlandFocusGrabV1, ()> for Shell {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &HyprlandFocusGrabV1,
        request: hyprland_focus_grab_v1::Request,
        _data: &(),
        _dh: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            hyprland_focus_grab_v1::Request::AddSurface { surface } => {
                if let Some(grab) = state.focus_grabs.grabs.iter_mut().find(|g| &g.resource == resource) {
                    if !grab.pending.contains(&surface) {
                        grab.pending.push(surface);
                    }
                }
            }
            hyprland_focus_grab_v1::Request::RemoveSurface { surface } => {
                if let Some(grab) = state.focus_grabs.grabs.iter_mut().find(|g| &g.resource == resource) {
                    grab.pending.retain(|s| *s != surface);
                }
            }
            hyprland_focus_grab_v1::Request::Commit => state.commit_grab(resource),
            hyprland_focus_grab_v1::Request::Destroy => end_grab(state, resource),
        }
    }

    fn destroyed(state: &mut Self, _client: ClientId, resource: &HyprlandFocusGrabV1, _data: &()) {
        end_grab(state, resource);
    }
}

/// Захват уничтожен программой: убрать его, клавиатура — верхнему окну.
fn end_grab(state: &mut Shell, resource: &HyprlandFocusGrabV1) {
    let Some(i) = state.focus_grabs.grabs.iter().position(|g| &g.resource == resource) else { return };
    let focus = state.seat.get_keyboard().and_then(|k| k.current_focus());
    let had_focus = !state.focus_grabs.grabs[i].active.is_empty() && focus.and_then(|f| f.surface()).is_some_and(|f| state.grab_contains(&f));
    state.focus_grabs.grabs.remove(i);
    if had_focus {
        state.focus_top();
    }
}
