//! Захват картинки: wlr-screencopy (монитор: grim, wf-recorder, Quickshell) и
//! hyprland_toplevel_export (одно окно: живая копия у «желе» и сворачивания
//! Delta). Программа даёт буфер, а кадр в него рисуется заново в ближайший проход
//! отрисовки. Заблокированный стол не отдаётся: у монитора рисуется только замок,
//! окна на это время не захватываются.

use std::sync::Mutex;

use smithay::{
    backend::{
        allocator::{Buffer as _, Fourcc},
        renderer::{
            damage::OutputDamageTracker,
            element::{
                surface::WaylandSurfaceRenderElement,
                utils::{Relocate, RelocateRenderElement},
                AsRenderElements,
            },
            gles::{GlesRenderer, GlesTexture},
            Bind, ExportMem, Offscreen, Renderer as _,
        },
    },
    desktop::Window,
    output::Output,
    reexports::{
        wayland_protocols_wlr::{
            screencopy::v1::server::{
                zwlr_screencopy_frame_v1::{self, ZwlrScreencopyFrameV1},
                zwlr_screencopy_manager_v1::{self, ZwlrScreencopyManagerV1},
            },
        },
        wayland_server::{
            backend::ClientId,
            protocol::{wl_buffer::WlBuffer, wl_output::WlOutput, wl_shm},
            Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
        },
    },
    utils::{Physical, Point, Rectangle, Scale, Size, Transform},
    wayland::{
        dmabuf::get_dmabuf,
        shm::{with_buffer_contents, with_buffer_contents_mut},
    },
};

use super::generated::toplevel_export::{
    hyprland_toplevel_export_frame_v1::{self, HyprlandToplevelExportFrameV1},
    hyprland_toplevel_export_manager_v1::{self, HyprlandToplevelExportManagerV1},
};
use crate::{
    config,
    render::{output_elements, OutputElement},
    workspaces::data,
    Shell,
};

#[derive(Clone)]
enum Source {
    Output { output: Output, region: Rectangle<i32, Physical> },
    Window(Window),
}

/// Что снимает кадр: ждёт буфер от программы. None — уже снято или снимать нечего.
struct Capture {
    source: Source,
    size: Size<i32, Physical>,
    overlay_cursor: bool,
}

type FrameData = Mutex<Option<Capture>>;

#[derive(Clone)]
enum Frame {
    Wlr(ZwlrScreencopyFrameV1),
    Export(HyprlandToplevelExportFrameV1),
}

impl Frame {
    fn alive(&self) -> bool {
        match self {
            Frame::Wlr(f) => f.is_alive(),
            Frame::Export(f) => f.is_alive(),
        }
    }

    fn failed(&self) {
        match self {
            Frame::Wlr(f) => f.failed(),
            Frame::Export(f) => f.failed(),
        }
    }

    /// Какой буфер нужен. Монитор непрозрачен, у окна важны скруглённые углы.
    fn announce(&self, size: Size<i32, Physical>) {
        let (w, h) = (size.w as u32, size.h as u32);
        match self {
            Frame::Wlr(f) => {
                f.buffer(wl_shm::Format::Xrgb8888, w, h, w * 4);
                if f.version() >= 3 {
                    f.linux_dmabuf(Fourcc::Xrgb8888 as u32, w, h);
                    f.buffer_done();
                }
            }
            Frame::Export(f) => {
                f.buffer(wl_shm::Format::Argb8888, w, h, w * 4);
                f.linux_dmabuf(Fourcc::Argb8888 as u32, w, h);
                f.buffer_done();
            }
        }
    }

    fn ready(&self, size: Size<i32, Physical>, time: std::time::Duration, with_damage: bool) {
        let (w, h) = (size.w as u32, size.h as u32);
        let secs = time.as_secs();
        let (hi, lo, nanos) = ((secs >> 32) as u32, secs as u32, time.subsec_nanos());
        match self {
            Frame::Wlr(f) => {
                f.flags(zwlr_screencopy_frame_v1::Flags::empty());
                if with_damage {
                    f.damage(0, 0, w, h);
                }
                f.ready(hi, lo, nanos);
            }
            Frame::Export(f) => {
                f.flags(hyprland_toplevel_export_frame_v1::Flags::empty());
                if with_damage {
                    f.damage(0, 0, w, h);
                }
                f.ready(hi, lo, nanos);
            }
        }
    }
}

struct Pending {
    frame: Frame,
    buffer: WlBuffer,
    capture: Capture,
    with_damage: bool,
}

#[derive(Default)]
pub struct ScreencopyState {
    pending: Vec<Pending>,
}

impl ScreencopyState {
    pub fn new(dh: &DisplayHandle) -> Self {
        dh.create_global::<Shell, ZwlrScreencopyManagerV1, _>(3, ());
        dh.create_global::<Shell, HyprlandToplevelExportManagerV1, _>(2, ());
        Self::default()
    }
}

/// Буфер подходит: нужный размер и формат, в который мы умеем писать.
fn buffer_fits(buffer: &WlBuffer, size: Size<i32, Physical>) -> bool {
    if let Ok(dmabuf) = get_dmabuf(buffer) {
        let s = dmabuf.size();
        return (s.w, s.h) == (size.w, size.h);
    }
    with_buffer_contents(buffer, |_, _, d| {
        d.width == size.w && d.height == size.h && d.stride >= size.w * 4 && matches!(d.format, wl_shm::Format::Xrgb8888 | wl_shm::Format::Argb8888)
    })
    .unwrap_or(false)
}

impl Shell {
    fn output_capture(&self, output: &WlOutput, region: Option<Rectangle<i32, smithay::utils::Logical>>, overlay_cursor: bool) -> Option<Capture> {
        let output = Output::from_resource(output)?;
        let mode = output.current_mode()?;
        self.space.output_geometry(&output)?;
        let scale = output.current_scale().fractional_scale();
        let whole = Rectangle::from_size(output.current_transform().transform_size(mode.size));
        let region = match region {
            Some(r) => r.to_f64().to_physical(scale).to_i32_round().intersection(whole)?,
            None => whole,
        };
        (region.size.w > 0 && region.size.h > 0).then_some(Capture { size: region.size, source: Source::Output { output, region }, overlay_cursor })
    }

    fn window_capture(&self, window: Window) -> Option<Capture> {
        if self.is_locked() {
            return None;
        }
        let scale = self.output_of(&window).map(|o| o.current_scale().fractional_scale()).unwrap_or(1.0);
        let size: Size<i32, Physical> = window.geometry().size.to_f64().to_physical(scale).to_i32_round();
        (size.w > 0 && size.h > 0).then_some(Capture { size, source: Source::Window(window), overlay_cursor: false })
    }

    /// Снять всё, что ждёт этот монитор, и все окна. Зовётся после кадра.
    pub fn run_copies(&mut self, renderer: &mut GlesRenderer, output: &Output) {
        if self.screencopy.pending.is_empty() {
            return;
        }
        let pending = std::mem::take(&mut self.screencopy.pending);
        for p in pending {
            if matches!(&p.capture.source, Source::Output { output: o, .. } if o != output) {
                self.screencopy.pending.push(p);
                continue;
            }
            if !p.frame.alive() || !p.buffer.is_alive() {
                continue;
            }
            match self.copy_frame(renderer, &p) {
                Ok(()) => p.frame.ready(p.capture.size, self.clock.now().into(), p.with_damage),
                Err(e) => {
                    tracing::warn!("захват не удался: {e}");
                    p.frame.failed();
                }
            }
        }
    }

    fn copy_frame(&mut self, renderer: &mut GlesRenderer, p: &Pending) -> Result<(), String> {
        let (elements, shift, scale, transform, clear) = match &p.capture.source {
            Source::Output { output, region } => {
                let elements = output_elements(renderer, self, output, p.capture.overlay_cursor);
                (elements, region.loc, output.current_scale().fractional_scale(), output.current_transform(), config::BACKGROUND)
            }
            Source::Window(window) => {
                if self.is_locked() {
                    return Err("стол заблокирован".into());
                }
                let scale = self.output_of(window).map(|o| o.current_scale().fractional_scale()).unwrap_or(1.0);
                let surfaces: Vec<WaylandSurfaceRenderElement<GlesRenderer>> =
                    AsRenderElements::render_elements(window, renderer, (0, 0).into(), Scale::from(scale), 1.0);
                let at = window.geometry().loc.to_f64().to_physical(scale).to_i32_round();
                (surfaces.into_iter().map(OutputElement::Surface).collect(), at, scale, Transform::Normal, [0.0; 4])
            }
        };
        let shift = Point::<i32, Physical>::from((-shift.x, -shift.y));
        let elements: Vec<_> = elements.into_iter().map(|e| RelocateRenderElement::from_element(e, shift, Relocate::Relative)).collect();
        render_into(renderer, &elements, p, scale, transform, clear)
    }
}

fn render_into(
    renderer: &mut GlesRenderer,
    elements: &[RelocateRenderElement<OutputElement>],
    p: &Pending,
    scale: f64,
    transform: Transform,
    clear: [f32; 4],
) -> Result<(), String> {
    let size = p.capture.size;
    let mut tracker = OutputDamageTracker::new(size, scale, transform);

    // dmabuf — прямо в память программы, без копии через процессор
    if let Ok(dmabuf) = get_dmabuf(&p.buffer) {
        let mut dmabuf = dmabuf.clone();
        let mut target = renderer.bind(&mut dmabuf).map_err(|e| e.to_string())?;
        let result = tracker.render_output(renderer, &mut target, 0, elements, clear).map_err(|e| format!("{e:?}"))?;
        return renderer.wait(&result.sync).map_err(|e| e.to_string());
    }

    let buffer_size = size.to_logical(1).to_buffer(1, Transform::Normal);
    let mut texture: GlesTexture = renderer.create_buffer(Fourcc::Abgr8888, buffer_size).map_err(|e| e.to_string())?;
    let mut target = renderer.bind(&mut texture).map_err(|e| e.to_string())?;
    tracker.render_output(renderer, &mut target, 0, elements, clear).map_err(|e| format!("{e:?}"))?;
    let mapping = renderer.copy_framebuffer(&target, Rectangle::from_size(buffer_size), Fourcc::Argb8888).map_err(|e| e.to_string())?;
    let pixels = renderer.map_texture(&mapping).map_err(|e| e.to_string())?;

    let row = size.w as usize * 4;
    with_buffer_contents_mut(&p.buffer, |ptr, len, d| {
        let (offset, stride) = (d.offset as usize, d.stride as usize);
        if pixels.len() < row * size.h as usize || offset + stride * size.h as usize > len {
            return Err("буфер меньше кадра".to_string());
        }
        for y in 0..size.h as usize {
            // размеры проверены выше; буфер программы — общая память, она своя у каждой стороны
            unsafe { std::ptr::copy_nonoverlapping(pixels[y * row..].as_ptr(), ptr.add(offset + y * stride), row) };
        }
        Ok(())
    })
    .map_err(|e| e.to_string())?
}

impl GlobalDispatch<ZwlrScreencopyManagerV1, ()> for Shell {
    fn bind(_: &mut Self, _: &DisplayHandle, _: &Client, resource: New<ZwlrScreencopyManagerV1>, _: &(), init: &mut DataInit<'_, Self>) {
        init.init(resource, ());
    }
}

impl Dispatch<ZwlrScreencopyManagerV1, ()> for Shell {
    fn request(
        state: &mut Self,
        _: &Client,
        _: &ZwlrScreencopyManagerV1,
        request: zwlr_screencopy_manager_v1::Request,
        _: &(),
        _: &DisplayHandle,
        init: &mut DataInit<'_, Self>,
    ) {
        let (frame, capture) = match request {
            zwlr_screencopy_manager_v1::Request::CaptureOutput { frame, overlay_cursor, output } => (frame, state.output_capture(&output, None, overlay_cursor != 0)),
            zwlr_screencopy_manager_v1::Request::CaptureOutputRegion { frame, overlay_cursor, output, x, y, width, height } => {
                let region = Rectangle::new((x, y).into(), (width, height).into());
                (frame, state.output_capture(&output, Some(region), overlay_cursor != 0))
            }
            _ => return,
        };
        let size = capture.as_ref().map(|c| c.size);
        let frame = init.init(frame, Mutex::new(capture));
        match size {
            Some(size) => Frame::Wlr(frame).announce(size),
            None => frame.failed(),
        }
    }
}

impl Dispatch<ZwlrScreencopyFrameV1, FrameData> for Shell {
    fn request(
        state: &mut Self,
        _: &Client,
        frame: &ZwlrScreencopyFrameV1,
        request: zwlr_screencopy_frame_v1::Request,
        data: &FrameData,
        _: &DisplayHandle,
        _: &mut DataInit<'_, Self>,
    ) {
        let (buffer, with_damage) = match request {
            zwlr_screencopy_frame_v1::Request::Copy { buffer } => (buffer, false),
            zwlr_screencopy_frame_v1::Request::CopyWithDamage { buffer } => (buffer, true),
            _ => return,
        };
        state.queue_copy(Frame::Wlr(frame.clone()), data, buffer, with_damage);
    }

    fn destroyed(state: &mut Self, _: ClientId, frame: &ZwlrScreencopyFrameV1, _: &FrameData) {
        state.screencopy.pending.retain(|p| !matches!(&p.frame, Frame::Wlr(f) if f == frame));
    }
}

impl GlobalDispatch<HyprlandToplevelExportManagerV1, ()> for Shell {
    fn bind(_: &mut Self, _: &DisplayHandle, _: &Client, resource: New<HyprlandToplevelExportManagerV1>, _: &(), init: &mut DataInit<'_, Self>) {
        init.init(resource, ());
    }
}

impl Dispatch<HyprlandToplevelExportManagerV1, ()> for Shell {
    fn request(
        state: &mut Self,
        _: &Client,
        _: &HyprlandToplevelExportManagerV1,
        request: hyprland_toplevel_export_manager_v1::Request,
        _: &(),
        _: &DisplayHandle,
        init: &mut DataInit<'_, Self>,
    ) {
        let (frame, window) = match request {
            // handle — младшие биты адреса окна из Hyprland IPC
            hyprland_toplevel_export_manager_v1::Request::CaptureToplevel { frame, handle, .. } => {
                (frame, state.windows.iter().find(|w| data(w).address as u32 == handle).cloned())
            }
            hyprland_toplevel_export_manager_v1::Request::CaptureToplevelWithWlrToplevelHandle { frame, handle, .. } => {
                (frame, state.window_of_handle(&handle))
            }
            _ => return,
        };
        let capture = window.and_then(|w| state.window_capture(w));
        let size = capture.as_ref().map(|c| c.size);
        let frame = init.init(frame, Mutex::new(capture));
        match size {
            Some(size) => Frame::Export(frame).announce(size),
            None => frame.failed(),
        }
    }
}

impl Dispatch<HyprlandToplevelExportFrameV1, FrameData> for Shell {
    fn request(
        state: &mut Self,
        _: &Client,
        frame: &HyprlandToplevelExportFrameV1,
        request: hyprland_toplevel_export_frame_v1::Request,
        data: &FrameData,
        _: &DisplayHandle,
        _: &mut DataInit<'_, Self>,
    ) {
        if let hyprland_toplevel_export_frame_v1::Request::Copy { buffer, ignore_damage } = request {
            state.queue_copy(Frame::Export(frame.clone()), data, buffer, ignore_damage == 0);
        }
    }

    fn destroyed(state: &mut Self, _: ClientId, frame: &HyprlandToplevelExportFrameV1, _: &FrameData) {
        state.screencopy.pending.retain(|p| !matches!(&p.frame, Frame::Export(f) if f == frame));
    }
}

impl Shell {
    fn queue_copy(&mut self, frame: Frame, data: &FrameData, buffer: WlBuffer, with_damage: bool) {
        let Some(capture) = data.lock().unwrap().take() else {
            frame.failed();
            return;
        };
        if !buffer_fits(&buffer, capture.size) {
            frame.failed();
            return;
        }
        self.screencopy.pending.push(Pending { frame, buffer, capture, with_damage });
    }
}
