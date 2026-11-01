//! Элементы кадра с эффектами. Всё рисуется в координатах относительно
//! своего `dst`, поэтому снимок экрана (RelocateRenderElement) ничего не ломает.

use std::{cell::RefCell, rc::Rc};

use smithay::{
    backend::renderer::{
        element::{surface::WaylandSurfaceRenderElement, Element, Id, Kind, RenderElement, UnderlyingStorage},
        gles::{
            ffi, GlesError, GlesFrame, GlesPixelProgram, GlesRenderer, GlesTexProgram,
            GlesTexture, Uniform, UniformName, UniformType,
        },
        utils::{CommitCounter, DamageSet, OpaqueRegions},
    },
    utils::{Buffer as BufferCoords, Physical, Point, Rectangle, Scale, Size, Transform},
};

use super::{
    gl::{self as gl_util, bind_positions, fb_rect, viewport, Blurred, Chain, Raw, UNIT_QUAD},
    shaders,
};

type R = GlesRenderer;

/// Программы эффектов — на один GL-контекст.
#[derive(Debug)]
pub struct Programs {
    pub clip: GlesTexProgram,
    pub glass: GlesTexProgram,
    pub decor: GlesPixelProgram,
    down: Raw,
    up: Raw,
    backdrop: Raw,
    reveal: Raw,
    shards: Raw,
    jelly: Raw,
    grid: Vec<f32>,
    chain: RefCell<Chain>,
}

const GRID: usize = 32;

impl Programs {
    pub fn new(renderer: &mut R) -> Result<Rc<Self>, String> {
        let u = |n: &'static str, t| UniformName::new(n, t);
        let clip = renderer
            .compile_custom_texture_shader(shaders::CLIP, &[u("clip_rect", UniformType::_4f), u("clip_radius", UniformType::_1f)])
            .map_err(|e| format!("clip: {e:?}"))?;
        let glass = renderer
            .compile_custom_texture_shader(
                shaders::GLASS,
                &[
                    u("blur_tex", UniformType::_1i),
                    u("blur_map", UniformType::_4f),
                    u("blur_clamp", UniformType::_4f),
                    u("tex_px", UniformType::_2f),
                    u("ignore_alpha", UniformType::_1f),
                    u("lens", UniformType::_1f),
                    u("lens_reach", UniformType::_1f),
                    u("y_sign", UniformType::_1f),
                    u("saturation", UniformType::_1f),
                ],
            )
            .map_err(|e| format!("glass: {e:?}"))?;
        let decor = renderer
            .compile_custom_pixel_shader(
                shaders::DECOR,
                &[
                    u("win_size", UniformType::_2f),
                    u("radius", UniformType::_1f),
                    u("border", UniformType::_1f),
                    u("shadow", UniformType::_1f),
                    u("border_color", UniformType::_4f),
                ],
            )
            .map_err(|e| format!("decor: {e:?}"))?;

        // треугольники сетки «желе»
        let mut grid = Vec::with_capacity(GRID * GRID * 12);
        let step = 1.0 / GRID as f32;
        for y in 0..GRID {
            for x in 0..GRID {
                let (a, b) = (x as f32 * step, y as f32 * step);
                let (c, d) = (a + step, b + step);
                grid.extend_from_slice(&[a, b, c, b, a, d, c, b, c, d, a, d]);
            }
        }

        let (down, up, backdrop, reveal, shards, jelly) = renderer
            .with_context(|gl| unsafe {
                let pass = ["tex", "uv_max", "halfpixel", "offset"];
                let blur = ["blur_tex", "blur_map", "blur_clamp"];
                let list = |extra: &[&'static str]| -> Vec<&'static str> { blur.iter().chain(extra).copied().collect() };
                Ok::<_, String>((
                    Raw::new(gl, shaders::PASS_VERT, shaders::BLUR_DOWN, &pass)?,
                    Raw::new(gl, shaders::PASS_VERT, shaders::BLUR_UP, &pass)?,
                    Raw::new(gl, shaders::QUAD_VERT, shaders::BACKDROP, &list(&["proj", "rect", "radius", "saturation", "alpha"]))?,
                    Raw::new(
                        gl,
                        shaders::QUAD_VERT,
                        shaders::REVEAL,
                        &list(&[
                            "proj", "rect", "tex", "blur_on", "content", "shape_c", "win", "win_radius", "shape_r", "ball",
                            "content_alpha", "alpha",
                        ]),
                    )?,
                    Raw::new(
                        gl,
                        shaders::SHARDS_VERT,
                        shaders::SHARDS_FRAG,
                        &["proj", "origin", "full", "t", "omega", "zeta", "tex", "alpha"],
                    )?,
                    Raw::new(
                        gl,
                        shaders::JELLY_VERT,
                        shaders::JELLY_FRAG,
                        &list(&["proj", "rect", "pad", "grab", "reach", "o12", "o34", "o5", "tex", "blur_on", "radius"]),
                    )?,
                ))
            })
            .map_err(|e| format!("{e:?}"))??;

        Ok(Rc::new(Self {
            clip,
            glass,
            decor,
            down,
            up,
            backdrop,
            reveal,
            shards,
            jelly,
            grid,
            chain: RefCell::new(Chain::default()),
        }))
    }

    unsafe fn blur(&self, gl: &ffi::Gles2, rect: [f32; 4], blur: BlurParams) -> Option<Blurred> {
        self.chain.borrow_mut().run(gl, &self.down, &self.up, rect, blur.passes, blur.offset)
    }
}

/// Сила размытия: проходы и размах одного прохода.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BlurParams {
    pub passes: usize,
    pub offset: f32,
    pub saturation: f32,
}

// ---- окно со скруглёнными углами ----

/// Поверхность окна, обрезанная по скруглённому прямоугольнику окна.
#[derive(Debug)]
pub struct ClipSurface {
    pub inner: WaylandSurfaceRenderElement<R>,
    /// прямоугольник окна относительно этого элемента, физические пиксели
    pub clip: Rectangle<i32, Physical>,
    pub radius: f32,
    pub programs: Rc<Programs>,
}

impl Element for ClipSurface {
    fn id(&self) -> &Id {
        self.inner.id()
    }
    fn current_commit(&self) -> CommitCounter {
        self.inner.current_commit()
    }
    fn location(&self, scale: Scale<f64>) -> Point<i32, Physical> {
        self.inner.location(scale)
    }
    fn src(&self) -> Rectangle<f64, BufferCoords> {
        self.inner.src()
    }
    fn transform(&self) -> Transform {
        self.inner.transform()
    }
    fn geometry(&self, scale: Scale<f64>) -> Rectangle<i32, Physical> {
        self.inner.geometry(scale)
    }
    fn damage_since(&self, scale: Scale<f64>, commit: Option<CommitCounter>) -> DamageSet<i32, Physical> {
        self.inner.damage_since(scale, commit)
    }
    /// Углы окна прозрачны — то, что под ними, надо рисовать.
    fn opaque_regions(&self, scale: Scale<f64>) -> OpaqueRegions<i32, Physical> {
        let r = self.radius.ceil() as i32;
        let g = self.clip;
        let corners = [
            Rectangle::new(g.loc, (r, r).into()),
            Rectangle::new((g.loc.x + g.size.w - r, g.loc.y).into(), (r, r).into()),
            Rectangle::new((g.loc.x, g.loc.y + g.size.h - r).into(), (r, r).into()),
            Rectangle::new((g.loc.x + g.size.w - r, g.loc.y + g.size.h - r).into(), (r, r).into()),
        ];
        let inner = self.inner.opaque_regions(scale);
        let cut: Vec<_> = Rectangle::subtract_rects_many(inner.iter().copied(), corners);
        cut.into_iter().collect()
    }
    fn alpha(&self) -> f32 {
        self.inner.alpha()
    }
    fn kind(&self) -> Kind {
        self.inner.kind()
    }
}

impl RenderElement<R> for ClipSurface {
    fn draw(
        &self,
        frame: &mut GlesFrame<'_, '_>,
        src: Rectangle<f64, BufferCoords>,
        dst: Rectangle<i32, Physical>,
        damage: &[Rectangle<i32, Physical>],
        opaque_regions: &[Rectangle<i32, Physical>],
    ) -> Result<(), GlesError> {
        let proj = *frame.projection();
        let vp = frame.with_context(|gl| unsafe { viewport(gl) })?;
        let c = self.clip;
        let rect = fb_rect(
            &proj,
            vp,
            (dst.loc.x + c.loc.x) as f32,
            (dst.loc.y + c.loc.y) as f32,
            c.size.w as f32,
            c.size.h as f32,
        );
        frame.override_default_tex_program(
            self.programs.clip.clone(),
            vec![Uniform::new("clip_rect", rect), Uniform::new("clip_radius", self.radius)],
        );
        let res = RenderElement::<R>::draw(&self.inner, frame, src, dst, damage, opaque_regions);
        frame.clear_tex_program_override();
        res
    }

    fn underlying_storage(&self, _renderer: &mut R) -> Option<UnderlyingStorage<'_>> {
        None
    }
}

// ---- панель оболочки на стекле ----

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Glass {
    pub blur: BlurParams,
    pub ignore_alpha: f32,
    /// преломление у края, физические пиксели; 0 — без линзы
    pub lens: f32,
    pub lens_reach: f32,
}

/// Панель поверх размытого фона: всё в одном проходе программы GLASS.
#[derive(Debug)]
pub struct GlassSurface {
    pub inner: WaylandSurfaceRenderElement<R>,
    pub glass: Glass,
    /// счётчик сцены: что-то изменилось — панель перерисовывается целиком
    pub scene: CommitCounter,
    pub programs: Rc<Programs>,
}

impl Element for GlassSurface {
    fn id(&self) -> &Id {
        self.inner.id()
    }
    fn current_commit(&self) -> CommitCounter {
        self.scene
    }
    fn location(&self, scale: Scale<f64>) -> Point<i32, Physical> {
        self.inner.location(scale)
    }
    fn src(&self) -> Rectangle<f64, BufferCoords> {
        self.inner.src()
    }
    fn transform(&self) -> Transform {
        self.inner.transform()
    }
    fn geometry(&self, scale: Scale<f64>) -> Rectangle<i32, Physical> {
        self.inner.geometry(scale)
    }
    fn damage_since(&self, scale: Scale<f64>, commit: Option<CommitCounter>) -> DamageSet<i32, Physical> {
        if commit == Some(self.scene) {
            return DamageSet::default();
        }
        DamageSet::from_slice(&[Rectangle::from_size(self.geometry(scale).size)])
    }
    fn opaque_regions(&self, _scale: Scale<f64>) -> OpaqueRegions<i32, Physical> {
        OpaqueRegions::default()
    }
    fn alpha(&self) -> f32 {
        self.inner.alpha()
    }
    fn kind(&self) -> Kind {
        self.inner.kind()
    }
}

impl RenderElement<R> for GlassSurface {
    fn draw(
        &self,
        frame: &mut GlesFrame<'_, '_>,
        src: Rectangle<f64, BufferCoords>,
        dst: Rectangle<i32, Physical>,
        damage: &[Rectangle<i32, Physical>],
        opaque_regions: &[Rectangle<i32, Physical>],
    ) -> Result<(), GlesError> {
        let proj = *frame.projection();
        let programs = self.programs.clone();
        let blur = self.glass.blur;
        let blurred = frame.with_context(|gl| unsafe {
            let vp = viewport(gl);
            let rect = fb_rect(&proj, vp, dst.loc.x as f32, dst.loc.y as f32, dst.size.w as f32, dst.size.h as f32);
            let b = programs.blur(gl, rect, blur);
            if let Some(b) = b {
                gl.ActiveTexture(ffi::TEXTURE1);
                gl.BindTexture(ffi::TEXTURE_2D, b.tex);
                gl.ActiveTexture(ffi::TEXTURE0);
            }
            b
        })?;
        let Some(b) = blurred else {
            return RenderElement::<R>::draw(&self.inner, frame, src, dst, damage, opaque_regions);
        };
        frame.override_default_tex_program(
            self.programs.glass.clone(),
            vec![
                Uniform::new("blur_tex", 1i32),
                Uniform::new("blur_map", b.map),
                Uniform::new("blur_clamp", b.clamp),
                Uniform::new("tex_px", [1.0 / dst.size.w.max(1) as f32, 1.0 / dst.size.h.max(1) as f32]),
                Uniform::new("ignore_alpha", self.glass.ignore_alpha),
                Uniform::new("lens", self.glass.lens),
                Uniform::new("lens_reach", self.glass.lens_reach),
                Uniform::new("y_sign", gl_util::y_sign(&proj)),
                Uniform::new("saturation", self.glass.blur.saturation),
            ],
        );
        let res = RenderElement::<R>::draw(&self.inner, frame, src, dst, damage, &[]);
        frame.clear_tex_program_override();
        frame.with_context(|gl| unsafe {
            gl.ActiveTexture(ffi::TEXTURE1);
            gl.BindTexture(ffi::TEXTURE_2D, 0);
            gl.ActiveTexture(ffi::TEXTURE0);
        })?;
        res
    }
}

// ---- свои проходы: фон окна и снимки на сетке ----

unsafe fn scissored(gl: &ffi::Gles2, proj: &[f32; 9], vp: [i32; 4], dst: Rectangle<i32, Physical>, damage: &[Rectangle<i32, Physical>], mut draw: impl FnMut()) {
    for d in damage {
        let r = fb_rect(
            proj,
            vp,
            (dst.loc.x + d.loc.x) as f32,
            (dst.loc.y + d.loc.y) as f32,
            d.size.w as f32,
            d.size.h as f32,
        );
        gl.Scissor(r[0].floor() as i32, r[1].floor() as i32, (r[2] - r[0]).ceil() as i32, (r[3] - r[1]).ceil() as i32);
        draw();
    }
    gl.Scissor(vp[0], vp[1], vp[2], vp[3]);
}

unsafe fn set_blur(gl: &ffi::Gles2, p: &Raw, b: &Blurred) {
    gl.ActiveTexture(ffi::TEXTURE1);
    gl.BindTexture(ffi::TEXTURE_2D, b.tex);
    gl.ActiveTexture(ffi::TEXTURE0);
    gl.Uniform1i(p.u("blur_tex"), 1);
    gl.Uniform4f(p.u("blur_map"), b.map[0], b.map[1], b.map[2], b.map[3]);
    gl.Uniform4f(p.u("blur_clamp"), b.clamp[0], b.clamp[1], b.clamp[2], b.clamp[3]);
}

unsafe fn unbind(gl: &ffi::Gles2) {
    gl.UseProgram(0);
    gl.ActiveTexture(ffi::TEXTURE1);
    gl.BindTexture(ffi::TEXTURE_2D, 0);
    gl.ActiveTexture(ffi::TEXTURE0);
    gl.BindTexture(ffi::TEXTURE_2D, 0);
    gl.BindBuffer(ffi::ARRAY_BUFFER, 0);
}

/// Размытый фон под полупрозрачным окном.
#[derive(Debug)]
pub struct Backdrop {
    pub id: Id,
    pub geo: Rectangle<i32, Physical>,
    pub radius: f32,
    pub blur: BlurParams,
    pub scene: CommitCounter,
    pub programs: Rc<Programs>,
}

impl Element for Backdrop {
    fn id(&self) -> &Id {
        &self.id
    }
    fn current_commit(&self) -> CommitCounter {
        self.scene
    }
    fn src(&self) -> Rectangle<f64, BufferCoords> {
        Rectangle::from_size(Size::from((self.geo.size.w as f64, self.geo.size.h as f64)))
    }
    fn geometry(&self, _scale: Scale<f64>) -> Rectangle<i32, Physical> {
        self.geo
    }
    fn damage_since(&self, _scale: Scale<f64>, commit: Option<CommitCounter>) -> DamageSet<i32, Physical> {
        if commit == Some(self.scene) {
            return DamageSet::default();
        }
        DamageSet::from_slice(&[Rectangle::from_size(self.geo.size)])
    }
    fn kind(&self) -> Kind {
        Kind::Unspecified
    }
}

impl RenderElement<R> for Backdrop {
    fn draw(
        &self,
        frame: &mut GlesFrame<'_, '_>,
        _src: Rectangle<f64, BufferCoords>,
        dst: Rectangle<i32, Physical>,
        damage: &[Rectangle<i32, Physical>],
        _opaque: &[Rectangle<i32, Physical>],
    ) -> Result<(), GlesError> {
        let proj = *frame.projection();
        let programs = self.programs.clone();
        let (radius, blur) = (self.radius, self.blur);
        frame.with_context(|gl| unsafe {
            let vp = viewport(gl);
            let rect = fb_rect(&proj, vp, dst.loc.x as f32, dst.loc.y as f32, dst.size.w as f32, dst.size.h as f32);
            let Some(b) = programs.blur(gl, rect, blur) else { return };
            let p = &programs.backdrop;
            gl.UseProgram(p.id);
            set_blur(gl, p, &b);
            gl.UniformMatrix3fv(p.u("proj"), 1, ffi::FALSE, proj.as_ptr());
            gl.Uniform4f(p.u("rect"), dst.loc.x as f32, dst.loc.y as f32, dst.size.w as f32, dst.size.h as f32);
            gl.Uniform1f(p.u("radius"), radius);
            gl.Uniform1f(p.u("saturation"), blur.saturation);
            gl.Uniform1f(p.u("alpha"), 1.0);
            let quad = UNIT_QUAD;
            bind_positions(gl, p.a_pos, &quad);
            scissored(gl, &proj, vp, dst, damage, || gl.DrawArrays(ffi::TRIANGLE_STRIP, 0, 4));
            gl.DisableVertexAttribArray(p.a_pos);
            unbind(gl);
        })
    }
}

/// Снимок окна в форме: рост из точки, всплытие, сдвиг. Пиксели — от левого
/// верхнего угла элемента.
#[derive(Debug, Clone, Copy)]
pub struct RevealParams {
    /// где лежит снимок: x, y, ширина, высота
    pub content: [f32; 4],
    /// форма обрезки: центр и половины размера
    pub shape: [f32; 4],
    pub shape_r: f32,
    /// цвет капли (пока окно не проявилось)
    pub ball: [f32; 4],
    pub content_alpha: f32,
    pub alpha: f32,
    /// окно: центр и половины размера — где под ним размытие
    pub win: [f32; 4],
    pub win_radius: f32,
}

#[derive(Debug, Clone, Copy)]
pub struct JellyParams {
    /// окно относительно элемента
    pub rel: [f32; 4],
    pub pad: f32,
    pub grab: [f32; 2],
    pub reach: f32,
    pub o: [[f32; 2]; 5],
    pub radius: f32,
}

#[derive(Debug, Clone)]
pub enum Mesh {
    Reveal(RevealParams),
    Shards { t: f32, omega: f32, zeta: f32, alpha: f32, origin: [f32; 2], full: [f32; 2], verts: Rc<Vec<f32>> },
    Jelly(JellyParams),
}

/// Снимок окна на своей геометрии.
#[derive(Debug)]
pub struct MeshElement {
    pub id: Id,
    pub commit: CommitCounter,
    pub geo: Rectangle<i32, Physical>,
    pub tex: GlesTexture,
    pub mesh: Mesh,
    pub blur: Option<BlurParams>,
    pub programs: Rc<Programs>,
}

impl Element for MeshElement {
    fn id(&self) -> &Id {
        &self.id
    }
    fn current_commit(&self) -> CommitCounter {
        self.commit
    }
    fn src(&self) -> Rectangle<f64, BufferCoords> {
        Rectangle::from_size(Size::from((self.geo.size.w as f64, self.geo.size.h as f64)))
    }
    fn geometry(&self, _scale: Scale<f64>) -> Rectangle<i32, Physical> {
        self.geo
    }
    fn damage_since(&self, _scale: Scale<f64>, commit: Option<CommitCounter>) -> DamageSet<i32, Physical> {
        if commit == Some(self.commit) {
            return DamageSet::default();
        }
        DamageSet::from_slice(&[Rectangle::from_size(self.geo.size)])
    }
    fn kind(&self) -> Kind {
        Kind::Unspecified
    }
}

impl RenderElement<R> for MeshElement {
    fn draw(
        &self,
        frame: &mut GlesFrame<'_, '_>,
        _src: Rectangle<f64, BufferCoords>,
        dst: Rectangle<i32, Physical>,
        damage: &[Rectangle<i32, Physical>],
        _opaque: &[Rectangle<i32, Physical>],
    ) -> Result<(), GlesError> {
        let proj = *frame.projection();
        let programs = self.programs.clone();
        let tex = self.tex.tex_id();
        let mesh = self.mesh.clone();
        let blur = self.blur;
        frame.with_context(|gl| unsafe {
            let vp = viewport(gl);
            let area = [dst.loc.x as f32, dst.loc.y as f32, dst.size.w as f32, dst.size.h as f32];
            let blurred = blur.and_then(|b| programs.blur(gl, fb_rect(&proj, vp, area[0], area[1], area[2], area[3]), b));
            gl.ActiveTexture(ffi::TEXTURE0);
            gl.BindTexture(ffi::TEXTURE_2D, tex);
            for f in [ffi::TEXTURE_MIN_FILTER, ffi::TEXTURE_MAG_FILTER] {
                gl.TexParameteri(ffi::TEXTURE_2D, f, ffi::LINEAR as i32);
            }
            gl.TexParameteri(ffi::TEXTURE_2D, ffi::TEXTURE_WRAP_S, ffi::CLAMP_TO_EDGE as i32);
            gl.TexParameteri(ffi::TEXTURE_2D, ffi::TEXTURE_WRAP_T, ffi::CLAMP_TO_EDGE as i32);
            match &mesh {
                Mesh::Reveal(r) => {
                    let p = &programs.reveal;
                    gl.UseProgram(p.id);
                    gl.Uniform1i(p.u("tex"), 0);
                    gl.UniformMatrix3fv(p.u("proj"), 1, ffi::FALSE, proj.as_ptr());
                    gl.Uniform4f(p.u("rect"), area[0], area[1], area[2], area[3]);
                    gl.Uniform4f(p.u("content"), r.content[0], r.content[1], r.content[2], r.content[3]);
                    gl.Uniform4f(p.u("shape_c"), r.shape[0], r.shape[1], r.shape[2], r.shape[3]);
                    gl.Uniform1f(p.u("shape_r"), r.shape_r);
                    gl.Uniform4f(p.u("ball"), r.ball[0], r.ball[1], r.ball[2], r.ball[3]);
                    gl.Uniform1f(p.u("content_alpha"), r.content_alpha);
                    gl.Uniform1f(p.u("alpha"), r.alpha);
                    gl.Uniform4f(p.u("win"), r.win[0], r.win[1], r.win[2], r.win[3]);
                    gl.Uniform1f(p.u("win_radius"), r.win_radius);
                    gl.Uniform1f(p.u("blur_on"), if blurred.is_some() { 1.0 } else { 0.0 });
                    if let Some(b) = &blurred {
                        set_blur(gl, p, b);
                    }
                    let quad = UNIT_QUAD;
                    bind_positions(gl, p.a_pos, &quad);
                    scissored(gl, &proj, vp, dst, damage, || gl.DrawArrays(ffi::TRIANGLE_STRIP, 0, 4));
                    gl.DisableVertexAttribArray(p.a_pos);
                }
                Mesh::Shards { t, omega, zeta, alpha, origin, full, verts } => {
                    let p = &programs.shards;
                    gl.UseProgram(p.id);
                    gl.Uniform1i(p.u("tex"), 0);
                    gl.UniformMatrix3fv(p.u("proj"), 1, ffi::FALSE, proj.as_ptr());
                    gl.Uniform2f(p.u("origin"), area[0] + origin[0], area[1] + origin[1]);
                    gl.Uniform2f(p.u("full"), full[0], full[1]);
                    gl.Uniform1f(p.u("t"), *t);
                    gl.Uniform1f(p.u("omega"), *omega);
                    gl.Uniform1f(p.u("zeta"), *zeta);
                    gl.Uniform1f(p.u("alpha"), *alpha);
                    gl.BindBuffer(ffi::ARRAY_BUFFER, 0);
                    let stride = 6 * 4;
                    gl.EnableVertexAttribArray(p.a_pos);
                    gl_util::per_vertex(gl, p.a_pos);
                    gl.VertexAttribPointer(p.a_pos, 2, ffi::FLOAT, ffi::FALSE, stride, verts.as_ptr() as *const _);
                    if let Some(a) = p.a_tile {
                        gl.EnableVertexAttribArray(a);
                        gl_util::per_vertex(gl, a);
                        gl.VertexAttribPointer(a, 4, ffi::FLOAT, ffi::FALSE, stride, verts.as_ptr().add(2) as *const _);
                    }
                    let n = (verts.len() / 6) as i32;
                    scissored(gl, &proj, vp, dst, damage, || gl.DrawArrays(ffi::TRIANGLES, 0, n));
                    gl.DisableVertexAttribArray(p.a_pos);
                    if let Some(a) = p.a_tile {
                        gl.DisableVertexAttribArray(a);
                    }
                }
                Mesh::Jelly(j) => {
                    let p = &programs.jelly;
                    gl.UseProgram(p.id);
                    gl.Uniform1i(p.u("tex"), 0);
                    gl.UniformMatrix3fv(p.u("proj"), 1, ffi::FALSE, proj.as_ptr());
                    gl.Uniform4f(p.u("rect"), area[0] + j.rel[0], area[1] + j.rel[1], j.rel[2], j.rel[3]);
                    gl.Uniform1f(p.u("pad"), j.pad);
                    gl.Uniform2f(p.u("grab"), j.grab[0], j.grab[1]);
                    gl.Uniform1f(p.u("reach"), j.reach);
                    gl.Uniform4f(p.u("o12"), j.o[0][0], j.o[0][1], j.o[1][0], j.o[1][1]);
                    gl.Uniform4f(p.u("o34"), j.o[2][0], j.o[2][1], j.o[3][0], j.o[3][1]);
                    gl.Uniform2f(p.u("o5"), j.o[4][0], j.o[4][1]);
                    gl.Uniform1f(p.u("radius"), j.radius);
                    gl.Uniform1f(p.u("blur_on"), if blurred.is_some() { 1.0 } else { 0.0 });
                    if let Some(b) = &blurred {
                        set_blur(gl, p, b);
                    }
                    bind_positions(gl, p.a_pos, &programs.grid);
                    let n = (programs.grid.len() / 2) as i32;
                    scissored(gl, &proj, vp, dst, damage, || gl.DrawArrays(ffi::TRIANGLES, 0, n));
                    gl.DisableVertexAttribArray(p.a_pos);
                }
            }
            unbind(gl);
        })
    }
}

