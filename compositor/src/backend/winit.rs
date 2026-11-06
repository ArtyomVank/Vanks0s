use smithay::{
    backend::{
        drm::DrmDeviceFd,
        egl::EGLDevice,
        renderer::{damage::OutputDamageTracker, gles::GlesRenderer, ImportDma},
        winit::{self, WinitEvent},
    },
    input::pointer::{CursorIcon, CursorImageStatus},
    output::{Mode, Output, PhysicalProperties, Subpixel},
    reexports::{
        calloop::{
            timer::{TimeoutAction, Timer},
            EventLoop,
        },
        wayland_protocols::wp::presentation_time::server::wp_presentation_feedback,
    },
    utils::{DeviceFd, Rectangle, Scale, Transform},
    wayland::{
        dmabuf::DmabufFeedbackBuilder,
        drm_syncobj::{supports_syncobj_eventfd, DrmSyncobjState},
        presentation::Refresh,
    },
};

use crate::{config, hdr::HdrPass, render::{output_elements, take_feedback}, CalloopData, Shell};

/// Окно отладки: один выход размером с окно, ввод — из него же.
pub fn init(event_loop: &mut EventLoop<CalloopData>, data: &mut CalloopData) -> Result<(), Box<dyn std::error::Error>> {
    let (mut backend, winit) = winit::init::<GlesRenderer>()?;
    backend.window().set_title("композитор Delta (отладка)");

    // программы рисуют на видеокарте и отдают кадры как dmabuf — как в настоящей
    // сессии. Без адреса видеокарты Quickshell ушёл бы на медленный SHM
    let formats = backend.renderer().dmabuf_formats();
    let node = EGLDevice::device_for_display(backend.renderer().egl_context().display())
        .and_then(|device| device.try_get_render_node());
    // явная синхронизация кадров, как в настоящей сессии
    if let Ok(Some(path)) = node.as_ref().map(|n| n.as_ref().and_then(|n| n.dev_path())) {
        if let Ok(file) = std::fs::File::options().read(true).write(true).open(path) {
            let fd = DrmDeviceFd::new(DeviceFd::from(std::os::fd::OwnedFd::from(file)));
            if supports_syncobj_eventfd(&fd) {
                data.state.syncobj_state = Some(DrmSyncobjState::new::<Shell>(&data.display_handle, fd));
                tracing::info!("явная синхронизация кадров включена");
            }
        }
    }
    let feedback = match node {
        Ok(Some(node)) => DmabufFeedbackBuilder::new(node.dev_id(), formats.clone()).build().ok(),
        _ => None,
    };
    match feedback {
        Some(feedback) => {
            data.state.dmabuf_state.create_global_with_default_feedback::<Shell>(&data.display_handle, &feedback);
        }
        None => {
            tracing::warn!("видеокарта окна не определилась: dmabuf без адреса устройства");
            data.state.dmabuf_state.create_global::<Shell>(&data.display_handle, formats);
        }
    }

    let mode = Mode { size: backend.window_size(), refresh: 60_000 };
    let output = Output::new(
        "winit".to_string(),
        PhysicalProperties {
            size: (0, 0).into(),
            subpixel: Subpixel::Unknown,
            make: "Delta".into(),
            model: "Окно отладки".into(),
        },
    );
    let _global = output.create_global::<Shell>(&data.display_handle);
    // кадр winit перевёрнут по вертикали относительно GL
    output.change_current_state(Some(mode), Some(Transform::Flipped180), None, Some((0, 0).into()));
    output.set_preferred(mode);
    data.state.space.map_output(&output, (0, 0));
    data.state.output_added(&output);
    data.state.winit = Some(backend);
    data.state.reload_monitors();

    // Запись видео из скрытого окна: сессия вокруг просит кадры редко, поэтому
    // снимки экрана и кадры программ идут по своему таймеру (DELTA_CAPTURE_FPS=60).
    let capture_fps = std::env::var("DELTA_CAPTURE_FPS").ok().and_then(|v| v.parse::<u32>().ok()).filter(|f| *f > 0);
    if let Some(fps) = capture_fps {
        let period = std::time::Duration::from_secs_f64(1.0 / f64::from(fps));
        let capture_output = output.clone();
        event_loop.handle().insert_source(Timer::from_duration(period), move |_, _, data| {
            let state = &mut data.state;
            if let Some(mut backend) = state.winit.take() {
                state.lock_frame_drawn(&capture_output);
                state.run_copies(backend.renderer(), &capture_output);
                state.send_frames(&capture_output);
                state.winit = Some(backend);
                state.space.refresh();
                state.popups.cleanup();
                let _ = data.display_handle.flush_clients();
            }
            TimeoutAction::ToDuration(period)
        })?;
    }

    let mut damage_tracker = OutputDamageTracker::from_output(&output);
    // проверка HDR без монитора: DELTA_NESTED_HDR=1, и раздел «Экран» включает
    // проход PQ в этом окне (монитор вокруг покажет его блёклым, это нормально)
    let mut hdr_pass: Option<HdrPass> = None;
    // курсор рисует сессия вокруг; мы только меняем его фигуру, когда просит программа
    let mut shown_cursor: Option<CursorIcon> = Some(CursorIcon::Default);

    event_loop.handle().insert_source(winit, move |event, _, data| {
        let state = &mut data.state;
        match event {
            WinitEvent::Resized { size, .. } => {
                output.change_current_state(Some(Mode { size, refresh: 60_000 }), None, None, None);
                state.resize_lock_surfaces();
            }
            WinitEvent::Input(event) => state.process_input_event(event),
            WinitEvent::Redraw => {
                // состояние оболочки нужно и для элементов кадра — окно временно отдельно
                let Some(mut backend) = state.winit.take() else { return };
                let want = match &state.cursor_status {
                    CursorImageStatus::Named(icon) => Some(*icon),
                    CursorImageStatus::Hidden => None,
                    // своя картинка программы — пока обычная стрелка
                    CursorImageStatus::Surface(_) => Some(CursorIcon::Default),
                };
                if want != shown_cursor {
                    let window = backend.window();
                    window.set_cursor_visible(want.is_some());
                    if let Some(icon) = want {
                        window.set_cursor(icon);
                    }
                    shown_cursor = want;
                }

                let size = backend.window_size();
                let damage = Rectangle::from_size(size);
                let mut feedback = None;
                // до bind: снимки окон для анимаций рисуются в свои текстуры
                let elements = output_elements(backend.renderer(), state, &output, false);
                let mut hdr_states = None;
                match crate::hdr::output_white(&output) {
                    Some(white) => {
                        if !hdr_pass.as_ref().is_some_and(|p| p.fits(size, Scale::from(1.0))) {
                            hdr_pass = HdrPass::new(backend.renderer(), size, Scale::from(1.0), white)
                                .map_err(|e| tracing::warn!("{e}"))
                                .ok();
                        }
                        if let Some(pass) = hdr_pass.as_mut() {
                            pass.set_white(white);
                            pass.set_saturation(crate::hdr::output_saturation(&output));
                            hdr_states = pass.render(backend.renderer(), &elements).map_err(|e| tracing::warn!("{e}")).ok();
                        }
                    }
                    None => hdr_pass = None,
                }
                let bound = match backend.bind() {
                    Ok((renderer, mut framebuffer)) => {
                        let drawn = match (&hdr_pass, hdr_states) {
                            (Some(pass), Some(states)) => damage_tracker
                                .render_output(renderer, &mut framebuffer, 0, &[pass.frame()], config::BACKGROUND)
                                .map(|_| states),
                            _ => damage_tracker
                                .render_output(renderer, &mut framebuffer, 0, &elements, config::BACKGROUND)
                                .map(|result| result.states),
                        };
                        match drawn {
                            Ok(states) => feedback = Some(take_feedback(state, &output, &states)),
                            Err(e) => tracing::warn!("ошибка отрисовки: {e:?}"),
                        }
                        true
                    }
                    Err(e) => {
                        tracing::warn!("кадр пропущен: {e}");
                        false
                    }
                };
                if bound {
                    if let Err(e) = backend.submit(Some(&[damage])) {
                        tracing::warn!("кадр не показан: {e}");
                    }
                    // когда окно вокруг покажет кадр, нам не сообщают: считаем, что сейчас
                    if let Some(mut feedback) = feedback.take() {
                        feedback.presented(state.clock.now(), Refresh::Unknown, 0, wp_presentation_feedback::Kind::empty());
                    }
                    state.lock_frame_drawn(&output);
                    state.run_copies(backend.renderer(), &output);
                    // программам — «рисуйте следующий кадр»
                    state.send_frames(&output);
                }
                backend.window().request_redraw();
                state.winit = Some(backend);

                state.space.refresh();
                state.popups.cleanup();
                let _ = data.display_handle.flush_clients();
            }
            WinitEvent::CloseRequested => state.loop_signal.stop(),
            _ => (),
        };
    })?;

    Ok(())
}
