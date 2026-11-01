use std::cell::Cell;

use smithay::{
    delegate_xdg_shell,
    desktop::{find_popup_root_surface, get_popup_toplevel_coords, PopupKind, Window},
    input::{
        pointer::{Focus, GrabStartData as PointerGrabStartData},
        Seat,
    },
    reexports::{
        wayland_protocols::xdg::shell::server::xdg_toplevel,
        wayland_server::{
            protocol::{wl_seat, wl_surface::WlSurface},
            Resource,
        },
    },
    utils::{Rectangle, Serial, SERIAL_COUNTER},
    wayland::{
        compositor::with_states,
        shell::xdg::{PopupSurface, PositionerState, ToplevelSurface, XdgShellHandler, XdgShellState, XdgToplevelSurfaceData},
    },
};

use crate::{
    grabs::{MoveSurfaceGrab, ResizeSurfaceGrab},
    Shell,
};

/// Окно уже поставлено на место (по центру, каскадом). Пока программа не
/// прислала первый кадр, его размер неизвестен — ставим при первом кадре.
#[derive(Default)]
struct Placed(Cell<bool>);

impl XdgShellHandler for Shell {
    fn xdg_shell_state(&mut self) -> &mut XdgShellState {
        &mut self.xdg_shell_state
    }

    /// Новое окно: сразу впереди и с фокусом, как в Windows и GNOME.
    fn new_toplevel(&mut self, surface: ToplevelSurface) {
        let window = Window::new_wayland_window(surface);
        self.space.map_element(window.clone(), (0, 0), true);
        self.focus_window(&window, SERIAL_COUNTER.next_serial());
    }

    /// Закрылось окно: фокус — тому, что под ним.
    fn toplevel_destroyed(&mut self, _surface: ToplevelSurface) {
        self.focus_top();
    }

    fn new_popup(&mut self, surface: PopupSurface, _positioner: PositionerState) {
        self.unconstrain_popup(&surface);
        let _ = self.popups.track_popup(PopupKind::Xdg(surface));
    }

    fn reposition_request(&mut self, surface: PopupSurface, positioner: PositionerState, token: u32) {
        surface.with_pending_state(|state| {
            state.geometry = positioner.get_geometry();
            state.positioner = positioner;
        });
        self.unconstrain_popup(&surface);
        surface.send_repositioned(token);
    }

    /// Программа просит тащить окно (за свой заголовок).
    fn move_request(&mut self, surface: ToplevelSurface, seat: wl_seat::WlSeat, serial: Serial) {
        let seat = Seat::from_resource(&seat).unwrap();
        let wl_surface = surface.wl_surface();
        let Some(start_data) = check_grab(&seat, wl_surface, serial) else { return };
        let Some(window) = self.window_for_surface(wl_surface) else { return };
        let initial_window_location = self.space.element_location(&window).unwrap();
        let pointer = seat.get_pointer().unwrap();
        pointer.set_grab(self, MoveSurfaceGrab { start_data, window, initial_window_location }, serial, Focus::Clear);
    }

    /// Программа просит менять размер (за свой край).
    fn resize_request(&mut self, surface: ToplevelSurface, seat: wl_seat::WlSeat, serial: Serial, edges: xdg_toplevel::ResizeEdge) {
        let seat = Seat::from_resource(&seat).unwrap();
        let wl_surface = surface.wl_surface();
        let Some(start_data) = check_grab(&seat, wl_surface, serial) else { return };
        let Some(window) = self.window_for_surface(wl_surface) else { return };
        let initial_window_location = self.space.element_location(&window).unwrap();
        let initial_window_size = window.geometry().size;

        surface.with_pending_state(|state| {
            state.states.set(xdg_toplevel::State::Resizing);
        });
        surface.send_pending_configure();

        let grab = ResizeSurfaceGrab::start(
            start_data,
            window,
            edges.into(),
            Rectangle::new(initial_window_location, initial_window_size),
        );
        seat.get_pointer().unwrap().set_grab(self, grab, serial, Focus::Clear);
    }

    fn grab(&mut self, _surface: PopupSurface, _seat: wl_seat::WlSeat, _serial: Serial) {
        // захват ввода всплывающими меню — в плане (PopupGrab)
    }
}
delegate_xdg_shell!(Shell);

/// Просьба тащить или менять размер честная: кнопка нажата именно над этой программой.
fn check_grab(seat: &Seat<Shell>, surface: &WlSurface, serial: Serial) -> Option<PointerGrabStartData<Shell>> {
    let pointer = seat.get_pointer()?;
    if !pointer.has_grab(serial) {
        return None;
    }
    let start_data = pointer.grab_start_data()?;
    let (focus, _) = start_data.focus.as_ref()?;
    if !focus.id().same_client_as(&surface.id()) {
        return None;
    }
    Some(start_data)
}

/// При каждом кадре: первая настройка окна, место для нового окна, всплывающие меню.
pub fn handle_commit(shell: &mut Shell, surface: &WlSurface) {
    if let Some(window) = shell.window_for_surface(surface) {
        let initial_configure_sent = with_states(surface, |states| {
            states.data_map.get::<XdgToplevelSurfaceData>().unwrap().lock().unwrap().initial_configure_sent
        });
        if !initial_configure_sent {
            window.toplevel().unwrap().send_configure();
        }

        let size = window.geometry().size;
        let placed = window.user_data().get_or_insert(Placed::default);
        if !placed.0.get() && size.w > 0 && size.h > 0 {
            placed.0.set(true);
            let loc = shell.initial_position((size.w, size.h));
            shell.space.map_element(window.clone(), loc, false);
        }
    }

    shell.popups.commit(surface);
    if let Some(PopupKind::Xdg(ref xdg)) = shell.popups.find_popup(surface) {
        if !xdg.is_initial_configure_sent() {
            // первая настройка разрешена всегда
            xdg.send_configure().expect("первая настройка меню");
        }
    }
}

impl Shell {
    /// Всплывающее меню не вылезает за экран.
    fn unconstrain_popup(&self, popup: &PopupSurface) {
        let Ok(root) = find_popup_root_surface(&PopupKind::Xdg(popup.clone())) else { return };
        let Some(window) = self.window_for_surface(&root) else { return };
        let Some(output) = self.space.outputs().next() else { return };
        let output_geo = self.space.output_geometry(output).unwrap();
        let window_geo = self.space.element_geometry(&window).unwrap();

        // цель — относительно родителя меню
        let mut target = output_geo;
        target.loc -= get_popup_toplevel_coords(&PopupKind::Xdg(popup.clone()));
        target.loc -= window_geo.loc;
        popup.with_pending_state(|state| {
            state.geometry = state.positioner.get_unconstrained_geometry(target);
        });
    }
}
