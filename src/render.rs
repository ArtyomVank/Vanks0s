//! Что рисуется на выходе: окна и курсор поверх. Общее для настоящей сессии;
//! в окне отладки курсор рисует сессия вокруг.

use std::sync::Mutex;

use smithay::{
    backend::renderer::{
        element::{
            memory::MemoryRenderBufferRenderElement,
            surface::{render_elements_from_surface_tree, WaylandSurfaceRenderElement},
            Kind,
        },
        gles::GlesRenderer,
    },
    desktop::space::{space_render_elements, SpaceRenderElements},
    input::pointer::{CursorImageAttributes, CursorImageStatus},
    output::Output,
    render_elements,
    utils::{IsAlive, Point, Scale},
    wayland::compositor,
};

use crate::Shell;

type R = GlesRenderer;

render_elements! {
    pub OutputElement<=GlesRenderer>;
    Space = SpaceRenderElements<R, WaylandSurfaceRenderElement<R>>,
    Surface = WaylandSurfaceRenderElement<R>,
    Cursor = MemoryRenderBufferRenderElement<R>,
}

/// Элементы кадра выхода — спереди назад: курсор, затем окна или, при
/// блокировке, только замок. Курсор в окне отладки рисует сессия вокруг.
pub fn output_elements(renderer: &mut R, shell: &mut Shell, output: &Output, draw_cursor: bool) -> Vec<OutputElement> {
    let mut elements = Vec::new();
    let Some(geo) = shell.space.output_geometry(output) else { return elements };
    let scale = Scale::from(output.current_scale().fractional_scale());

    let pointer = shell.seat.get_pointer().map(|p| p.current_location()).unwrap_or_default();
    if draw_cursor && geo.to_f64().contains(pointer) {
        let at = (pointer - geo.loc.to_f64()).to_physical(scale);

        // картинка курсора от программы, которой уже нет, — обратно к стрелке
        if let CursorImageStatus::Surface(s) = &shell.cursor_status {
            if !s.alive() {
                shell.cursor_status = CursorImageStatus::default_named();
            }
        }
        match shell.cursor_status.clone() {
            CursorImageStatus::Hidden => {}
            CursorImageStatus::Named(icon) => {
                let (buffer, hotspot) = shell.cursor.image(icon, shell.start_time.elapsed());
                let loc = at - hotspot.to_f64();
                if let Ok(e) = MemoryRenderBufferRenderElement::from_buffer(renderer, loc, &buffer, None, None, None, Kind::Cursor) {
                    elements.push(OutputElement::Cursor(e));
                }
            }
            CursorImageStatus::Surface(surface) => {
                let hotspot = compositor::with_states(&surface, |states| {
                    states
                        .data_map
                        .get::<Mutex<CursorImageAttributes>>()
                        .map(|a| a.lock().unwrap().hotspot)
                        .unwrap_or_default()
                });
                let loc: Point<i32, _> = (at - hotspot.to_f64().to_physical(scale)).to_i32_round();
                elements.extend(
                    render_elements_from_surface_tree(renderer, &surface, loc, scale, 1.0, Kind::Cursor)
                        .into_iter()
                        .map(OutputElement::Surface),
                );
            }
        }
    }

    if shell.is_locked() {
        if let Some(lock) = shell.lock_surface(output) {
            let surface = lock.wl_surface().clone();
            elements.extend(
                render_elements_from_surface_tree(renderer, &surface, (0, 0), scale, 1.0, Kind::Unspecified)
                    .into_iter()
                    .map(OutputElement::Surface),
            );
        }
        return elements;
    }

    // не Space::render_elements_for_output: в Smithay 0.7 она не учитывает место
    // слоя и рисует сверху экрана всё, что прижато к другому краю (нижний док)
    match space_render_elements(renderer, [&shell.space], output, 1.0) {
        Ok(space) => elements.extend(space.into_iter().map(OutputElement::Space)),
        Err(e) => tracing::warn!("окна для {}: {e:?}", output.name()),
    }
    elements
}
