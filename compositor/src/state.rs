use std::{ffi::OsString, sync::Arc};

use smithay::{
    backend::{renderer::gles::GlesRenderer, winit::WinitGraphicsBackend},
    desktop::{layer_map_for_output, utils::send_frames_surface_tree, PopupManager, Space, Window, WindowSurfaceType},
    wayland::seat::WaylandFocus,
    input::{keyboard::XkbConfig, pointer::CursorImageStatus, Seat, SeatState},
    reexports::{
        calloop::{generic::Generic, EventLoop, Interest, LoopHandle, LoopSignal, Mode, PostAction},
        wayland_server::{
            backend::{ClientData, ClientId, DisconnectReason},
            protocol::wl_surface::WlSurface,
            Display, DisplayHandle,
        },
    },
    utils::{Clock, Logical, Monotonic, Point, Serial, SERIAL_COUNTER},
    wayland::{
        compositor::{CompositorClientState, CompositorState},
        content_type::ContentTypeState,
        cursor_shape::CursorShapeManagerState,
        dmabuf::DmabufState,
        drm_syncobj::DrmSyncobjState,
        fractional_scale::{with_fractional_scale, FractionalScaleManagerState},
        idle_inhibit::IdleInhibitManagerState,
        output::OutputManagerState,
        pointer_constraints::PointerConstraintsState,
        pointer_gestures::PointerGesturesState,
        presentation::PresentationState,
        relative_pointer::RelativePointerManagerState,
        selection::{
            data_device::DataDeviceState, primary_selection::PrimarySelectionState, wlr_data_control::DataControlState,
        },
        session_lock::SessionLockManagerState,
        shell::{
            wlr_layer::{Layer, WlrLayerShellState},
            xdg::{decoration::XdgDecorationState, XdgShellState},
        },
        shm::ShmState,
        single_pixel_buffer::SinglePixelBufferState,
        socket::ListeningSocketSource,
        viewporter::ViewporterState,
        xdg_activation::XdgActivationState,
        xwayland_shell::XWaylandShellState,
    },
    xwayland::X11Wm,
};

use crate::{
    backend::udev::UdevData, config, cursor::Cursor, focus::KeyFocus, ipc::Ipc, protocols::global_shortcuts::GlobalShortcutsState,
    lock::{Lock, LockSurfaceOn},
    protocols::{focus_grab::FocusGrabState, foreign_toplevel::ForeignToplevelState, idle_notify::IdleNotifyState, screencopy::ScreencopyState},
    settings::Settings, workspaces::Workspaces, CalloopData,
};

/// Всё состояние композитора.
pub struct Shell {
    pub start_time: std::time::Instant,
    /// те же часы, что у wp_presentation
    pub clock: Clock<Monotonic>,
    pub socket_name: OsString,
    pub display_handle: DisplayHandle,

    /// Плоскость, на которой лежат окна и выходы (мониторы). Порядок окон в
    /// ней — порядок наложения: последнее поднятое — сверху.
    pub space: Space<Window>,
    pub loop_signal: LoopSignal,
    pub loop_handle: LoopHandle<'static, CalloopData>,
    pub settings: Settings,

    // состояния протоколов Smithay
    pub compositor_state: CompositorState,
    pub xdg_shell_state: XdgShellState,
    pub xdg_decoration_state: XdgDecorationState,
    pub layer_shell_state: WlrLayerShellState,
    pub shm_state: ShmState,
    pub output_manager_state: OutputManagerState,
    pub seat_state: SeatState<Shell>,
    pub data_device_state: DataDeviceState,
    pub dmabuf_state: DmabufState,
    /// явная синхронизация кадров, если её умеет видеокарта
    pub syncobj_state: Option<DrmSyncobjState>,
    pub cursor_shape_state: CursorShapeManagerState,
    pub session_lock_state: SessionLockManagerState,
    pub primary_selection_state: PrimarySelectionState,
    pub data_control_state: DataControlState,
    pub xdg_activation_state: XdgActivationState,
    pub popups: PopupManager,

    pub seat: Seat<Self>,
    /// до этого времени рабочий стол виден сквозь замок (lock.rs, переход Delta)
    pub lock_xray: Option<std::time::Instant>,
    /// все окна, и на других столах, — в порядке наложения (последнее сверху)
    pub windows: Vec<Window>,
    pub workspaces: Workspaces,
    pub fx: crate::fx::Fx,
    /// IPC как у Hyprland (ipc.rs) — для Delta
    pub ipc: Option<Ipc>,
    pub global_shortcuts: GlobalShortcutsState,
    pub focus_grabs: FocusGrabState,
    pub foreign_toplevels: ForeignToplevelState,
    pub color: crate::protocols::color_management::ColorManagement,
    pub screencopy: ScreencopyState,
    pub idle_notify: IdleNotifyState,
    pub idle_inhibit_state: IdleInhibitManagerState,
    /// поверхности, которые просят не считать простоем (видео, игры)
    pub idle_inhibitors: Vec<WlSurface>,
    /// Super нажат и пока ни с чем не сочетался (отпустят — меню Delta)
    pub super_alone: bool,
    /// идёт смахивание тремя пальцами: сколько уже прошли по горизонтали
    pub swipe: Option<f64>,
    /// номер строки delta-drag.json
    pub drag_seq: u64,
    /// блокировка экрана (lock.rs)
    pub lock: Lock,
    pub lock_surfaces: Vec<LockSurfaceOn>,
    pub lock_retry: Option<std::time::Instant>,

    /// какой курсор просит программа под мышью (или своя стрелка)
    pub cursor_status: CursorImageStatus,
    /// оконный менеджер Xwayland и номер его дисплея, когда он готов
    pub xwm: Option<X11Wm>,
    pub xdisplay: Option<u32>,
    pub xwayland_shell_state: XWaylandShellState,
    /// тема курсора — рисуем сами только в настоящей сессии
    pub cursor: Cursor,
    /// настоящая сессия (DRM, libinput, libseat); в окне отладки — None
    pub udev: Option<UdevData>,
    /// окно отладки; в настоящей сессии — None
    pub winit: Option<WinitGraphicsBackend<GlesRenderer>>,
}

impl Shell {
    pub fn new(event_loop: &mut EventLoop<'static, CalloopData>, display: Display<Self>) -> Self {
        let dh = display.handle();

        let compositor_state = CompositorState::new::<Self>(&dh);
        let xdg_shell_state = XdgShellState::new::<Self>(&dh);
        let xdg_decoration_state = XdgDecorationState::new::<Self>(&dh);
        let layer_shell_state = WlrLayerShellState::new::<Self>(&dh);
        let shm_state = ShmState::new::<Self>(&dh, vec![]);
        let output_manager_state = OutputManagerState::new_with_xdg_output::<Self>(&dh);
        let mut seat_state = SeatState::new();
        let data_device_state = DataDeviceState::new::<Self>(&dh);
        let cursor_shape_state = CursorShapeManagerState::new::<Self>(&dh);
        let session_lock_state = SessionLockManagerState::new::<Self, _>(&dh, |_| true);
        let global_shortcuts = GlobalShortcutsState::new(&dh);
        let focus_grabs = FocusGrabState::new(&dh);
        let foreign_toplevels = ForeignToplevelState::new(&dh);
        let screencopy = ScreencopyState::new(&dh);
        let idle_notify = IdleNotifyState::new(&dh, &event_loop.handle());
        let idle_inhibit_state = IdleInhibitManagerState::new::<Self>(&dh);
        let primary_selection_state = PrimarySelectionState::new::<Self>(&dh);
        // привилегированных программ у нас нет: буфер обмена без окна доступен всем, как в Hyprland
        let data_control_state = DataControlState::new::<Self, _>(&dh, Some(&primary_selection_state), |_| true);
        let xdg_activation_state = XdgActivationState::new::<Self>(&dh);
        // живут вместе с Display, состояния хранить незачем
        ViewporterState::new::<Self>(&dh);
        SinglePixelBufferState::new::<Self>(&dh);
        ContentTypeState::new::<Self>(&dh);
        FractionalScaleManagerState::new::<Self>(&dh);
        PresentationState::new::<Self>(&dh, libc::CLOCK_MONOTONIC as u32);
        RelativePointerManagerState::new::<Self>(&dh);
        PointerConstraintsState::new::<Self>(&dh);
        PointerGesturesState::new::<Self>(&dh);
        let settings = Settings::load();

        // место (seat) — клавиатура и мышь одного пользователя. Раскладки и
        // повтор — из «Клавиатуры» Delta; переключение раскладки (Alt+Shift и
        // т. п.) делает сама xkb по опции switchKeys
        let mut seat: Seat<Self> = seat_state.new_wl_seat(&dh, "seat0");
        let layout = settings.input.xkb_layout();
        let options = Some(settings.input.switch_keys.clone()).filter(|o| !o.is_empty());
        let (delay, rate) = settings.input.repeat();
        let xkb = XkbConfig { layout: &layout, options: options.clone(), ..Default::default() };
        if seat.add_keyboard(xkb, delay, rate).is_ok() {
            tracing::info!(layout, ?options, delay, rate, "клавиатура");
        } else {
            tracing::warn!(layout, ?options, "раскладки из настроек не подошли, беру us");
            seat.add_keyboard(XkbConfig::default(), delay, rate).expect("клавиатура");
        }
        seat.add_pointer();

        let socket_name = Self::init_wayland_listener(display, event_loop);
        let dh_x = dh.clone();

        Self {
            start_time: std::time::Instant::now(),
            clock: Clock::new(),
            display_handle: dh,
            space: Space::default(),
            loop_signal: event_loop.get_signal(),
            loop_handle: event_loop.handle(),
            settings,
            socket_name,
            compositor_state,
            xdg_shell_state,
            xdg_decoration_state,
            layer_shell_state,
            shm_state,
            output_manager_state,
            seat_state,
            data_device_state,
            dmabuf_state: DmabufState::new(),
            syncobj_state: None,
            cursor_shape_state,
            session_lock_state,
            primary_selection_state,
            data_control_state,
            xdg_activation_state,
            popups: PopupManager::default(),
            seat,
            lock_xray: None,
            windows: Vec::new(),
            workspaces: Workspaces::default(),
            fx: Default::default(),
            ipc: None,
            global_shortcuts,
            focus_grabs,
            foreign_toplevels,
            color: Default::default(),
            screencopy,
            idle_notify,
            idle_inhibit_state,
            idle_inhibitors: Vec::new(),
            super_alone: false,
            swipe: None,
            drag_seq: 0,
            lock: Lock::default(),
            lock_surfaces: Vec::new(),
            lock_retry: None,
            cursor_status: CursorImageStatus::default_named(),
            xwm: None,
            xdisplay: None,
            xwayland_shell_state: XWaylandShellState::new::<Self>(&dh_x),
            cursor: Cursor::load(),
            udev: None,
            winit: None,
        }
    }

    /// Сокет wayland-N для программ и сам Display — в цикл событий.
    fn init_wayland_listener(display: Display<Shell>, event_loop: &mut EventLoop<'static, CalloopData>) -> OsString {
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
        use std::os::unix::process::CommandExt;
        let mut cmd = std::process::Command::new("sh");
        // SIGTERM и SIGINT оболочка ловит сама (main.rs) и держит их
        // заблокированными; программе это не передаём, иначе её не закрыть kill
        unsafe {
            cmd.pre_exec(|| {
                let mut set = std::mem::MaybeUninit::<libc::sigset_t>::uninit();
                libc::sigemptyset(set.as_mut_ptr());
                libc::pthread_sigmask(libc::SIG_SETMASK, set.as_ptr(), std::ptr::null_mut());
                Ok(())
            });
        }
        cmd
            .arg("-c")
            .arg(command)
            .env("WAYLAND_DISPLAY", &self.socket_name)
            // Delta и hyprctl находят нас как Hyprland (ipc.rs)
            .env("HYPRLAND_INSTANCE_SIGNATURE", self.ipc.as_ref().map(|i| i.signature.as_str()).unwrap_or(""))
            // оболочка выключает то, что здесь делает сам композитор (Jelly.qml)
            .env("DELTA_COMPOSITOR", "1")
            .env("XDG_CURRENT_DESKTOP", "Delta")
            .env("XDG_SESSION_DESKTOP", "delta")
            .env("XDG_SESSION_TYPE", "wayland")
            ;
        // X11 вокруг нам не нужен: только свой Xwayland
        match self.xdisplay {
            Some(n) => cmd.env("DISPLAY", format!(":{n}")),
            None => cmd.env_remove("DISPLAY"),
        };
        let r = cmd.spawn();
        match r {
            // завершившуюся программу надо забрать, иначе останется зомби
            Ok(mut child) => {
                std::thread::spawn(move || child.wait());
            }
            Err(e) => tracing::warn!("не запустилось «{command}»: {e}"),
        }
    }

    /// Поверхность под курсором и её начало на столе. Сверху вниз: слои
    /// «поверх всего» и верхний (панели, меню Delta), окна, нижний слой и фон.
    pub fn surface_under(&self, pos: Point<f64, Logical>) -> Option<(WlSurface, Point<f64, Logical>)> {
        // экран заблокирован: под мышью только замок
        if self.is_locked() {
            return self.lock_surface_under(pos);
        }
        if let Some((s, at, _)) = self.layer_surface_under(pos, &[Layer::Overlay, Layer::Top]) {
            return Some((s, at));
        }
        let window = self.space.element_under(pos).and_then(|(window, location)| {
            window
                .surface_under(pos - location.to_f64(), WindowSurfaceType::ALL)
                .map(|(s, p)| (s, (p + location).to_f64()))
        });
        window.or_else(|| self.layer_surface_under(pos, &[Layer::Bottom, Layer::Background]).map(|(s, at, _)| (s, at)))
    }

    /// Место для окон на мониторе: без краёв, занятых панелями.
    pub fn usable_area(&self, output: &smithay::output::Output) -> smithay::utils::Rectangle<i32, Logical> {
        let geo = self.space.output_geometry(output).unwrap_or_default();
        let zone = layer_map_for_output(output).non_exclusive_zone();
        smithay::utils::Rectangle::new(geo.loc + zone.loc, zone.size)
    }

    /// Программам на мониторе — «можно рисовать следующий кадр»: окнам и слоям.
    pub fn send_frames(&self, output: &smithay::output::Output) {
        let time = self.start_time.elapsed();
        let throttle = Some(std::time::Duration::ZERO);
        // экран заблокирован: остальное не видно — незачем и рисовать
        if self.is_locked() {
            if let Some(lock) = self.lock_surface(output) {
                send_frames_surface_tree(lock.wl_surface(), output, time, throttle, |_, _| Some(output.clone()));
            }
            if !self.lock_xray_active() {
                return;
            }
        }
        let scale = output.current_scale().fractional_scale();
        for window in self.space.elements() {
            // окно на другом мониторе рисует под его кадры (и его масштаб)
            let on = self.space.outputs_for_element(window);
            if !on.is_empty() && !on.contains(output) {
                continue;
            }
            window.send_frame(output, time, throttle, |_, _| Some(output.clone()));
            window.with_surfaces(|_, states| with_fractional_scale(states, |f| f.set_preferred_scale(scale)));
        }
        for layer in layer_map_for_output(output).layers() {
            layer.send_frame(output, time, throttle, |_, _| Some(output.clone()));
            layer.with_surfaces(|_, states| with_fractional_scale(states, |f| f.set_preferred_scale(scale)));
        }
    }

    pub fn window_for_surface(&self, surface: &WlSurface) -> Option<Window> {
        self.windows
            .iter()
            .find(|w| w.wl_surface().as_deref() == Some(surface))
            .cloned()
    }

    /// Новое окно: по центру экрана. Если там уже стоит другое — со сдвигом
    /// (каскад), но не за край экрана.
    pub fn initial_position(&mut self, size: (i32, i32)) -> Point<i32, Logical> {
        let Some(output) = self.output_under_pointer() else {
            return (0, 0).into();
        };
        let geo = self.usable_area(&output);
        let (free_w, free_h) = ((geo.size.w - size.0).max(0), (geo.size.h - size.1).max(0));
        let at = |step: i32| -> Point<i32, Logical> {
            let shift = config::CASCADE_STEP * step;
            (geo.loc.x + (free_w / 2 + shift).min(free_w), geo.loc.y + (free_h / 2 + shift).min(free_h)).into()
        };
        let taken = |loc: Point<i32, Logical>| self.space.elements().any(|w| self.space.element_location(w) == Some(loc));
        (0..8).map(at).find(|loc| !taken(*loc)).unwrap_or_else(|| at(0))
    }

    /// Поднять окно наверх и отдать ему клавиатуру — щелчок, Super+перетаскивание,
    /// новое окно. Остальные окна становятся неактивными (рамки, курсор ввода).
    pub fn focus_window(&mut self, window: &Window, serial: Serial) {
        self.space.raise_element(window, true);
        self.raise_in_stack(window);
        // открытые меню X11 остаются над окном
        let menus: Vec<Window> = self.space.elements().filter(|w| w.x11_surface().is_some_and(|x| x.is_override_redirect())).cloned().collect();
        menus.iter().for_each(|m| self.space.raise_element(m, false));
        if let (Some(xwm), Some(x11)) = (self.xwm.as_mut(), window.x11_surface()) {
            if let Err(e) = xwm.raise_window(x11) {
                tracing::debug!("окно X11 не поднялось: {e}");
            }
        }
        // при блокировке клавиатура только у замка
        if self.is_locked() {
            return;
        }
        if let Some(s) = window.wl_surface() {
            self.focus_grab_window(&s);
        }
        let target = match window.x11_surface() {
            Some(x11) => Some(KeyFocus::X11(x11.clone())),
            None => window.wl_surface().map(|s| KeyFocus::Surface(s.into_owned())),
        };
        if let Some(keyboard) = self.seat.get_keyboard() {
            keyboard.set_focus(self, target, serial);
        }
        self.space.elements().for_each(|w| {
            if let Some(t) = w.toplevel() {
                t.send_pending_configure();
            }
        });
    }

    /// Фокус — верхнему видимому окну (закрыли окно с фокусом, сменили стол), или никому.
    pub fn focus_top(&mut self) {
        if self.is_locked() {
            return;
        }
        let serial = SERIAL_COUNTER.next_serial();
        let top = self.windows.iter().rev().find(|w| self.space.element_location(w).is_some()).cloned();
        if let Some(top) = top {
            self.focus_window(&top, serial);
        } else if let Some(keyboard) = self.seat.get_keyboard() {
            keyboard.set_focus(self, None, serial);
        }
    }

    /// Окно с фокусом клавиатуры.
    pub fn focused_window(&self) -> Option<Window> {
        let focus = self.seat.get_keyboard()?.current_focus()?;
        self.window_for_focus(&focus)
    }

    pub fn window_for_focus(&self, focus: &KeyFocus) -> Option<Window> {
        match focus {
            KeyFocus::Surface(s) => self.window_for_surface(s),
            KeyFocus::X11(x) => self.windows.iter().find(|w| w.x11_surface() == Some(x)).cloned(),
        }
    }

    /// Точка, ближайшая к pos, на каком-нибудь мониторе: мышь не уходит за край.
    pub fn clamp_to_outputs(&self, pos: Point<f64, Logical>) -> Point<f64, Logical> {
        let mut best: Option<(f64, Point<f64, Logical>)> = None;
        for output in self.space.outputs() {
            let Some(geo) = self.space.output_geometry(output) else { continue };
            let geo = geo.to_f64();
            let x = pos.x.clamp(geo.loc.x, geo.loc.x + geo.size.w - 1.0);
            let y = pos.y.clamp(geo.loc.y, geo.loc.y + geo.size.h - 1.0);
            let d = (x - pos.x).powi(2) + (y - pos.y).powi(2);
            if best.map_or(true, |(bd, _)| d < bd) {
                best = Some((d, (x, y).into()));
            }
        }
        best.map(|(_, p)| p).unwrap_or(pos)
    }

    /// Монитор отключили: окна, которые оказались вне всех мониторов, —
    /// на первый, по центру. Мышь — туда же, если тоже осталась в пустоте.
    pub fn fixup_windows(&mut self) {
        let Some(first) = self.space.outputs().next().and_then(|o| self.space.output_geometry(o)) else { return };
        let lost: Vec<Window> = self
            .space
            .elements()
            .filter(|w| {
                let Some(loc) = self.space.element_location(w) else { return false };
                !self.space.outputs().any(|o| self.space.output_geometry(o).map_or(false, |g| g.contains(loc)))
            })
            .cloned()
            .collect();
        for w in lost {
            let size = w.geometry().size;
            let loc = first.loc + Point::from(((first.size.w - size.w).max(0) / 2, (first.size.h - size.h).max(0) / 2));
            self.space.map_element(w, loc, false);
        }
        if let Some(pointer) = self.seat.get_pointer() {
            let pos = pointer.current_location();
            let clamped = self.clamp_to_outputs(pos);
            if clamped != pos {
                pointer.set_location(clamped);
            }
        }
    }
}

/// Данные каждой подключённой программы.
#[derive(Default)]
pub struct ClientState {
    pub compositor_state: CompositorClientState,
}

impl ClientData for ClientState {
    fn initialized(&self, _client_id: ClientId) {}
    fn disconnected(&self, _client_id: ClientId, reason: DisconnectReason) {
        // программа закрылась сама — обычное дело; ошибка протокола — наша забота
        if let DisconnectReason::ProtocolError(e) = reason {
            tracing::warn!(error = %e, "программа отключена за ошибку протокола");
        }
    }
}
