use std::{ffi::OsString, sync::Arc};

use smithay::{
    desktop::{PopupManager, Space, Window, WindowSurfaceType},
    input::{Seat, SeatState},
    reexports::{
        calloop::{generic::Generic, EventLoop, Interest, LoopSignal, Mode, PostAction},
        wayland_server::{
            backend::{ClientData, ClientId, DisconnectReason},
            protocol::wl_surface::WlSurface,
            Display, DisplayHandle,
        },
    },
    utils::{Logical, Point, Serial, SERIAL_COUNTER},
    wayland::{
        compositor::{CompositorClientState, CompositorState},
        output::OutputManagerState,
        selection::data_device::DataDeviceState,
        shell::xdg::XdgShellState,
        shm::ShmState,
        socket::ListeningSocketSource,
    },
};

use crate::{config, CalloopData};

/// Всё состояние композитора.
pub struct Shell {
    pub start_time: std::time::Instant,
    pub socket_name: OsString,
    pub display_handle: DisplayHandle,

    /// Плоскость, на которой лежат окна и выходы (мониторы). Порядок окон в
    /// ней — порядок наложения: последнее поднятое — сверху.
    pub space: Space<Window>,
    pub loop_signal: LoopSignal,

    // состояния протоколов Smithay
    pub compositor_state: CompositorState,
    pub xdg_shell_state: XdgShellState,
    pub shm_state: ShmState,
    pub output_manager_state: OutputManagerState,
    pub seat_state: SeatState<Shell>,
    pub data_device_state: DataDeviceState,
    pub popups: PopupManager,

    pub seat: Seat<Self>,
    /// сколько окон уже поставлено каскадом (сдвиг следующего)
    pub cascade: i32,
}

impl Shell {
    pub fn new(event_loop: &mut EventLoop<CalloopData>, display: Display<Self>) -> Self {
        let dh = display.handle();

        let compositor_state = CompositorState::new::<Self>(&dh);
        let xdg_shell_state = XdgShellState::new::<Self>(&dh);
        let shm_state = ShmState::new::<Self>(&dh, vec![]);
        let output_manager_state = OutputManagerState::new_with_xdg_output::<Self>(&dh);
        let mut seat_state = SeatState::new();
        let data_device_state = DataDeviceState::new::<Self>(&dh);

        // место (seat) — клавиатура и мышь одного пользователя. В окне отладки
        // они есть всегда; в настоящей сессии их подключение отслеживает libinput
        let mut seat: Seat<Self> = seat_state.new_wl_seat(&dh, "seat0");
        seat.add_keyboard(Default::default(), 300, 30).expect("клавиатура");
        seat.add_pointer();

        let socket_name = Self::init_wayland_listener(display, event_loop);

        Self {
            start_time: std::time::Instant::now(),
            display_handle: dh,
            space: Space::default(),
            loop_signal: event_loop.get_signal(),
            socket_name,
            compositor_state,
            xdg_shell_state,
            shm_state,
            output_manager_state,
            seat_state,
            data_device_state,
            popups: PopupManager::default(),
            seat,
            cascade: 0,
        }
    }

    /// Сокет wayland-N для программ и сам Display — в цикл событий.
    fn init_wayland_listener(display: Display<Shell>, event_loop: &mut EventLoop<CalloopData>) -> OsString {
        let listening_socket = ListeningSocketSource::new_auto().expect("сокет Wayland");
        let socket_name = listening_socket.socket_name().to_os_string();
        let handle = event_loop.handle();

        handle
            .insert_source(listening_socket, move |client_stream, _, data| {
                if let Err(e) = data
                    .display_handle
                    .insert_client(client_stream, Arc::new(ClientState::default()))
                {
                    tracing::warn!("программа не подключилась: {e}");
                }
            })
            .expect("источник сокета");

        handle
            .insert_source(Generic::new(display, Interest::READ, Mode::Level), |_, display, data| {
                // Display живёт, пока жив источник: get_mut безопасен
                unsafe {
                    display.get_mut().dispatch_clients(&mut data.state).unwrap();
                }
                Ok(PostAction::Continue)
            })
            .expect("источник Display");

        socket_name
    }

    /// Запустить программу внутри оболочки (через sh -c: можно с аргументами).
    pub fn spawn(&self, command: &str) {
        let r = std::process::Command::new("sh")
            .arg("-c")
            .arg(command)
            .env("WAYLAND_DISPLAY", &self.socket_name)
            .env("XDG_CURRENT_DESKTOP", "Vanks")
            .env("XDG_SESSION_TYPE", "wayland")
            // X11 вокруг нам не нужен: программа должна прийти к нам по Wayland
            .env_remove("DISPLAY")
            .spawn();
        if let Err(e) = r {
            tracing::warn!("не запустилось «{command}»: {e}");
        }
    }

    /// Окно и точка на его поверхности под курсором.
    pub fn surface_under(&self, pos: Point<f64, Logical>) -> Option<(WlSurface, Point<f64, Logical>)> {
        self.space.element_under(pos).and_then(|(window, location)| {
            window
                .surface_under(pos - location.to_f64(), WindowSurfaceType::ALL)
                .map(|(s, p)| (s, (p + location).to_f64()))
        })
    }

    pub fn window_for_surface(&self, surface: &WlSurface) -> Option<Window> {
        self.space
            .elements()
            .find(|w| w.toplevel().map(|t| t.wl_surface() == surface).unwrap_or(false))
            .cloned()
    }

    /// Новое окно: по центру экрана, каждое следующее — со сдвигом (каскад).
    pub fn initial_position(&mut self, size: (i32, i32)) -> Point<i32, Logical> {
        let Some(output) = self.space.outputs().next() else {
            return (0, 0).into();
        };
        let geo = self.space.output_geometry(output).unwrap_or_default();
        let step = config::CASCADE_STEP * (self.cascade % 8);
        self.cascade += 1;
        let x = geo.loc.x + (geo.size.w - size.0).max(0) / 2 + step;
        let y = geo.loc.y + (geo.size.h - size.1).max(0) / 2 + step;
        (x, y).into()
    }

    /// Поднять окно наверх и отдать ему клавиатуру — щелчок, Super+перетаскивание,
    /// новое окно. Остальные окна становятся неактивными (рамки, курсор ввода).
    pub fn focus_window(&mut self, window: &Window, serial: Serial) {
        self.space.raise_element(window, true);
        let surface = window.toplevel().map(|t| t.wl_surface().clone());
        if let Some(keyboard) = self.seat.get_keyboard() {
            keyboard.set_focus(self, surface, serial);
        }
        self.space.elements().for_each(|w| {
            if let Some(t) = w.toplevel() {
                t.send_pending_configure();
            }
        });
    }

    /// Фокус — верхнему окну (закрыли окно с фокусом), или никому.
    pub fn focus_top(&mut self) {
        let serial = SERIAL_COUNTER.next_serial();
        if let Some(top) = self.space.elements().last().cloned() {
            self.focus_window(&top, serial);
        } else if let Some(keyboard) = self.seat.get_keyboard() {
            keyboard.set_focus(self, Option::<WlSurface>::None, serial);
        }
    }

    /// Окно с фокусом клавиатуры.
    pub fn focused_window(&self) -> Option<Window> {
        let focus = self.seat.get_keyboard()?.current_focus()?;
        self.window_for_surface(&focus)
    }
}

/// Данные каждой подключённой программы.
#[derive(Default)]
pub struct ClientState {
    pub compositor_state: CompositorClientState,
}

impl ClientData for ClientState {
    fn initialized(&self, _client_id: ClientId) {}
    fn disconnected(&self, _client_id: ClientId, _reason: DisconnectReason) {}
}
