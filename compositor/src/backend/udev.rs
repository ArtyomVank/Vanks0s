//! Настоящая сессия: композитор Delta сама ведёт видеокарту (DRM/KMS) и ввод
//! (libinput), а доступ к ним даёт libseat (logind или seatd) — так же, как
//! Hyprland. Запускается с текстовой консоли или экрана входа (greetd).
//!
//! Пока одна видеокарта — основная (boot VGA); мониторы на ней — все, с
//! горячим подключением. Вторая видеокарта (ноутбуки с дискретной) — в плане.
//!
//! Кадр: собираем элементы (окна, курсор) → DrmOutput сравнивает с прошлым
//! кадром → если что-то изменилось, ставим кадр на показ → VBlank от
//! монитора → следующий кадр. Если не изменилось ничего — пробуем снова
//! через один кадр монитора.

use std::{collections::HashMap, path::Path, time::Duration};

use smithay::{
    backend::{
        allocator::{
            gbm::{GbmAllocator, GbmBufferFlags, GbmDevice},
            Fourcc,
        },
        drm::{
            compositor::FrameFlags,
            exporter::gbm::GbmFramebufferExporter,
            output::{DrmOutput, DrmOutputManager, DrmOutputRenderElements},
            DrmDevice, DrmDeviceFd, DrmError, DrmEvent, DrmEventMetadata, DrmEventTime, DrmNode, NodeType,
        },
        egl::{EGLContext, EGLDevice, EGLDisplay},
        input::InputEvent,
        libinput::{LibinputInputBackend, LibinputSessionInterface},
        renderer::{gles::GlesRenderer, ImportDma, ImportMemWl},
        session::{libseat::LibSeatSession, Event as SessionEvent, Session},
        udev::{all_gpus, primary_gpu, UdevBackend, UdevEvent},
        SwapBuffersError,
    },
    desktop::{layer_map_for_output, utils::OutputPresentationFeedback},
    output::{Mode as WlMode, Output, PhysicalProperties, Scale},
    reexports::{
        calloop::{
            timer::{TimeoutAction, Timer},
            EventLoop, RegistrationToken,
        },
        drm::control::{self, connector, crtc, Device as _, ModeTypeFlags},
        input::{DeviceCapability, Libinput},
        rustix::fs::OFlags,
        wayland_protocols::wp::presentation_time::server::wp_presentation_feedback,
        wayland_server::backend::GlobalId,
    },
    utils::{DeviceFd, Monotonic, Time},
    wayland::{
        dmabuf::{DmabufFeedbackBuilder, DmabufGlobal},
        presentation::Refresh,
    },
};
use smithay_drm_extras::drm_scanner::{DrmScanEvent, DrmScanner};

use crate::{
    config, edid,
    monitors::{transform_from, MonitorRule},
    render::{output_elements, take_feedback, OutputElement},
    workspaces::OutputSerial,
    CalloopData, Shell,
};

/// Форматы кадра на мониторе: 8 бит на канал — их понимают все.
const COLOR_FORMATS: &[Fourcc] = &[Fourcc::Argb8888, Fourcc::Abgr8888];

type Allocator = GbmAllocator<DrmDeviceFd>;
type Exporter = GbmFramebufferExporter<DrmDeviceFd>;
type OutputManager = DrmOutputManager<Allocator, Exporter, OutputPresentationFeedback, DrmDeviceFd>;

/// Всё, что есть только в настоящей сессии.
pub struct UdevData {
    pub session: LibSeatSession,
    libinput: Libinput,
    /// узел отрисовки основной видеокарты (renderD128)
    primary_render: Option<DrmNode>,
    gpu: Option<Gpu>,
    dmabuf_global: Option<DmabufGlobal>,
    /// клавиатуры — для лампочек Caps Lock / Num Lock
    keyboards: Vec<smithay::reexports::input::Device>,
}

struct Gpu {
    /// узел card0, по которому udev сообщает о мониторах
    node: DrmNode,
    renderer: GlesRenderer,
    manager: OutputManager,
    scanner: DrmScanner,
    screens: HashMap<crtc::Handle, Screen>,
    /// подключены, но выключены в настройках
    disabled: HashMap<crtc::Handle, (connector::Info, Output)>,
    token: RegistrationToken,
}

/// Один монитор: его выход Wayland и кадры на него.
struct Screen {
    output: Output,
    connector: connector::Info,
    global: GlobalId,
    drm_output: DrmOutput<Allocator, Exporter, OutputPresentationFeedback, DrmDeviceFd>,
    /// экран выключен (DPMS): кадры не рисуются
    off: bool,
    /// кадр отдан монитору, ждём VBlank
    queued: bool,
    /// следующая попытка кадра уже назначена
    timer: Option<RegistrationToken>,
}

/// Родное разрешение, но самая высокая частота: «предпочтительный» режим в EDID
/// часто 60 Гц даже у игровых мониторов (200 Гц у разработчика).
fn best_mode(connector: &connector::Info) -> Option<control::Mode> {
    let modes = connector.modes();
    let native = modes.iter().find(|m| m.mode_type().contains(ModeTypeFlags::PREFERRED)).or_else(|| modes.first())?;
    modes.iter().filter(|m| m.size() == native.size()).max_by_key(|m| m.vrefresh()).copied()
}

/// Режим с этим разрешением и ближайшей частотой (59,94 и 60 — разные режимы);
/// частота 0 — самая высокая.
fn nearest_mode(connector: &connector::Info, (w, h, hz): (i32, i32, f64)) -> Option<control::Mode> {
    let same = connector.modes().iter().filter(|m| m.size() == (w as u16, h as u16));
    let rate = |m: &control::Mode| WlMode::from(*m).refresh as f64 / 1000.0;
    if hz <= 0.0 {
        return same.max_by_key(|m| WlMode::from(**m).refresh).copied();
    }
    same.min_by(|a, b| (rate(a) - hz).abs().total_cmp(&(rate(b) - hz).abs())).copied()
}

pub fn init(event_loop: &mut EventLoop<'static, CalloopData>, data: &mut CalloopData) -> Result<(), Box<dyn std::error::Error>> {
    let (session, notifier) = LibSeatSession::new().map_err(|e| format!("нет доступа к месту (libseat): {e}"))?;
    let seat = session.seat();
    tracing::info!(seat, "сессия получена");

    // основная видеокарта: та, что выводила картинку при загрузке
    let primary_render = primary_gpu(&seat)
        .ok()
        .flatten()
        .or_else(|| all_gpus(&seat).ok()?.into_iter().next())
        .and_then(|p| DrmNode::from_path(p).ok())
        .and_then(|n| n.node_with_type(NodeType::Render).and_then(Result::ok).or(Some(n)));
    tracing::info!(gpu = ?primary_render, "основная видеокарта");

    let udev = UdevBackend::new(&seat)?;

    let mut libinput = Libinput::new_with_udev::<LibinputSessionInterface<LibSeatSession>>(session.clone().into());
    libinput.udev_assign_seat(&seat).map_err(|()| "libinput не взял место")?;

    data.state.udev = Some(UdevData {
        session,
        libinput: libinput.clone(),
        primary_render,
        gpu: None,
        dmabuf_global: None,
        keyboards: Vec::new(),
    });

    let devices: Vec<_> = udev.device_list().map(|(id, path)| (id, path.to_path_buf())).collect();
    for (id, path) in devices {
        match DrmNode::from_dev_id(id) {
            Ok(node) => data.state.device_added(node, &path),
            Err(e) => tracing::warn!("{}: {e}", path.display()),
        }
    }
    if data.state.udev.as_ref().is_none_or(|u| u.gpu.is_none()) {
        return Err("ни одна видеокарта не запустилась".into());
    }

    let handle = event_loop.handle();
    handle.insert_source(udev, |event, _, data| match event {
        UdevEvent::Added { device_id, path } => {
            if let Ok(node) = DrmNode::from_dev_id(device_id) {
                data.state.device_added(node, &path);
            }
        }
        UdevEvent::Changed { device_id } => {
            if let Ok(node) = DrmNode::from_dev_id(device_id) {
                data.state.device_changed(node);
            }
        }
        UdevEvent::Removed { device_id } => {
            if let Ok(node) = DrmNode::from_dev_id(device_id) {
                data.state.device_removed(node);
            }
        }
    })?;

    handle.insert_source(LibinputInputBackend::new(libinput), |mut event, _, data| {
        data.state.input_device_event(&mut event);
        data.state.process_input_event(event);
    })?;

    // переключились на другую консоль и обратно
    handle.insert_source(notifier, |event, _, data| {
        let Some(udev) = data.state.udev.as_mut() else { return };
        match event {
            SessionEvent::PauseSession => {
                tracing::info!("консоль ушла — пауза");
                udev.libinput.suspend();
                if let Some(gpu) = udev.gpu.as_mut() {
                    gpu.manager.pause();
                }
            }
            SessionEvent::ActivateSession => {
                tracing::info!("консоль вернулась");
                if udev.libinput.resume().is_err() {
                    tracing::warn!("libinput не возобновился");
                }
                if let Some(gpu) = udev.gpu.as_mut() {
                    if let Err(e) = gpu.manager.activate(false) {
                        tracing::warn!("видеокарта не вернулась: {e}");
                    }
                    for screen in gpu.screens.values_mut() {
                        screen.queued = false;
                    }
                }
                data.state.schedule_all();
            }
        }
    })?;

    Ok(())
}

impl Shell {
    fn device_added(&mut self, node: DrmNode, path: &Path) {
        let Some(udev) = self.udev.as_mut() else { return };
        let render = node.node_with_type(NodeType::Render).and_then(Result::ok);
        if udev.gpu.is_some() || (udev.primary_render.is_some() && render != udev.primary_render && Some(node) != udev.primary_render) {
            tracing::info!("{}: не основная видеокарта — пока пропускаю", path.display());
            return;
        }
        match self.open_gpu(node, path) {
            Ok(()) => self.device_changed(node),
            Err(e) => tracing::error!("{}: {e}", path.display()),
        }
    }

    fn open_gpu(&mut self, node: DrmNode, path: &Path) -> Result<(), Box<dyn std::error::Error>> {
        let udev = self.udev.as_mut().expect("udev");
        let fd = udev.session.open(path, OFlags::RDWR | OFlags::CLOEXEC | OFlags::NOCTTY | OFlags::NONBLOCK)?;
        let fd = DrmDeviceFd::new(DeviceFd::from(fd));
        let (drm, notifier) = DrmDevice::new(fd.clone(), true)?;
        let gbm = GbmDevice::new(fd)?;

        let display = unsafe { EGLDisplay::new(gbm.clone())? };
        let egl_device = EGLDevice::device_for_display(&display)?;
        let render_node = egl_device.try_get_render_node().ok().flatten().unwrap_or(node);
        let context = EGLContext::new(&display)?;
        let renderer = unsafe { GlesRenderer::new(context)? };
        tracing::info!(?render_node, software = egl_device.is_software(), "отрисовка через OpenGL ES");

        let render_formats = renderer.egl_context().dmabuf_render_formats().clone();
        let allocator = GbmAllocator::new(gbm.clone(), GbmBufferFlags::RENDERING | GbmBufferFlags::SCANOUT);
        let exporter = GbmFramebufferExporter::new(gbm.clone(), Some(render_node));
        let manager = DrmOutputManager::new(drm, allocator, exporter, Some(gbm), COLOR_FORMATS.iter().copied(), render_formats);

        // программы рисуют на видеокарте и отдают кадры как dmabuf
        self.shm_state.update_formats(renderer.shm_formats());
        let feedback = DmabufFeedbackBuilder::new(render_node.dev_id(), renderer.dmabuf_formats()).build()?;
        let global = self.dmabuf_state.create_global_with_default_feedback::<Shell>(&self.display_handle, &feedback);

        let token = self.loop_handle.insert_source(notifier, move |event, metadata, data| match event {
            DrmEvent::VBlank(crtc) => data.state.frame_shown(node, crtc, metadata.take()),
            DrmEvent::Error(e) => tracing::error!("видеокарта: {e:?}"),
        })?;

        let udev = self.udev.as_mut().expect("udev");
        udev.dmabuf_global = Some(global);
        udev.gpu = Some(Gpu { node, renderer, manager, scanner: DrmScanner::new(), screens: HashMap::new(), disabled: HashMap::new(), token });
        Ok(())
    }

    /// udev: на видеокарте что-то поменялось — обычно подключили или
    /// отключили монитор.
    fn device_changed(&mut self, node: DrmNode) {
        let Some(gpu) = self.udev.as_mut().and_then(|u| u.gpu.as_mut()).filter(|g| g.node == node) else { return };
        let events = match gpu.scanner.scan_connectors(gpu.manager.device()) {
            Ok(r) => r,
            Err(e) => {
                tracing::warn!("мониторы не опросились: {e}");
                return;
            }
        };
        for event in events {
            match event {
                DrmScanEvent::Connected { connector, crtc: Some(crtc) } => self.connector_connected(connector, crtc),
                DrmScanEvent::Disconnected { crtc: Some(crtc), .. } => self.connector_disconnected(crtc),
                _ => {}
            }
        }
        // в настройках выключены все, что подключены сейчас: экран не должен остаться чёрным
        if self.space.outputs().count() == 0 {
            if let Some(output) = self.disabled_outputs().first() {
                tracing::warn!(name = output.name(), "других экранов нет — включаю выключенный");
                if let Err(e) = self.enable_output(output, None) {
                    tracing::warn!(name = output.name(), "{e}");
                }
            }
        }
        self.fixup_windows();
    }

    fn connector_connected(&mut self, connector: connector::Info, crtc: crtc::Handle) {
        let name = format!("{}-{}", connector.interface().as_str(), connector.interface_id());
        if connector.modes().is_empty() {
            tracing::warn!(name, "у монитора нет режимов");
            return;
        }
        let gpu = self.udev.as_mut().and_then(|u| u.gpu.as_mut()).expect("gpu");
        let info = edid_blob(gpu.manager.device(), connector.handle()).and_then(|b| edid::parse(&b));
        let (make, model, serial) = info.map(|i| (i.make, i.model, i.serial)).unwrap_or_else(|| ("Unknown".into(), "Unknown".into(), String::new()));
        let (w, h) = connector.size().unwrap_or((0, 0));
        let output = Output::new(
            name.clone(),
            PhysicalProperties { size: (w as i32, h as i32).into(), subpixel: connector.subpixel().into(), make, model },
        );
        output.user_data().insert_if_missing(|| OutputSerial(serial));
        for mode in connector.modes() {
            output.add_mode(WlMode::from(*mode));
        }

        let rule = self.rule_for(&output);
        if rule.as_ref().is_some_and(|r| r.disabled) {
            tracing::info!(name, "монитор выключен в настройках");
            let gpu = self.udev.as_mut().and_then(|u| u.gpu.as_mut()).expect("gpu");
            gpu.disabled.insert(crtc, (connector, output));
            return;
        }
        if let Err(e) = self.start_screen(connector, crtc, output, rule.as_ref()) {
            tracing::warn!(name, "{e}");
        }
    }

    /// Запустить монитор: при подключении и когда его включают снова.
    fn start_screen(&mut self, connector: connector::Info, crtc: crtc::Handle, output: Output, rule: Option<&MonitorRule>) -> Result<(), String> {
        let name = output.name();
        let mode = rule
            .and_then(|r| r.mode)
            .and_then(|want| nearest_mode(&connector, want))
            .or_else(|| best_mode(&connector))
            .ok_or("у монитора нет режимов")?;
        let x = self.space.outputs().filter_map(|o| self.space.output_geometry(o)).map(|g| g.loc.x + g.size.w).max().unwrap_or(0);
        let loc = rule.and_then(|r| r.position).unwrap_or((x, 0));
        let wl_mode = WlMode::from(mode);
        output.set_preferred(wl_mode);
        output.change_current_state(
            Some(wl_mode),
            rule.and_then(|r| r.transform).map(transform_from),
            rule.and_then(|r| r.scale).map(Scale::Fractional),
            Some(loc.into()),
        );
        let global = output.create_global::<Shell>(&self.display_handle);

        let gpu = self.udev.as_mut().and_then(|u| u.gpu.as_mut()).expect("gpu");
        // накладные плоскости пока не трогаем (на некоторых драйверах, NVIDIA,
        // с ними мерцает); курсор — на своей плоскости, если она есть
        let planes = gpu.manager.device().planes(&crtc).ok().map(|mut p| {
            p.overlay.clear();
            p
        });
        let drm_output = match gpu.manager.initialize_output::<_, OutputElement>(
            crtc,
            mode,
            &[connector.handle()],
            &output,
            planes,
            &mut gpu.renderer,
            &DrmOutputRenderElements::default(),
        ) {
            Ok(o) => o,
            Err(e) => {
                self.display_handle.remove_global::<Shell>(global);
                return Err(format!("монитор не запустился: {e}"));
            }
        };
        tracing::info!(name, size = ?wl_mode.size, refresh = wl_mode.refresh, ?loc, "монитор подключён");

        gpu.screens.insert(crtc, Screen { off: false, output: output.clone(), connector, global, drm_output, queued: false, timer: None });
        self.space.map_output(&output, loc);
        self.output_added(&output);
        layer_map_for_output(&output).arrange();

        // первый монитор — мышь в его центр
        if self.space.outputs().count() == 1 {
            if let (Some(pointer), Some(geo)) = (self.seat.get_pointer(), self.space.output_geometry(&output)) {
                pointer.set_location(geo.to_f64().loc + geo.to_f64().size.downscale(2.0));
            }
        }
        self.schedule_render(crtc, Duration::ZERO);
        Ok(())
    }

    fn stop_screen(&mut self, screen: Screen) {
        if let Some(t) = screen.timer {
            self.loop_handle.remove(t);
        }
        self.space.unmap_output(&screen.output);
        self.output_removed(&screen.output);
        self.display_handle.remove_global::<Shell>(screen.global);
    }

    fn connector_disconnected(&mut self, crtc: crtc::Handle) {
        let Some(gpu) = self.udev.as_mut().and_then(|u| u.gpu.as_mut()) else { return };
        gpu.disabled.remove(&crtc);
        let Some(screen) = gpu.screens.remove(&crtc) else { return };
        tracing::info!(name = screen.output.name(), "монитор отключён");
        self.stop_screen(screen);
    }

    /// Выключенные в настройках мониторы: подключены, но не работают.
    pub fn disabled_outputs(&self) -> Vec<Output> {
        let gpu = self.udev.as_ref().and_then(|u| u.gpu.as_ref());
        gpu.map(|g| g.disabled.values().map(|(_, o)| o.clone()).collect()).unwrap_or_default()
    }

    pub fn disable_output(&mut self, output: &Output) -> Result<(), String> {
        let gpu = self.udev.as_mut().and_then(|u| u.gpu.as_mut()).ok_or("окно отладки не выключается")?;
        let crtc = gpu.screens.iter().find(|(_, s)| s.output == *output).map(|(c, _)| *c).ok_or("монитор уже выключен")?;
        let screen = gpu.screens.remove(&crtc).expect("монитор найден выше");
        if let Err(e) = screen.drm_output.with_compositor(|c| c.surface().clear()) {
            tracing::warn!(name = output.name(), "монитор не погас: {e}");
        }
        tracing::info!(name = output.name(), "монитор выключен");
        gpu.disabled.insert(crtc, (screen.connector.clone(), output.clone()));
        self.stop_screen(screen);
        Ok(())
    }

    pub fn enable_output(&mut self, output: &Output, rule: Option<&MonitorRule>) -> Result<(), String> {
        let gpu = self.udev.as_mut().and_then(|u| u.gpu.as_mut()).ok_or("нет видеокарты")?;
        let crtc = gpu.disabled.iter().find(|(_, (_, o))| o == output).map(|(c, _)| *c).ok_or("монитор уже включён")?;
        let (connector, output) = gpu.disabled.remove(&crtc).expect("монитор найден выше");
        self.start_screen(connector, crtc, output, rule)
    }

    /// Новый режим монитора. None — менять нечего: он уже такой или это окно отладки.
    pub fn set_output_mode(&mut self, output: &Output, want: (i32, i32, f64)) -> Result<Option<WlMode>, String> {
        let Some(gpu) = self.udev.as_mut().and_then(|u| u.gpu.as_mut()) else { return Ok(None) };
        let Gpu { renderer, screens, .. } = gpu;
        let screen = screens.values_mut().find(|s| s.output == *output).ok_or("монитор выключен")?;
        let mode = nearest_mode(&screen.connector, want).ok_or_else(|| format!("нет режима {}x{}", want.0, want.1))?;
        let wl_mode = WlMode::from(mode);
        if output.current_mode() == Some(wl_mode) {
            return Ok(None);
        }
        screen
            .drm_output
            .use_mode(mode, renderer, &DrmOutputRenderElements::<_, OutputElement>::default())
            .map_err(|e| format!("режим не включился: {e}"))?;
        Ok(Some(wl_mode))
    }

    fn device_removed(&mut self, node: DrmNode) {
        let crtcs: Vec<_> = match self.udev.as_ref().and_then(|u| u.gpu.as_ref()).filter(|g| g.node == node) {
            Some(gpu) => gpu.screens.keys().copied().collect(),
            None => return,
        };
        for crtc in crtcs {
            self.connector_disconnected(crtc);
        }
        if let Some(gpu) = self.udev.as_mut().and_then(|u| u.gpu.take()) {
            self.loop_handle.remove(gpu.token);
        }
        if let Some(global) = self.udev.as_mut().and_then(|u| u.dmabuf_global.take()) {
            self.dmabuf_state.destroy_global::<Shell>(&self.display_handle, global);
        }
        tracing::warn!("основная видеокарта пропала");
        self.fixup_windows();
    }

    /// VBlank: монитор показал наш кадр. Программам — «рисуйте дальше»,
    /// себе — следующий кадр.
    fn frame_shown(&mut self, node: DrmNode, crtc: crtc::Handle, metadata: Option<DrmEventMetadata>) {
        let now = self.clock.now();
        let Some(gpu) = self.udev.as_mut().and_then(|u| u.gpu.as_mut()).filter(|g| g.node == node) else { return };
        let Some(screen) = gpu.screens.get_mut(&crtc) else { return };
        screen.queued = false;
        match screen.drm_output.frame_submitted() {
            Ok(Some(mut feedback)) => {
                let refresh = screen.output.current_mode().map_or(Refresh::Unknown, |m| {
                    Refresh::fixed(Duration::from_secs_f64(1000.0 / m.refresh.max(1) as f64))
                });
                // время от самой видеокарты, если оно по тем же часам
                let hw = metadata.as_ref().and_then(|m| match m.time {
                    DrmEventTime::Monotonic(t) if !t.is_zero() => Some((t, m.sequence as u64)),
                    _ => None,
                });
                let vsync = wp_presentation_feedback::Kind::Vsync;
                match hw {
                    Some((t, seq)) => feedback.presented(
                        Time::<Monotonic>::from(t),
                        refresh,
                        seq,
                        vsync | wp_presentation_feedback::Kind::HwClock | wp_presentation_feedback::Kind::HwCompletion,
                    ),
                    None => feedback.presented(now, refresh, 0, vsync),
                }
            }
            Ok(None) => {}
            Err(e) => tracing::warn!("кадр: {e:?}"),
        }
        self.schedule_render(crtc, Duration::ZERO);
    }

    /// Назначить кадр монитора через delay (если ещё не назначен и монитор
    /// не ждёт показа прошлого).
    fn schedule_render(&mut self, crtc: crtc::Handle, delay: Duration) {
        let Some(screen) = self.udev.as_mut().and_then(|u| u.gpu.as_mut()).and_then(|g| g.screens.get_mut(&crtc)) else { return };
        if screen.timer.is_some() || screen.queued {
            return;
        }
        let token = self.loop_handle.insert_source(Timer::from_duration(delay), move |_, _, data| {
            if let Some(s) = data.state.udev.as_mut().and_then(|u| u.gpu.as_mut()).and_then(|g| g.screens.get_mut(&crtc)) {
                s.timer = None;
            }
            data.state.render_screen(crtc);
            TimeoutAction::Drop
        });
        match token {
            Ok(t) => screen.timer = Some(t),
            Err(e) => tracing::error!("таймер кадра: {e}"),
        }
    }

    pub fn schedule_all(&mut self) {
        let crtcs: Vec<_> = self.udev.as_ref().and_then(|u| u.gpu.as_ref()).map(|g| g.screens.keys().copied().collect()).unwrap_or_default();
        for crtc in crtcs {
            self.schedule_render(crtc, Duration::ZERO);
        }
    }

    fn render_screen(&mut self, crtc: crtc::Handle) {
        // состояние оболочки нужно и для элементов кадра — udev временно отдельно
        let Some(mut udev) = self.udev.take() else { return };
        let active = udev.session.is_active();
        let result = udev.gpu.as_mut().and_then(|gpu| {
            let screen = gpu.screens.get_mut(&crtc)?;
            let output = screen.output.clone();
            let shown = active && !screen.off;
            let drawn = shown.then(|| self.draw(&mut gpu.renderer, screen));
            if shown {
                self.run_copies(&mut gpu.renderer, &output);
            }
            Some((output, drawn))
        });
        self.udev = Some(udev);

        let Some((output, drawn)) = result else { return };
        if matches!(drawn, Some(Ok(_))) {
            self.lock_frame_drawn(&output);
        }
        let frame = output.current_mode().map(|m| Duration::from_secs_f64(1000.0 / m.refresh.max(1) as f64)).unwrap_or(Duration::from_millis(16));
        match drawn {
            // на монитор ушёл новый кадр: дальше — по VBlank
            Some(Ok(true)) => {}
            // ничего не изменилось — проверим снова через кадр
            Some(Ok(false)) => self.schedule_render(crtc, frame),
            Some(Err(e)) => {
                tracing::warn!("кадр не отрисован: {e:?}");
                let inactive = matches!(&e, SwapBuffersError::TemporaryFailure(err)
                    if matches!(err.downcast_ref::<DrmError>(), Some(DrmError::DeviceInactive)));
                if !inactive {
                    self.schedule_render(crtc, frame);
                }
            }
            // консоль не наша — вернёмся по ActivateSession
            None => {}
        }

        // программам на этом мониторе — «можно рисовать следующий кадр»
        self.send_frames(&output);
    }

    /// Отрисовать кадр монитора; true — кадр новый и поставлен на показ.
    fn draw(&mut self, renderer: &mut GlesRenderer, screen: &mut Screen) -> Result<bool, SwapBuffersError> {
        let elements = output_elements(renderer, self, &screen.output, true);
        let result = screen
            .drm_output
            .render_frame(renderer, &elements, config::BACKGROUND, FrameFlags::DEFAULT)
            .map_err(|e| match e {
                smithay::backend::drm::compositor::RenderFrameError::PrepareFrame(e) => SwapBuffersError::from(e),
                smithay::backend::drm::compositor::RenderFrameError::RenderFrame(e) => {
                    SwapBuffersError::ContextLost(Box::new(e))
                }
            })?;
        if result.is_empty {
            return Ok(false);
        }
        let feedback = take_feedback(self, &screen.output, &result.states);
        screen.drm_output.queue_frame(feedback).map_err(SwapBuffersError::from)?;
        screen.queued = true;
        Ok(true)
    }

    /// Новые и пропавшие устройства ввода: настройки мыши и тачпада из Delta.
    fn input_device_event(&mut self, event: &mut InputEvent<LibinputInputBackend>) {
        let Some(udev) = self.udev.as_mut() else { return };
        match event {
            InputEvent::DeviceAdded { device } => {
                let input = &self.settings.input;
                if device.config_accel_is_available() {
                    let _ = device.config_accel_set_speed(input.sensitivity.clamp(-1.0, 1.0));
                }
                // тачпад: касание — щелчок, «естественная» прокрутка (как в Delta)
                if device.config_tap_finger_count() > 0 {
                    let _ = device.config_tap_set_enabled(input.tap_to_click);
                    if device.config_scroll_has_natural_scroll() {
                        let _ = device.config_scroll_set_natural_scroll_enabled(input.natural_scroll);
                    }
                }
                if device.has_capability(DeviceCapability::Keyboard) {
                    if let Some(kb) = self.seat.get_keyboard() {
                        device.led_update(kb.led_state().into());
                    }
                    udev.keyboards.push(device.clone());
                }
                tracing::info!(name = device.name(), "устройство ввода");
            }
            InputEvent::DeviceRemoved { device } => udev.keyboards.retain(|d| d != device),
            _ => {}
        }
    }

    /// Выключить или включить экраны (простой, «Выключить экран»).
    pub fn set_dpms(&mut self, on: bool) {
        let Some(gpu) = self.udev.as_mut().and_then(|u| u.gpu.as_mut()) else { return };
        let mut wake = Vec::new();
        for (crtc, screen) in gpu.screens.iter_mut() {
            if screen.off == !on {
                continue;
            }
            screen.off = !on;
            if on {
                wake.push(*crtc);
            } else if let Err(e) = screen.drm_output.with_compositor(|c| c.clear()) {
                tracing::warn!("экран не выключился: {e:?}");
            }
        }
        for crtc in wake {
            self.schedule_render(crtc, Duration::ZERO);
        }
    }

    /// Выполнить с рендерером вне кадра (снимок закрывающегося окна).
    pub fn with_renderer<T>(&mut self, f: impl FnOnce(&mut Self, &mut GlesRenderer) -> T) -> Option<T> {
        if let Some(mut udev) = self.udev.take() {
            let result = udev.gpu.as_mut().map(|g| f(self, &mut g.renderer));
            self.udev = Some(udev);
            return result;
        }
        let mut backend = self.winit.take()?;
        let result = f(self, backend.renderer());
        self.winit = Some(backend);
        Some(result)
    }

    /// Лампочки Caps Lock и т. п. на всех клавиатурах.
    pub fn update_leds(&mut self, leds: smithay::input::keyboard::LedState) {
        if let Some(udev) = self.udev.as_mut() {
            for kb in udev.keyboards.iter_mut() {
                kb.led_update(leds.into());
            }
        }
    }

    /// Ctrl+Alt+F1…F12.
    pub fn change_vt(&mut self, vt: i32) {
        if let Some(udev) = self.udev.as_mut() {
            if let Err(e) = udev.session.change_vt(vt) {
                tracing::warn!(vt, "консоль не переключилась: {e}");
            }
        }
    }

    /// Программа прислала кадр как dmabuf: сможем ли мы его показать.
    pub fn import_dmabuf(&mut self, dmabuf: &smithay::backend::allocator::dmabuf::Dmabuf) -> bool {
        if let Some(backend) = self.winit.as_mut() {
            return backend.renderer().import_dmabuf(dmabuf, None).is_ok();
        }
        self.udev
            .as_mut()
            .and_then(|u| u.gpu.as_mut())
            .is_some_and(|g| g.renderer.import_dmabuf(dmabuf, None).is_ok())
    }
}

/// EDID монитора — свойство «EDID» коннектора.
fn edid_blob(device: &DrmDevice, conn: connector::Handle) -> Option<Vec<u8>> {
    let props = device.get_properties(conn).ok()?;
    let (handles, values) = props.as_props_and_values();
    handles.iter().zip(values).find_map(|(&h, &v)| {
        let info = device.get_property(h).ok()?;
        (info.name().to_str() == Ok("EDID") && v != 0).then(|| device.get_property_blob(v).ok()).flatten()
    })
}
