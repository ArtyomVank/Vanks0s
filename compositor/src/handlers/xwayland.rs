//! XWayland: старые программы и игры на X11 (Steam, CS2, Wine). Сам X-сервер —
//! отдельная программа Xwayland, а мы — его оконный менеджер: окна X11 живут
//! рядом с окнами Wayland, в том же списке и на тех же столах.

use std::{os::fd::OwnedFd, process::Stdio};

use smithay::{
    delegate_xwayland_shell,
    desktop::Window,
    input::pointer::{Focus, GrabStartData},
    utils::{Logical, Rectangle, SERIAL_COUNTER},
    wayland::{
        selection::{
            data_device::{
                clear_data_device_selection, current_data_device_selection_userdata, request_data_device_client_selection,
                set_data_device_selection,
            },
            primary_selection::{
                clear_primary_selection, current_primary_selection_userdata, request_primary_client_selection, set_primary_selection,
            },
            SelectionTarget,
        },
        xwayland_shell::{XWaylandShellHandler, XWaylandShellState},
    },
    xwayland::{
        xwm::{Reorder, ResizeEdge as X11Edge, WmWindowProperty, XwmId},
        X11Surface, X11Wm, XWayland, XWaylandEvent, XwmHandler,
    },
};

use crate::{
    focus::KeyFocus,
    grabs::{resize_grab::ResizeEdge, MoveSurfaceGrab, ResizeSurfaceGrab},
    workspaces::{data, Mode, SPECIAL},
    CalloopData, Shell,
};

impl Shell {
    /// Запустить Xwayland; commands — когда он готов (им нужен DISPLAY).
    /// Не запустился — работаем без него: окна X11 не откроются, остальное да.
    pub fn start_xwayland(&mut self, commands: Vec<String>) {
        let spawned = XWayland::spawn(
            &self.display_handle,
            None,
            std::iter::empty::<(String, String)>(),
            true,
            Stdio::null(),
            Stdio::null(),
            |_| (),
        );
        let (xwayland, client) = match spawned {
            Ok(x) => x,
            Err(e) => {
                tracing::warn!("Xwayland не запустился, программы X11 работать не будут: {e}");
                commands.iter().for_each(|c| self.spawn(c));
                return;
            }
        };
        let mut commands = Some(commands);
        let source = self.loop_handle.insert_source(xwayland, move |event, _, data| {
            let state = &mut data.state;
            match event {
                XWaylandEvent::Ready { x11_socket, display_number } => {
                    match X11Wm::start_wm(state.loop_handle.clone(), x11_socket, client.clone()) {
                        Ok(wm) => {
                            state.xwm = Some(wm);
                            state.xdisplay = Some(display_number);
                            tracing::info!(display = display_number, "Xwayland готов");
                        }
                        Err(e) => tracing::warn!("оконный менеджер X11 не запустился: {e}"),
                    }
                }
                XWaylandEvent::Error => tracing::warn!("Xwayland завершился при запуске"),
            }
            for c in commands.take().unwrap_or_default() {
                state.spawn(&c);
            }
        });
        if let Err(e) = source {
            tracing::warn!("Xwayland не встал в цикл событий: {e}");
        }
    }

    fn x11_window(&self, surface: &X11Surface) -> Option<Window> {
        self.windows.iter().find(|w| w.x11_surface() == Some(surface)).cloned()
    }

    /// Окно X11 или меню X11 (их нет в списке окон) на экране.
    fn x11_element(&self, surface: &X11Surface) -> Option<Window> {
        self.space.elements().find(|w| w.x11_surface() == Some(surface)).cloned()
    }

    fn x11_gone(&mut self, surface: &X11Surface) {
        if let Some(window) = self.x11_window(surface) {
            self.untrack_window(&window);
            self.focus_top();
        } else if let Some(window) = self.x11_element(surface) {
            self.space.unmap_elem(&window);
        }
    }

    /// Начало тяги мышью, которую просит окно X11: кнопка должна быть нажата.
    fn x11_grab_start(&self, button: u32) -> Option<GrabStartData<Shell>> {
        let pointer = self.seat.get_pointer()?;
        pointer.is_grabbed().then(|| GrabStartData { focus: None, button, location: pointer.current_location() })
    }
}

impl XwmHandler for Shell {
    fn xwm_state(&mut self, _xwm: XwmId) -> &mut X11Wm {
        self.xwm.as_mut().expect("X11Wm запущен")
    }

    fn new_window(&mut self, _xwm: XwmId, _window: X11Surface) {}
    fn new_override_redirect_window(&mut self, _xwm: XwmId, _window: X11Surface) {}

    /// Окно просит показать себя: как новое окно Wayland, по центру и с фокусом.
    fn map_window_request(&mut self, _xwm: XwmId, surface: X11Surface) {
        if let Err(e) = surface.set_mapped(true) {
            tracing::warn!("окно X11 не показалось: {e}");
            return;
        }
        let window = Window::new_x11_window(surface.clone());
        self.track_window(&window);
        crate::workspaces::data(&window).fx.opening = true;
        let size = surface.geometry().size;
        let loc = self.initial_position((size.w, size.h));
        let _ = surface.configure(Rectangle::new(loc, size));
        self.space.map_element(window.clone(), loc, true);
        self.focus_window(&window, SERIAL_COUNTER.next_serial());
        // игра могла попросить весь экран ещё до показа
        if surface.is_fullscreen() || crate::rules::for_class(&surface.class()).fullscreen {
            self.set_mode(&window, Mode::Fullscreen);
        } else if surface.is_maximized() {
            self.set_mode(&window, Mode::Maximized);
        }
    }

    /// Меню и подсказки X11 ставят себя сами, координаты X — те же, что у нас.
    fn mapped_override_redirect_window(&mut self, _xwm: XwmId, surface: X11Surface) {
        let loc = surface.geometry().loc;
        let window = Window::new_x11_window(surface);
        // без активации: окно под меню должно остаться активным
        self.space.map_element(window, loc, false);
    }

    fn unmapped_window(&mut self, _xwm: XwmId, surface: X11Surface) {
        self.x11_gone(&surface);
        if !surface.is_override_redirect() {
            let _ = surface.set_mapped(false);
        }
    }

    fn destroyed_window(&mut self, _xwm: XwmId, surface: X11Surface) {
        self.x11_gone(&surface);
    }

    /// Окно просит место и размер. В обычном режиме — пожалуйста; развёрнутое и
    /// на весь экран остаётся как есть (X всё равно ждёт ответа).
    fn configure_request(
        &mut self,
        _xwm: XwmId,
        surface: X11Surface,
        x: Option<i32>,
        y: Option<i32>,
        w: Option<u32>,
        h: Option<u32>,
        reorder: Option<Reorder>,
    ) {
        let mut geo = surface.geometry();
        let window = self.x11_window(&surface);
        // программа подняла своё окно (Steam: уже открытые друзья и настройки). Чужому
        // окну фокус не отдаём: поднимаем, только если сейчас активна та же программа
        if let (Some(Reorder::Top), Some(w)) = (reorder, window.as_ref()) {
            let same = matches!(self.seat.get_keyboard().and_then(|k| k.current_focus()),
                Some(KeyFocus::X11(x)) if x != surface && x.class() == surface.class());
            if same && self.space.element_location(w).is_some() {
                self.focus_window(&w.clone(), SERIAL_COUNTER.next_serial());
            }
        }
        if window.as_ref().is_some_and(|w| data(w).mode != Mode::Normal) {
            let _ = surface.configure(geo);
            return;
        }
        if let Some(x) = x {
            geo.loc.x = x;
        }
        if let Some(y) = y {
            geo.loc.y = y;
        }
        if let Some(w) = w {
            geo.size.w = w as i32;
        }
        if let Some(h) = h {
            geo.size.h = h as i32;
        }
        let _ = surface.configure(geo);
        if let Some(window) = window.filter(|w| self.space.element_location(w).is_some()) {
            self.space.map_element(window, geo.loc, false);
        }
    }

    fn configure_notify(&mut self, _xwm: XwmId, surface: X11Surface, geometry: Rectangle<i32, Logical>, _above: Option<u32>) {
        if !surface.is_override_redirect() {
            return;
        }
        if let Some(window) = self.x11_element(&surface) {
            self.space.map_element(window, geometry.loc, false);
        }
    }

    fn property_notify(&mut self, _xwm: XwmId, surface: X11Surface, property: WmWindowProperty) {
        if property == WmWindowProperty::Title {
            if let Some(window) = self.x11_window(&surface) {
                self.window_title_changed(&window);
            }
        }
    }

    fn maximize_request(&mut self, _xwm: XwmId, surface: X11Surface) {
        if let Some(window) = self.x11_window(&surface) {
            self.window_mode(&window, Mode::Maximized, true);
        }
    }
    fn unmaximize_request(&mut self, _xwm: XwmId, surface: X11Surface) {
        if let Some(window) = self.x11_window(&surface) {
            self.window_mode(&window, Mode::Maximized, false);
        }
    }
    fn fullscreen_request(&mut self, _xwm: XwmId, surface: X11Surface) {
        if let Some(window) = self.x11_window(&surface) {
            self.window_mode(&window, Mode::Fullscreen, true);
        }
    }
    fn unfullscreen_request(&mut self, _xwm: XwmId, surface: X11Surface) {
        if let Some(window) = self.x11_window(&surface) {
            self.window_mode(&window, Mode::Fullscreen, false);
        }
    }
    fn minimize_request(&mut self, _xwm: XwmId, surface: X11Surface) {
        if let Some(window) = self.x11_window(&surface) {
            self.move_to_workspace(&window, SPECIAL, false);
        }
    }

    fn unminimize_request(&mut self, _xwm: XwmId, surface: X11Surface) {
        if let Some(window) = self.x11_window(&surface) {
            if data(&window).workspace == SPECIAL {
                let id = self.active_ws(&self.focused_output_name());
                self.move_to_workspace(&window, id, false);
            }
            self.focus_window(&window, SERIAL_COUNTER.next_serial());
        }
    }

    fn resize_request(&mut self, _xwm: XwmId, surface: X11Surface, button: u32, edge: X11Edge) {
        let Some(window) = self.x11_window(&surface) else { return };
        let Some(start_data) = self.x11_grab_start(button) else { return };
        let Some(loc) = self.space.element_location(&window) else { return };
        let edges = match edge {
            X11Edge::Top => ResizeEdge::TOP,
            X11Edge::Bottom => ResizeEdge::BOTTOM,
            X11Edge::Left => ResizeEdge::LEFT,
            X11Edge::Right => ResizeEdge::RIGHT,
            X11Edge::TopLeft => ResizeEdge::TOP_LEFT,
            X11Edge::TopRight => ResizeEdge::TOP_RIGHT,
            X11Edge::BottomLeft => ResizeEdge::BOTTOM_LEFT,
            X11Edge::BottomRight => ResizeEdge::BOTTOM_RIGHT,
        };
        let size = window.geometry().size;
        let grab = ResizeSurfaceGrab::start(start_data, window, edges, Rectangle::new(loc, size));
        if let Some(pointer) = self.seat.get_pointer() {
            pointer.set_grab(self, grab, SERIAL_COUNTER.next_serial(), Focus::Clear);
        }
    }

    fn move_request(&mut self, _xwm: XwmId, surface: X11Surface, button: u32) {
        let Some(window) = self.x11_window(&surface) else { return };
        let Some(start_data) = self.x11_grab_start(button) else { return };
        let Some(initial_window_location) = self.space.element_location(&window) else { return };
        if let Some(pointer) = self.seat.get_pointer() {
            let grab = MoveSurfaceGrab::new(start_data, window, initial_window_location);
            pointer.set_grab(self, grab, SERIAL_COUNTER.next_serial(), Focus::Clear);
        }
    }

    // --- буфер обмена между X11 и Wayland ---

    /// Читать буфер из Wayland может только окно X11 с фокусом.
    fn allow_selection_access(&mut self, xwm: XwmId, _selection: SelectionTarget) -> bool {
        let focus = self.seat.get_keyboard().and_then(|k| k.current_focus());
        matches!(focus, Some(KeyFocus::X11(x)) if x.xwm_id() == Some(xwm))
    }

    fn send_selection(&mut self, _xwm: XwmId, selection: SelectionTarget, mime_type: String, fd: OwnedFd) {
        let result = match selection {
            SelectionTarget::Clipboard => request_data_device_client_selection(&self.seat, mime_type, fd).map_err(|e| e.to_string()),
            SelectionTarget::Primary => request_primary_client_selection(&self.seat, mime_type, fd).map_err(|e| e.to_string()),
        };
        if let Err(e) = result {
            tracing::debug!("буфер обмена для X11: {e}");
        }
    }

    fn new_selection(&mut self, _xwm: XwmId, selection: SelectionTarget, mime_types: Vec<String>) {
        let dh = self.display_handle.clone();
        match selection {
            SelectionTarget::Clipboard => set_data_device_selection(&dh, &self.seat, mime_types, ()),
            SelectionTarget::Primary => set_primary_selection(&dh, &self.seat, mime_types, ()),
        }
    }

    fn cleared_selection(&mut self, _xwm: XwmId, selection: SelectionTarget) {
        let dh = self.display_handle.clone();
        match selection {
            SelectionTarget::Clipboard => {
                if current_data_device_selection_userdata(&self.seat).is_some() {
                    clear_data_device_selection(&dh, &self.seat);
                }
            }
            SelectionTarget::Primary => {
                if current_primary_selection_userdata(&self.seat).is_some() {
                    clear_primary_selection(&dh, &self.seat);
                }
            }
        }
    }

    fn disconnected(&mut self, _xwm: XwmId) {
        tracing::warn!("Xwayland отключился");
        self.xwm = None;
        self.xdisplay = None;
    }
}

impl XWaylandShellHandler for Shell {
    fn xwayland_shell_state(&mut self) -> &mut XWaylandShellState {
        &mut self.xwayland_shell_state
    }
}
delegate_xwayland_shell!(Shell);

// цикл событий работает с CalloopData, поэтому X11Wm просит обработчик у него;
// вся работа — в Shell
impl XwmHandler for CalloopData {
    fn xwm_state(&mut self, xwm: XwmId) -> &mut X11Wm {
        XwmHandler::xwm_state(&mut self.state, xwm)
    }
    fn new_window(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::new_window(&mut self.state, xwm, window)
    }
    fn new_override_redirect_window(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::new_override_redirect_window(&mut self.state, xwm, window)
    }
    fn map_window_request(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::map_window_request(&mut self.state, xwm, window)
    }
    fn mapped_override_redirect_window(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::mapped_override_redirect_window(&mut self.state, xwm, window)
    }
    fn unmapped_window(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::unmapped_window(&mut self.state, xwm, window)
    }
    fn destroyed_window(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::destroyed_window(&mut self.state, xwm, window)
    }
    fn configure_request(
        &mut self,
        xwm: XwmId,
        window: X11Surface,
        x: Option<i32>,
        y: Option<i32>,
        w: Option<u32>,
        h: Option<u32>,
        reorder: Option<Reorder>,
    ) {
        XwmHandler::configure_request(&mut self.state, xwm, window, x, y, w, h, reorder)
    }
    fn configure_notify(&mut self, xwm: XwmId, window: X11Surface, geometry: Rectangle<i32, Logical>, above: Option<u32>) {
        XwmHandler::configure_notify(&mut self.state, xwm, window, geometry, above)
    }
    fn property_notify(&mut self, xwm: XwmId, window: X11Surface, property: WmWindowProperty) {
        XwmHandler::property_notify(&mut self.state, xwm, window, property)
    }
    fn maximize_request(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::maximize_request(&mut self.state, xwm, window)
    }
    fn unmaximize_request(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::unmaximize_request(&mut self.state, xwm, window)
    }
    fn fullscreen_request(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::fullscreen_request(&mut self.state, xwm, window)
    }
    fn unfullscreen_request(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::unfullscreen_request(&mut self.state, xwm, window)
    }
    fn minimize_request(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::minimize_request(&mut self.state, xwm, window)
    }
    fn unminimize_request(&mut self, xwm: XwmId, window: X11Surface) {
        XwmHandler::unminimize_request(&mut self.state, xwm, window)
    }
    fn resize_request(&mut self, xwm: XwmId, window: X11Surface, button: u32, edge: X11Edge) {
        XwmHandler::resize_request(&mut self.state, xwm, window, button, edge)
    }
    fn move_request(&mut self, xwm: XwmId, window: X11Surface, button: u32) {
        XwmHandler::move_request(&mut self.state, xwm, window, button)
    }
    fn allow_selection_access(&mut self, xwm: XwmId, selection: SelectionTarget) -> bool {
        XwmHandler::allow_selection_access(&mut self.state, xwm, selection)
    }
    fn send_selection(&mut self, xwm: XwmId, selection: SelectionTarget, mime_type: String, fd: OwnedFd) {
        XwmHandler::send_selection(&mut self.state, xwm, selection, mime_type, fd)
    }
    fn new_selection(&mut self, xwm: XwmId, selection: SelectionTarget, mime_types: Vec<String>) {
        XwmHandler::new_selection(&mut self.state, xwm, selection, mime_types)
    }
    fn cleared_selection(&mut self, xwm: XwmId, selection: SelectionTarget) {
        XwmHandler::cleared_selection(&mut self.state, xwm, selection)
    }
    fn disconnected(&mut self, xwm: XwmId) {
        XwmHandler::disconnected(&mut self.state, xwm)
    }
}

impl XWaylandShellHandler for CalloopData {
    fn xwayland_shell_state(&mut self) -> &mut XWaylandShellState {
        &mut self.state.xwayland_shell_state
    }
}
