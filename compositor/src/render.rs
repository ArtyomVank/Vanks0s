//! Что рисуется на выходе: обои и панели, окна с эффектами, курсор. Общее для
//! настоящей сессии и окна отладки (там курсор рисует сессия вокруг).

use std::{
    collections::hash_map::DefaultHasher,
    hash::{Hash, Hasher},
    rc::Rc,
    sync::Mutex,
    time::Instant,
};

use smithay::wayland::seat::WaylandFocus;
use smithay::{
    backend::{
        allocator::Fourcc,
        renderer::{
            damage::OutputDamageTracker,
            element::{
                memory::MemoryRenderBufferRenderElement,
                surface::{render_elements_from_surface_tree, WaylandSurfaceRenderElement},
                AsRenderElements, Element, Id, Kind, RenderElementStates,
            },
            gles::{element::PixelShaderElement, GlesRenderer, GlesTexture, Uniform},
            utils::CommitCounter,
            Bind, Offscreen,
        },
    },
    desktop::{
        layer_map_for_output,
        utils::{surface_presentation_feedback_flags_from_states, OutputPresentationFeedback},
        LayerSurface, PopupManager, Window,
    },
    input::pointer::{CursorImageAttributes, CursorImageStatus},
    output::Output,
    reexports::wayland_server::Resource,
    render_elements,
    utils::{IsAlive, Logical, Physical, Point, Rectangle, Scale, Size, Transform},
    wayland::{compositor, shell::wlr_layer::Layer},
};

use crate::{
    fx::{
        self,
        elements::{Backdrop, ClipSurface, GlassSurface, JellyParams, Mesh, MeshElement, RevealParams},
        Closing, Glass, Open, Params, Programs, Spring, WsAnim,
    },
    workspaces::{data, Mode},
    Shell,
};

type R = GlesRenderer;
type Surface = WaylandSurfaceRenderElement<R>;

render_elements! {
    pub OutputElement<=GlesRenderer>;
    Surface = Surface,
    Clip = ClipSurface,
    Glass = GlassSurface,
    Decor = PixelShaderElement,
    Backdrop = Backdrop,
    Mesh = MeshElement,
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

    let programs = shell.fx_programs(renderer);
    let params = Params::from_settings(&shell.settings);
    let now = Instant::now();
    shell.update_scene();

    let area = geo;
    let fullscreen = shell
        .space
        .elements()
        .any(|w| data(w).mode == Mode::Fullscreen && shell.space.element_location(w).is_some_and(|l| area.contains(l)));

    // слои поверх окон; окно на весь экран закрывает верхний слой (как у Hyprland)
    push_layers(renderer, shell, output, Layer::Overlay, &programs, &params, &mut elements);
    if !fullscreen {
        push_layers(renderer, shell, output, Layer::Top, &programs, &params, &mut elements);
    }

    if let Some(programs) = &programs {
        push_closing(shell, area, scale, now, programs, &params, &mut elements);
    }

    // стол сменился: новые окна въезжают, старые уезжают
    let width = area.size.w as f32;
    let name = output.name();
    let ws_p = shell.fx.ws.get(&name).map(|a| {
        let spring = params.motion.ws;
        let x = now.saturating_duration_since(a.start).as_secs_f32() / params.global_time;
        (spring.value(x), x >= spring.settle(), a.dir)
    });
    let ws_offset = |w: &Window, p: Option<(f32, bool, f32)>| -> i32 {
        match p {
            Some((v, _, dir)) if !data(w).pinned => ((1.0 - v) * dir * width).round() as i32,
            _ => 0,
        }
    };

    let windows: Vec<Window> = shell.space.elements().rev().cloned().collect();
    let focused = shell.focused_window();
    for window in &windows {
        let loc = shell.space.element_location(window).unwrap_or_default();
        let offset = ws_offset(window, ws_p);
        push_window(
            renderer, shell, window, loc + Point::from((offset, 0)), area, scale, focused.as_ref() == Some(window), now,
            &programs, &params, &mut elements,
        );
    }
    if let Some((v, done, dir)) = ws_p {
        let old = shell.fx.ws.get(&name).map(|a| a.old.clone()).unwrap_or_default();
        for window in old.iter().rev() {
            if windows.contains(window) || !window.alive() {
                continue;
            }
            let loc = data(window).loc + Point::from(((-v * dir * width).round() as i32, 0));
            push_window(renderer, shell, window, loc, area, scale, false, now, &programs, &params, &mut elements);
        }
        if done {
            shell.fx.ws.remove(&name);
        }
    }

    push_layers(renderer, shell, output, Layer::Bottom, &programs, &params, &mut elements);
    push_layers(renderer, shell, output, Layer::Background, &programs, &params, &mut elements);
    elements
}

/// Панели Delta размываются; у эффектов «джинн», «край окна» и кнопок окна слой
/// во весь экран, им размытие не нужно (те же правила, что были для Hyprland).
fn layer_glass(layer: &LayerSurface, p: &Params, scale: f64) -> Option<Glass> {
    if !p.blur_on {
        return None;
    }
    let ns = layer.namespace();
    if !ns.starts_with("delta-")
        || matches!(ns, "delta-wallpaper" | "delta-genie" | "delta-jelly" | "delta-snap" | "delta-window-controls" | "delta-start")
    {
        return None;
    }
    Some(Glass {
        blur: p.blur,
        ignore_alpha: p.ignore_alpha,
        lens: p.lens * scale as f32,
        lens_reach: 16.0 * scale as f32,
    })
}

fn push_layers(
    renderer: &mut R,
    shell: &Shell,
    output: &Output,
    which: Layer,
    programs: &Option<Rc<Programs>>,
    params: &Params,
    out: &mut Vec<OutputElement>,
) {
    let f = output.current_scale().fractional_scale();
    let scale = Scale::from(f);
    let map = layer_map_for_output(output);
    let layers: Vec<LayerSurface> = map.layers_on(which).rev().cloned().collect();
    for layer in layers {
        let Some(geo) = map.layer_geometry(&layer) else { continue };
        let loc = geo.loc.to_physical_precise_round(scale);
        let surfaces: Vec<Surface> = layer.render_elements(renderer, loc, scale, 1.0);
        let glass = programs.as_ref().and_then(|p| layer_glass(&layer, params, f).map(|g| (p, g)));
        for e in surfaces {
            out.push(match glass {
                Some((p, g)) => OutputElement::Glass(GlassSurface { inner: e, glass: g, scene: shell.fx.scene, programs: p.clone() }),
                None => OutputElement::Surface(e),
            });
        }
    }
}

/// Поверхности окна (спереди назад): меню и само окно.
fn window_surfaces(renderer: &mut R, window: &Window, at: Point<i32, Physical>, scale: Scale<f64>) -> (Vec<Surface>, Vec<Surface>) {
    let origin = at - window.geometry().loc.to_physical_precise_round(scale);
    let Some(toplevel) = window.toplevel() else {
        return (Vec::new(), window.render_elements(renderer, origin, scale, 1.0));
    };
    let surface = toplevel.wl_surface();
    let mut popups = Vec::new();
    for (popup, offset) in PopupManager::popups_for_surface(surface) {
        let o = (window.geometry().loc + offset - popup.geometry().loc).to_physical_precise_round(scale);
        popups.extend(render_elements_from_surface_tree(renderer, popup.wl_surface(), origin + o, scale, 1.0, Kind::Unspecified));
    }
    let main = render_elements_from_surface_tree(renderer, surface, origin, scale, 1.0, Kind::Unspecified);
    (popups, main)
}

fn clip_of(e: Surface, rect: Rectangle<i32, Physical>, radius: f32, programs: &Rc<Programs>, scale: Scale<f64>) -> ClipSurface {
    let at = e.geometry(scale).loc;
    ClipSurface {
        clip: Rectangle::new(rect.loc - at, rect.size),
        radius,
        programs: programs.clone(),
        inner: e,
    }
}

/// Рамка и тень окна; создаётся один раз, чтобы не перерисовывать без нужды.
fn decor_for(window: &Window, rect: Rectangle<i32, Logical>, active: bool, f: f64, p: &Params, programs: &Rc<Programs>) -> Option<PixelShaderElement> {
    if p.border <= 0.0 && p.shadow <= 0.0 {
        return None;
    }
    let pad = p.pad().ceil() as i32;
    let area = Rectangle::new(rect.loc - Point::from((pad, pad)), rect.size + Size::from((pad * 2, pad * 2)));
    let key = fx::DecorKey { area, active, radius: p.radius, border: p.border, color: p.accent, scale: (f * 1000.0) as u32 };
    let mut d = data(window);
    if let Some((e, k)) = &d.fx.decor {
        if *k == key {
            return Some(e.clone());
        }
    }
    let phys = rect.size.to_f64().to_physical(f);
    let color = if active { [p.accent[0], p.accent[1], p.accent[2], 0.93] } else { [1.0, 1.0, 1.0, 0.10] };
    let uniforms = vec![
        Uniform::new("win_size", [phys.w as f32, phys.h as f32]),
        Uniform::new("radius", p.radius * f as f32),
        Uniform::new("border", p.border * f as f32),
        Uniform::new("shadow", p.shadow * f as f32),
        Uniform::new("border_color", color),
    ];
    let element = match d.fx.decor.take() {
        Some((mut e, _)) => {
            e.resize(area, None);
            e.update_uniforms(uniforms);
            e
        }
        None => PixelShaderElement::new(programs.decor.clone(), area, None, 1.0, uniforms, Kind::Unspecified),
    };
    d.fx.decor = Some((element.clone(), key));
    Some(element)
}

/// Снимок окна целиком — со скруглением, рамкой и тенью — на прозрачном фоне.
fn snapshot(
    renderer: &mut R,
    window: &Window,
    f: f64,
    active: bool,
    p: &Params,
    programs: &Rc<Programs>,
    reuse: Option<(GlesTexture, (i32, i32))>,
) -> Option<(GlesTexture, (i32, i32))> {
    let scale = Scale::from(f);
    let size = window.geometry().size;
    let phys: Size<i32, Physical> = size.to_physical_precise_round(scale);
    let pad = (p.pad().ceil() as f64 * f).round() as i32;
    let full = (phys.w + pad * 2, phys.h + pad * 2);
    // не window.alive(): при закрытии xdg_toplevel уже мёртв, а поверхность с кадром ещё нет
    if full.0 <= 0 || full.1 <= 0 || !window.wl_surface().is_some_and(|s| s.is_alive()) {
        return None;
    }
    let mut tex = match reuse {
        Some((t, s)) if s == full => t,
        _ => renderer.create_buffer(Fourcc::Abgr8888, (full.0, full.1).into()).map_err(|e| tracing::warn!("снимок окна: {e:?}")).ok()?,
    };
    let at = Point::<i32, Physical>::from((pad, pad));
    let (popups, main) = window_surfaces(renderer, window, at, scale);
    if main.is_empty() {
        return None;
    }
    let rect = Rectangle::new(at, phys);
    let radius = p.radius * f as f32;
    let mut elements: Vec<OutputElement> = popups.into_iter().map(OutputElement::Surface).collect();
    for e in main {
        elements.push(OutputElement::Clip(clip_of(e, rect, radius, programs, scale)));
    }
    let logical_pad = p.pad().ceil() as i32;
    let color = if active { [p.accent[0], p.accent[1], p.accent[2], 0.93] } else { [1.0, 1.0, 1.0, 0.10] };
    elements.push(OutputElement::Decor(PixelShaderElement::new(
        programs.decor.clone(),
        Rectangle::new((0, 0).into(), size + Size::from((logical_pad * 2, logical_pad * 2))),
        None,
        1.0,
        vec![
            Uniform::new("win_size", [phys.w as f32, phys.h as f32]),
            Uniform::new("radius", radius),
            Uniform::new("border", p.border * f as f32),
            Uniform::new("shadow", p.shadow * f as f32),
            Uniform::new("border_color", color),
        ],
        Kind::Unspecified,
    )));
    let mut damage = OutputDamageTracker::new(full, f, Transform::Normal);
    {
        let mut target = renderer.bind(&mut tex).map_err(|e| tracing::warn!("снимок окна: {e:?}")).ok()?;
        damage
            .render_output(renderer, &mut target, 0, &elements, [0.0, 0.0, 0.0, 0.0])
            .map_err(|e| tracing::warn!("снимок окна: {e:?}"))
            .ok()?;
    }
    Some((tex, full))
}

fn window_is_opaque(main: &[Surface], rect: Rectangle<i32, Physical>, scale: Scale<f64>) -> bool {
    let mut rest = vec![rect];
    for e in main {
        let at = e.geometry(scale).loc;
        let opaque: Vec<_> = e.opaque_regions(scale).iter().map(|r| Rectangle::new(r.loc + at, r.size)).collect();
        rest = Rectangle::subtract_rects_many(rest, opaque).into_iter().collect();
    }
    rest.is_empty()
}

fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

fn smooth(a: f32, b: f32, x: f32) -> f32 {
    let t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

/// Настройка появления для снимка: `v` — положение пружины, `t` — доля времени.
fn reveal_mesh(kind: Open, v: f32, t: f32, win: Size<i32, Physical>, pad: f32, margin: f32, radius: f32, accent: [f32; 3]) -> Mesh {
    let (w, h) = (win.w as f32, win.h as f32);
    let (cx, cy) = (margin + pad + w * 0.5, margin + pad + h * 0.5);
    let (full_w, full_h) = (w + pad * 2.0, h + pad * 2.0);
    let huge = [cx, cy, full_w + margin, full_h + margin];
    let mut r = RevealParams {
        content: [margin, margin, full_w, full_h],
        shape: huge,
        shape_r: 0.0,
        ball: [0.0; 4],
        content_alpha: 1.0,
        alpha: 1.0,
        win: [cx, cy, w * 0.5, h * 0.5],
        win_radius: radius,
    };
    let scaled = |r: &mut RevealParams, s: f32, dy: f32| {
        let (sw, sh) = (full_w * s, full_h * s);
        r.content = [cx - sw * 0.5, cy - sh * 0.5 + dy, sw, sh];
    };
    match kind {
        Open::Inside => {
            // капля растёт изнутри окна, потом в ней проявляется окно
            let start = 22.0_f32.min(w * 0.5).min(h * 0.5);
            r.shape = [cx, cy, lerp(start, full_w * 0.5, v.max(0.0)), lerp(start, full_h * 0.5, v.max(0.0))];
            r.shape_r = lerp(start, radius + pad, v.clamp(0.0, 1.0));
            r.ball = [accent[0], accent[1], accent[2], 1.0];
            r.content_alpha = smooth(0.18, 0.52, t);
            scaled(&mut r, lerp(0.86, 1.0, v), 0.0);
            r.alpha = smooth(0.0, 0.06, t);
        }
        Open::Slide => {
            scaled(&mut r, 1.0, (1.0 - v) * h.min(90.0));
            r.alpha = smooth(0.0, 0.3, t);
        }
        Open::Fade => r.alpha = t.clamp(0.0, 1.0),
        _ => {
            scaled(&mut r, lerp(0.82, 1.0, v), 0.0);
            r.alpha = smooth(0.0, 0.3, t);
        }
    }
    Mesh::Reveal(r)
}

#[allow(clippy::too_many_arguments)]
fn push_window(
    renderer: &mut R,
    shell: &Shell,
    window: &Window,
    loc: Point<i32, Logical>,
    area: Rectangle<i32, Logical>,
    scale: Scale<f64>,
    active: bool,
    now: Instant,
    programs: &Option<Rc<Programs>>,
    p: &Params,
    out: &mut Vec<OutputElement>,
) {
    if data(window).hidden {
        return;
    }
    let f = scale.x;
    let size = window.geometry().size;
    let rect = Rectangle::new(loc - area.loc, size);
    let at: Point<i32, Physical> = rect.loc.to_physical_precise_round(scale);
    let phys: Size<i32, Physical> = size.to_physical_precise_round(scale);
    let phys_rect = Rectangle::new(at, phys);

    let plain = programs.is_none()
        || data(window).mode == Mode::Fullscreen
        || window.x11_surface().is_some_and(|x| x.is_override_redirect());
    let Some(programs) = programs.as_ref().filter(|_| !plain) else {
        data(window).fx.opening = false;
        let (popups, main) = window_surfaces(renderer, window, at, scale);
        out.extend(popups.into_iter().chain(main).map(OutputElement::Surface));
        return;
    };

    // анимация окна: снимок на своей геометрии
    enum Now {
        None,
        Open { kind: Open, x: f32, t: f32 },
        Geom { from: Rectangle<f64, Logical>, v: f32 },
        Jelly,
    }
    let state = {
        let mut d = data(window);
        if d.fx.opening && !p.animations {
            d.fx.opening = false;
        }
        if d.fx.opening && d.fx.open_start.is_none() {
            d.fx.open_start = Some(now);
        }
        let mut state = Now::None;
        if d.fx.jelly.is_some() {
            state = Now::Jelly;
        } else if d.fx.opening {
            let x = now.saturating_duration_since(d.fx.open_start.unwrap_or(now)).as_secs_f32() / p.time;
            let total = p.duration(p.open, true);
            if x >= total {
                d.fx.opening = false;
                d.fx.open_start = None;
            } else {
                state = Now::Open { kind: p.open, x, t: x / total };
            }
        } else if let Some((from, start)) = d.fx.geom {
            let x = now.saturating_duration_since(start).as_secs_f32() / p.global_time;
            if x >= p.motion.geom.settle() {
                d.fx.geom = None;
            } else {
                state = Now::Geom { from, v: p.motion.geom.value(x) };
            }
        }
        state
    };

    let (popups, main) = window_surfaces(renderer, window, at, scale);
    let radius = p.radius * f as f32;
    let blur = (p.blur_on && !window_is_opaque(&main, phys_rect, scale)).then_some(p.blur);

    if !matches!(state, Now::None) {
        let reuse = data(window).fx.tex.take();
        if let Some((tex, tex_size)) = snapshot(renderer, window, f, active, p, programs, reuse) {
            data(window).fx.tex = Some((tex.clone(), tex_size));
            let pad = (p.pad().ceil() as f64 * f).round() as f32;
            let mut d = data(window);
            d.fx.commit.increment();
            let commit = d.fx.commit;
            let id = d.fx.mesh_id.get_or_insert_with(Id::new).clone();
            let (x, y, w, h) = (at.x as f32, at.y as f32, phys.w as f32, phys.h as f32);
            let (geo, mesh, mblur) = match state {
                Now::Jelly => {
                    let strength = p.jelly.max(0.05);
                    let diag = (size.w as f32).hypot(size.h as f32);
                    let target = (loc.x as f32, loc.y as f32);
                    let jelly = d.fx.jelly.as_mut().unwrap();
                    let (off, calm) = jelly.step(target, diag, strength, now);
                    let grab = jelly.grab;
                    let done = jelly.stop
                        || jelly.released.is_some_and(|t| calm || now.saturating_duration_since(t).as_secs_f32() > 1.1);
                    if done {
                        d.fx.jelly = None;
                    }
                    let k = f as f32;
                    let o = off.map(|v| [v[0] * k, v[1] * k]);
                    let spread = o.iter().map(|v| v[0].hypot(v[1])).fold(0.0, f32::max).ceil() + 4.0;
                    let m = pad + spread;
                    let geo = Rectangle::new(
                        Point::from(((x - m).floor() as i32, (y - m).floor() as i32)),
                        Size::from(((w + m * 2.0).ceil() as i32, (h + m * 2.0).ceil() as i32)),
                    );
                    let grabp = [grab.0 * k, grab.1 * k];
                    let reach = [(0.0, 0.0), (w, 0.0), (0.0, h), (w, h)]
                        .iter()
                        .map(|c: &(f32, f32)| (c.0 - grabp[0]).hypot(c.1 - grabp[1]))
                        .fold(0.0, f32::max);
                    let rel = [x - geo.loc.x as f32, y - geo.loc.y as f32, w, h];
                    (geo, Mesh::Jelly(JellyParams { rel, pad, grab: grabp, reach, o, radius }), blur)
                }
                Now::Open { kind: Open::Assemble, x: secs, .. } => {
                    let spring = p.motion.shards;
                    let margin = 220.0 + 0.2 * w.hypot(h);
                    let verts = shards_for(&mut d, tex_size, 72.0 * f as f32);
                    let geo = pad_rect(x - pad, y - pad, w + pad * 2.0, h + pad * 2.0, margin);
                    let origin = [x - pad - geo.loc.x as f32, y - pad - geo.loc.y as f32];
                    let m = Mesh::Shards {
                        t: secs,
                        omega: spring.omega(),
                        zeta: spring.zeta,
                        alpha: 1.0,
                        origin,
                        full: [tex_size.0 as f32, tex_size.1 as f32],
                        verts,
                    };
                    (geo, m, None)
                }
                Now::Open { kind, x: secs, t } => {
                    let v = p.motion.open.value(secs);
                    let margin = 0.08 * w.max(h);
                    let geo = pad_rect(x - pad, y - pad, w + pad * 2.0, h + pad * 2.0, margin);
                    (geo, reveal_mesh(kind, v, t, phys, pad, margin, radius, p.accent), blur)
                }
                Now::Geom { from, v } => {
                    let v = v as f64;
                    let l = |a: f64, b: f64| a + (b - a) * v;
                    let lx = l(from.loc.x, rect.loc.x as f64 + area.loc.x as f64) - area.loc.x as f64;
                    let ly = l(from.loc.y, rect.loc.y as f64 + area.loc.y as f64) - area.loc.y as f64;
                    let lw = l(from.size.w, size.w as f64).max(1.0);
                    let lh = l(from.size.h, size.h as f64).max(1.0);
                    let (gx, gy, gw, gh) = ((lx * f) as f32, (ly * f) as f32, (lw * f) as f32, (lh * f) as f32);
                    let geo = pad_rect(gx - pad, gy - pad, gw + pad * 2.0, gh + pad * 2.0, 2.0);
                    let (cx, cy) = (gx + gw * 0.5 - geo.loc.x as f32, gy + gh * 0.5 - geo.loc.y as f32);
                    let r = RevealParams {
                        content: [gx - pad - geo.loc.x as f32, gy - pad - geo.loc.y as f32, gw + pad * 2.0, gh + pad * 2.0],
                        shape: [cx, cy, gw + pad * 2.0, gh + pad * 2.0],
                        shape_r: 0.0,
                        ball: [0.0; 4],
                        content_alpha: 1.0,
                        alpha: 1.0,
                        win: [cx, cy, gw * 0.5, gh * 0.5],
                        win_radius: radius,
                    };
                    (geo, Mesh::Reveal(r), blur)
                }
                Now::None => unreachable!(),
            };
            drop(d);
            out.push(OutputElement::Mesh(MeshElement { id, commit, geo, tex, mesh, blur: mblur, programs: programs.clone() }));
            return;
        }
    }

    // обычная отрисовка
    out.extend(popups.into_iter().map(OutputElement::Surface));
    if radius > 0.0 {
        for e in main {
            out.push(OutputElement::Clip(clip_of(e, phys_rect, radius, programs, scale)));
        }
    } else {
        out.extend(main.into_iter().map(OutputElement::Surface));
    }
    if let Some(e) = decor_for(window, rect, active, f, p, programs) {
        out.push(OutputElement::Decor(e));
    }
    if let Some(blur) = blur {
        let id = data(window).fx.backdrop_id.get_or_insert_with(Id::new).clone();
        out.push(OutputElement::Backdrop(Backdrop { id, geo: phys_rect, radius, blur, scene: shell.fx.scene, programs: programs.clone() }));
    }
}

fn pad_rect(x: f32, y: f32, w: f32, h: f32, m: f32) -> Rectangle<i32, Physical> {
    Rectangle::new(
        Point::from(((x - m).floor() as i32, (y - m).floor() as i32)),
        Size::from(((w + m * 2.0).ceil() as i32, (h + m * 2.0).ceil() as i32)),
    )
}

fn shards_for(d: &mut crate::workspaces::WinData, size: (i32, i32), tile: f32) -> Rc<Vec<f32>> {
    if let Some((v, s)) = &d.fx.shards {
        if *s == size {
            return v.clone();
        }
    }
    let v = fx::build_shards(size.0, size.1, tile);
    d.fx.shards = Some((v.clone(), size));
    v
}

fn push_closing(
    shell: &mut Shell,
    area: Rectangle<i32, Logical>,
    scale: Scale<f64>,
    now: Instant,
    programs: &Rc<Programs>,
    p: &Params,
    out: &mut Vec<OutputElement>,
) {
    let f = scale.x;
    let total = |kind: Open| p.duration(kind, false) * if kind == Open::Assemble { 0.55 } else { 1.0 };
    shell.fx.closing.retain(|c| now.saturating_duration_since(c.start).as_secs_f32() / p.time < total(c.kind));
    for c in shell.fx.closing.iter_mut().rev() {
        let inter = c.rect.overlaps(area);
        if !inter {
            continue;
        }
        c.commit.increment();
        let secs = now.saturating_duration_since(c.start).as_secs_f32() / p.time;
        let t = secs / total(c.kind);
        let pad = (p.pad().ceil() as f64 * c.scale).round() as f32;
        let at: Point<i32, Physical> = (c.rect.loc - area.loc).to_physical_precise_round(scale);
        let phys: Size<i32, Physical> = c.rect.size.to_physical_precise_round(scale);
        let (x, y, w, h) = (at.x as f32, at.y as f32, phys.w as f32, phys.h as f32);
        let radius = p.radius * f as f32;
        let (geo, mesh) = match c.kind {
            Open::Assemble => {
                let spring = p.motion.shards;
                let verts = c.shards.get_or_insert_with(|| fx::build_shards(c.tex_size.0, c.tex_size.1, 72.0 * f as f32)).clone();
                let margin = 220.0 + 0.2 * w.hypot(h);
                let geo = pad_rect(x - pad, y - pad, w + pad * 2.0, h + pad * 2.0, margin);
                let m = Mesh::Shards {
                    // обратный ход: плитки разлетаются
                    t: (1.0 - t) * spring.settle(),
                    omega: spring.omega(),
                    zeta: spring.zeta,
                    alpha: 1.0,
                    origin: [x - pad - geo.loc.x as f32, y - pad - geo.loc.y as f32],
                    full: [c.tex_size.0 as f32, c.tex_size.1 as f32],
                    verts,
                };
                (geo, m)
            }
            kind => {
                let v = 1.0 - close_curve(p.motion.close, secs);
                let margin = 0.08 * w.max(h);
                let geo = pad_rect(x - pad, y - pad, w + pad * 2.0, h + pad * 2.0, margin);
                (geo, reveal_mesh(kind, v, 1.0 - t, phys, pad, margin, radius, p.accent))
            }
        };
        out.push(OutputElement::Mesh(MeshElement {
            id: c.id.clone(),
            commit: c.commit,
            geo,
            tex: c.tex.clone(),
            mesh,
            blur: None,
            programs: programs.clone(),
        }));
    }
}

fn close_curve(s: Spring, x: f32) -> f32 {
    s.value(x).clamp(0.0, 1.0)
}

impl Shell {
    /// Программы эффектов; не собрались — окна будут просто без эффектов.
    fn fx_programs(&mut self, renderer: &mut R) -> Option<Rc<Programs>> {
        if self.fx.programs.is_none() && !self.fx.failed {
            match Programs::new(renderer) {
                Ok(p) => self.fx.programs = Some(p),
                Err(e) => {
                    tracing::warn!("эффекты окон выключены: {e}");
                    self.fx.failed = true;
                }
            }
        }
        self.fx.programs.clone()
    }

    /// Панели на стекле перерисовываются, только если под ними могло что-то
    /// измениться: новый кадр программы (счётчик в commit), сдвиг окна, анимация.
    fn update_scene(&mut self) {
        let mut h = DefaultHasher::new();
        for w in self.space.elements() {
            data(w).address.hash(&mut h);
            let loc = self.space.element_location(w).unwrap_or_default();
            (loc.x, loc.y).hash(&mut h);
            let size = w.geometry().size;
            (size.w, size.h).hash(&mut h);
        }
        let hash = h.finish();
        let animating = !self.fx.closing.is_empty()
            || !self.fx.ws.is_empty()
            || self.windows.iter().any(|w| {
                let d = data(w);
                d.fx.opening || d.fx.geom.is_some() || d.fx.jelly.is_some()
            });
        if hash != self.fx.scene_hash || animating {
            self.fx.scene_hash = hash;
            self.fx.scene.increment();
        }
    }

    /// Окно закрывается: снимаем его, пока поверхность жива, и доигрываем поверх.
    pub fn fx_window_closing(&mut self, window: &Window) {
        let p = Params::from_settings(&self.settings);
        let Some(loc) = self.space.element_location(window) else { return };
        if !p.animations || data(window).mode == Mode::Fullscreen || data(window).hidden || self.is_locked() {
            return;
        }
        let alive = window.toplevel().is_none_or(|t| t.wl_surface().is_alive())
            && window.x11_surface().is_none_or(|x| x.wl_surface().is_some());
        if !alive {
            return;
        }
        let rect = Rectangle::new(loc, window.geometry().size);
        let f = self.output_of(window).map(|o| o.current_scale().fractional_scale()).unwrap_or(1.0);
        let focused = self.focused_window().as_ref() == Some(window);
        let shot = self.with_renderer(|shell, renderer| {
            let programs = shell.fx_programs(renderer)?;
            snapshot(renderer, window, f, focused, &p, &programs, None)
        });
        if let Some(Some((tex, tex_size))) = shot {
            self.fx.closing.push(Closing {
                tex,
                tex_size,
                rect,
                scale: f,
                start: Instant::now(),
                kind: p.close,
                id: Id::new(),
                commit: CommitCounter::default(),
                shards: None,
            });
        }
    }

    /// Окно сменило место или размер: едет от прежнего прямоугольника.
    pub fn fx_geometry_from(&mut self, window: &Window, from: Rectangle<i32, Logical>) {
        if self.settings.windows.animations {
            let mut d = data(window);
            d.fx.jelly = None;
            d.fx.geom = Some((from.to_f64(), Instant::now()));
        }
    }

    /// Стол сменился: dir 1 — новый едет справа.
    pub fn fx_workspace(&mut self, output: String, old: Vec<Window>, dir: f32) {
        if self.settings.windows.animations {
            self.fx.ws.insert(output, WsAnim { old, dir, start: Instant::now() });
        }
    }

    /// Начали тянуть окно: желе ведёт сам кадр — без копии и без задержки.
    pub fn fx_jelly_begin(&mut self, window: &Window, grab: Point<i32, Logical>, at: Point<i32, Logical>) {
        let p = Params::from_settings(&self.settings);
        let mut d = data(window);
        if p.jelly > 0.0 && d.mode != Mode::Fullscreen {
            d.fx.geom = None;
            d.fx.jelly = Some(fx::Jelly::new((grab.x as f32, grab.y as f32), (at.x as f32, at.y as f32), Instant::now()));
        }
    }

    pub fn fx_jelly_release(&mut self, window: &Window) {
        if let Some(j) = data(window).fx.jelly.as_mut() {
            j.released = Some(Instant::now());
        }
    }
}

/// Кому сообщить, что этот кадр показан (wp_presentation): Vulkan и видео
/// сверяют по этому время следующего кадра.
pub fn take_feedback(shell: &Shell, output: &Output, states: &RenderElementStates) -> OutputPresentationFeedback {
    let mut feedback = OutputPresentationFeedback::new(output);
    let primary = |_: &_, _: &_| Some(output.clone());
    let flags = |surface: &_, _: &_| surface_presentation_feedback_flags_from_states(surface, states);
    for window in shell.space.elements() {
        if shell.space.outputs_for_element(window).contains(output) {
            window.take_presentation_feedback(&mut feedback, primary, flags);
        }
    }
    for layer in layer_map_for_output(output).layers() {
        layer.take_presentation_feedback(&mut feedback, primary, flags);
    }
    feedback
}
