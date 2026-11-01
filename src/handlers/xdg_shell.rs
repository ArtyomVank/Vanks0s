use std::cell::Cell;

use smithay::{
    delegate_xdg_decoration, delegate_xdg_shell,
    desktop::{
        find_popup_root_surface, get_popup_toplevel_coords, layer_map_for_output, PopupKeyboardGrab, PopupKind, PopupPointerGrab,
        PopupUngrabStrategy, Window, WindowSurfaceType,
    },
    input::{
        pointer::{Focus, GrabStartData as PointerGrabStartData},
        Seat,
    },
    reexports::{
        wayland_protocols::xdg::{
            decoration::zv1::server::zxdg_toplevel_decoration_v1::Mode as DecorationMode, shell::server::xdg_toplevel,
        },
        wayland_server::{
            protocol::{wl_seat, wl_surface::WlSurface},
            Resource,
        },
    },
    utils::{Rectangle, Serial, SERIAL_COUNTER},
    wayland::{
        compositor::with_states,
        shell::xdg::{
            decoration::XdgDecorationHandler, PopupSurface, PositionerState, ToplevelSurface, XdgShellHandler, XdgShellState,
            XdgToplevelSurfaceData,
        },
    },
};

use crate::{
    focus::KeyFocus,
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
        self.track_window(&window);
        self.space.map_element(window.clone(), (0, 0), true);
        self.focus_window(&window, SERIAL_COUNTER.next_serial());
    }

    /// Закрылось окно: фокус — тому, что под ним.
    fn toplevel_destroyed(&mut self, surface: ToplevelSurface) {
        let window = self.windows.iter().find(|w| w.toplevel() == Some(&surface)).cloned();
        if let Some(window) = window {
            self.untrack_window(&window);
        }
        self.focus_top();
    }

    fn title_changed(&mut self, surface: ToplevelSurface) {
        if let Some(window) = self.windows.iter().find(|w| w.toplevel() == Some(&surface)).cloned() {
            self.window_title_changed(&window);
        }
    }

    // кнопки окна и F11 программы — те же «развернуть» и «во весь экран»
    fn maximize_request(&mut self, surface: ToplevelSurface) {
        self.toplevel_mode(&surface, crate::workspaces::Mode::Maximized, true);
    }
    fn unmaximize_request(&mut self, surface: ToplevelSurface) {
        self.toplevel_mode(&surface, crate::workspaces::Mode::Maximized, false);
    }
    fn fullscreen_request(&mut self, surface: ToplevelSurface, _output: Option<smithay::reexports::wayland_server::protocol::wl_output::WlOutput>) {
        self.toplevel_mode(&surface, crate::workspaces::Mode::Fullscreen, true);
    }
    fn unfullscreen_request(&mut self, surface: ToplevelSurface) {
        self.toplevel_mode(&surface, crate::workspaces::Mode::Fullscreen, false);
    }
    // «свернуть» — как в Delta: на стол свёрнутых
    fn minimize_request(&mut self, surface: ToplevelSurface) {
        if let Some(window) = self.windows.iter().find(|w| w.toplevel() == Some(&surface)).cloned() {
            self.move_to_workspace(&window, crate::workspaces::SPECIAL, false);
        }
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

    /// Меню программы забирает ввод: щелчок мимо его закрывает.
    fn grab(&mut self, surface: PopupSurface, seat: wl_seat::WlSeat, serial: Serial) {
        let seat = Seat::from_resource(&seat).unwrap();
        let kind = PopupKind::Xdg(surface);
        let Ok(root) = find_popup_root_surface(&kind) else { return };
        let Ok(mut grab) = self.popups.grab_popup(KeyFocus::Surface(root), kind, &seat, serial) else { return };
        if let Some(keyboard) = seat.get_keyboard() {
            if keyboard.is_grabbed() && !(keyboard.has_grab(serial) || keyboard.has_grab(grab.previous_serial().unwrap_or(serial))) {
                grab.ungrab(PopupUngrabStrategy::All);
                return;
            }
            keyboard.set_focus(self, grab.current_grab(), serial);
            keyboard.set_grab(self, PopupKeyboardGrab::new(&grab), serial);
        }
        if let Some(pointer) = seat.get_pointer() {
            if pointer.is_grabbed() && !(pointer.has_grab(serial) || pointer.has_grab(grab.previous_serial().unwrap_or_else(|| grab.serial()))) {
                grab.ungrab(PopupUngrabStrategy::All);
                return;
            }
            pointer.set_grab(self, PopupPointerGrab::new(&grab), serial, Focus::Keep);
        }
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
    // у окон X11 всё это делает X-сервер, а место ставит map_window_request
    if let Some((window, toplevel)) = shell.window_for_surface(surface).and_then(|w| w.toplevel().cloned().map(|t| (w, t))) {
        let initial_configure_sent = with_states(surface, |states| {
            states.data_map.get::<XdgToplevelSurfaceData>().unwrap().lock().unwrap().initial_configure_sent
        });
        if !initial_configure_sent {
            toplevel.send_configure();
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
    /// Программа просит режим (on) или выйти из него (!on); уже так — ничего.
    pub fn toplevel_mode(&mut self, surface: &ToplevelSurface, mode: crate::workspaces::Mode, on: bool) {
        if let Some(window) = self.windows.iter().find(|w| w.toplevel() == Some(surface)).cloned() {
            self.window_mode(&window, mode, on);
        }
    }

    pub fn window_mode(&mut self, window: &Window, mode: crate::workspaces::Mode, on: bool) {
        let current = crate::workspaces::data(window).mode;
        if (current == mode) != on {
            self.set_mode(window, mode);
        } else if let Some(t) = window.toplevel().filter(|t| t.is_initial_configure_sent()) {
            // ответ на просьбу нужен, даже если менять нечего
            t.send_configure();
        }
    }

    pub fn window_title_changed(&mut self, window: &Window) {
        let address = crate::workspaces::data(window).address;
        let (class, title) = crate::workspaces::class_title(window);
        self.ipc_event("windowtitle", &format!("{address:x}"));
        self.ipc_event("windowtitlev2", &format!("{address:x},{title}"));
        if self.focused_window().as_ref() == Some(window) {
            self.ipc_event("activewindow", &format!("{class},{title}"));
        }
    }

    /// Всплывающее меню не вылезает за экран — и у окон, и у панелей Delta.
    pub fn unconstrain_popup(&self, popup: &PopupSurface) {
        let Ok(root) = find_popup_root_surface(&PopupKind::Xdg(popup.clone())) else { return };
        // начало родителя на столе и монитор, в который меню должно влезть
        let parent = if let Some(window) = self.window_for_surface(&root) {
            let geo = self.space.element_geometry(&window).unwrap_or_default();
            let output = self.space.output_under(geo.loc.to_f64()).next().or_else(|| self.space.outputs().next()).cloned();
            output.map(|o| (geo.loc, o))
        } else {
            self.space.outputs().find_map(|o| {
                let map = layer_map_for_output(o);
                let layer = map.layer_for_surface(&root, WindowSurfaceType::TOPLEVEL)?;
                let loc = map.layer_geometry(layer)?.loc + self.space.output_geometry(o)?.loc;
                Some((loc, o.clone()))
            })
        };
        let Some((parent_loc, output)) = parent else { return };
        let Some(output_geo) = self.space.output_geometry(&output) else { return };

        // цель — относительно родителя меню
        let mut target = output_geo;
        target.loc -= get_popup_toplevel_coords(&PopupKind::Xdg(popup.clone()));
        target.loc -= parent_loc;
        popup.with_pending_state(|state| {
            state.geometry = state.positioner.get_unconstrained_geometry(target);
        });
    }
}

// --- xdg-decoration: заголовки рисует не программа. Кнопки окна у Delta
// (WindowControls), поэтому всегда «на стороне сервера», как в Hyprland ---
fn server_side(toplevel: &ToplevelSurface) {
    toplevel.with_pending_state(|s| s.decoration_mode = Some(DecorationMode::ServerSide));
    let configured = with_states(toplevel.wl_surface(), |states| {
        states
            .data_map
            .get::<XdgToplevelSurfaceData>()
            .is_some_and(|d| d.lock().unwrap().initial_configure_sent)
    });
    if configured {
        toplevel.send_pending_configure();
    }
}

impl XdgDecorationHandler for Shell {
    fn new_decoration(&mut self, toplevel: ToplevelSurface) {
        server_side(&toplevel);
    }
    fn request_mode(&mut self, toplevel: ToplevelSurface, _mode: DecorationMode) {
        server_side(&toplevel);
    }
    fn unset_mode(&mut self, toplevel: ToplevelSurface) {
        server_side(&toplevel);
    }
}
delegate_xdg_decoration!(Shell);
