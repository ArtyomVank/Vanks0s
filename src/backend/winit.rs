use std::time::Duration;

use smithay::{
    backend::{
        renderer::{damage::OutputDamageTracker, element::surface::WaylandSurfaceRenderElement, gles::GlesRenderer},
        winit::{self, WinitEvent},
    },
    input::pointer::{CursorIcon, CursorImageStatus},
    output::{Mode, Output, PhysicalProperties, Subpixel},
    reexports::calloop::EventLoop,
    utils::{Rectangle, Transform},
};

use crate::{config, CalloopData, Shell};

/// Окно отладки: один выход размером с окно, ввод — из него же.
pub fn init(event_loop: &mut EventLoop<CalloopData>, data: &mut CalloopData) -> Result<(), Box<dyn std::error::Error>> {
    let (mut backend, winit) = winit::init()?;
    backend.window().set_title("Vanks Shell (отладка)");

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

    let mut damage_tracker = OutputDamageTracker::from_output(&output);
    // курсор рисует сессия вокруг; мы только меняем его фигуру, когда просит программа
    let mut shown_cursor: Option<CursorIcon> = Some(CursorIcon::Default);

    event_loop.handle().insert_source(winit, move |event, _, data| {
        let state = &mut data.state;
        match event {
            WinitEvent::Resized { size, .. } => {
                output.change_current_state(Some(Mode { size, refresh: 60_000 }), None, None, None);
            }
            WinitEvent::Input(event) => state.process_input_event(event),
            WinitEvent::Redraw => {
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
                {
                    let (renderer, mut framebuffer) = match backend.bind() {
                        Ok(b) => b,
                        Err(e) => {
                            tracing::warn!("кадр пропущен: {e}");
                            return;
                        }
                    };
                    if let Err(e) = smithay::desktop::space::render_output::<_, WaylandSurfaceRenderElement<GlesRenderer>, _, _>(
                        &output,
                        renderer,
                        &mut framebuffer,
                        1.0,
                        0,
                        [&state.space],
                        &[],
                        &mut damage_tracker,
                        config::BACKGROUND,
                    ) {
                        tracing::warn!("ошибка отрисовки: {e:?}");
                    }
                }
                if let Err(e) = backend.submit(Some(&[damage])) {
                    tracing::warn!("кадр не показан: {e}");
                }

                // программам — «рисуйте следующий кадр»
                state.space.elements().for_each(|window| {
                    window.send_frame(&output, state.start_time.elapsed(), Some(Duration::ZERO), |_, _| Some(output.clone()))
                });
                state.space.refresh();
                state.popups.cleanup();
                let _ = data.display_handle.flush_clients();
                backend.window().request_redraw();
            }
            WinitEvent::CloseRequested => state.loop_signal.stop(),
            _ => (),
        };
    })?;

    Ok(())
}
