use smithay::{
    backend::{
        egl::EGLDevice,
        renderer::{damage::OutputDamageTracker, gles::GlesRenderer, ImportDma},
        winit::{self, WinitEvent},
    },
    input::pointer::{CursorIcon, CursorImageStatus},
    output::{Mode, Output, PhysicalProperties, Subpixel},
    reexports::calloop::EventLoop,
    utils::{Rectangle, Transform},
    wayland::dmabuf::DmabufFeedbackBuilder,
};

use crate::{config, render::output_elements, CalloopData, Shell};

/// Окно отладки: один выход размером с окно, ввод — из него же.
pub fn init(event_loop: &mut EventLoop<CalloopData>, data: &mut CalloopData) -> Result<(), Box<dyn std::error::Error>> {
    let (mut backend, winit) = winit::init::<GlesRenderer>()?;
    backend.window().set_title("Vanks Shell (отладка)");

    // программы рисуют на видеокарте и отдают кадры как dmabuf — как в настоящей
    // сессии. Без адреса видеокарты Quickshell ушёл бы на медленный SHM
    let formats = backend.renderer().dmabuf_formats();
    let node = EGLDevice::device_for_display(backend.renderer().egl_context().display())
        .and_then(|device| device.try_get_render_node());
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
            make: "Vanks".into(),
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

    let mut damage_tracker = OutputDamageTracker::from_output(&output);
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
                let bound = match backend.bind() {
                    Ok((renderer, mut framebuffer)) => {
                        let elements = output_elements(renderer, state, &output, false);
                        if let Err(e) = damage_tracker.render_output(renderer, &mut framebuffer, 0, &elements, config::BACKGROUND) {
                            tracing::warn!("ошибка отрисовки: {e:?}");
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
                    state.lock_frame_drawn(&output);
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
