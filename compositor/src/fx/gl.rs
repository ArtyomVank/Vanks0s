//! Прямая работа с GL внутри кадра: свои программы и цепочка размытия.
//! Smithay ждёт, что после нас состояние GL прежнее (см. `restore`).

use std::{collections::HashMap, ffi::CString, ptr};

use smithay::backend::renderer::gles::ffi::{self, Gles2};

/// Своя программа: имена uniform и attribute разрешаются один раз.
#[derive(Debug)]
pub struct Raw {
    pub id: u32,
    uniforms: HashMap<&'static str, i32>,
    pub a_pos: u32,
    pub a_tile: Option<u32>,
}

unsafe fn compile(gl: &Gles2, kind: u32, src: &str) -> Result<u32, String> {
    let shader = gl.CreateShader(kind);
    let c = CString::new(src).map_err(|e| e.to_string())?;
    gl.ShaderSource(shader, 1, &c.as_ptr(), ptr::null());
    gl.CompileShader(shader);
    let mut ok = 0;
    gl.GetShaderiv(shader, ffi::COMPILE_STATUS, &mut ok);
    if ok == 0 {
        let mut log = vec![0u8; 2048];
        let mut len = 0;
        gl.GetShaderInfoLog(shader, 2048, &mut len, log.as_mut_ptr() as *mut _);
        return Err(String::from_utf8_lossy(&log[..len.max(0) as usize]).into_owned());
    }
    Ok(shader)
}

impl Raw {
    pub unsafe fn new(gl: &Gles2, vert: &str, frag: &str, uniforms: &[&'static str]) -> Result<Self, String> {
        let v = compile(gl, ffi::VERTEX_SHADER, vert)?;
        let f = compile(gl, ffi::FRAGMENT_SHADER, frag)?;
        let id = gl.CreateProgram();
        gl.AttachShader(id, v);
        gl.AttachShader(id, f);
        gl.LinkProgram(id);
        gl.DeleteShader(v);
        gl.DeleteShader(f);
        let mut ok = 0;
        gl.GetProgramiv(id, ffi::LINK_STATUS, &mut ok);
        if ok == 0 {
            return Err("программа не собралась".into());
        }
        let mut map = HashMap::new();
        for name in uniforms {
            let c = CString::new(*name).unwrap();
            map.insert(*name, gl.GetUniformLocation(id, c.as_ptr()));
        }
        let a_pos = gl.GetAttribLocation(id, c"a_pos".as_ptr());
        let a_tile = gl.GetAttribLocation(id, c"a_tile".as_ptr());
        Ok(Self { id, uniforms: map, a_pos: a_pos as u32, a_tile: (a_tile >= 0).then_some(a_tile as u32) })
    }

    pub fn u(&self, name: &str) -> i32 {
        self.uniforms.get(name).copied().unwrap_or(-1)
    }
}

/// Куда в кадр смотрит прямоугольник монитора: (x0, y0, x1, y1), матрица кадра
/// учитывает поворот монитора и перевёрнутый кадр окна отладки.
pub fn fb_rect(proj: &[f32; 9], vp: [i32; 4], x: f32, y: f32, w: f32, h: f32) -> [f32; 4] {
    let map = |x: f32, y: f32| {
        let nx = proj[0] * x + proj[3] * y + proj[6];
        let ny = proj[1] * x + proj[4] * y + proj[7];
        ((nx + 1.0) * 0.5 * vp[2] as f32 + vp[0] as f32, (ny + 1.0) * 0.5 * vp[3] as f32 + vp[1] as f32)
    };
    let (ax, ay) = map(x, y);
    let (bx, by) = map(x + w, y + h);
    [ax.min(bx), ay.min(by), ax.max(bx), ay.max(by)]
}

/// Знак оси Y: как идёт кадр относительно монитора (окно отладки перевёрнуто).
pub fn y_sign(proj: &[f32; 9]) -> f32 {
    if proj[4] * proj[4] >= proj[3] * proj[3] {
        // ось монитора вниз: в кадре DRM это рост, в окне отладки — убывание
        if proj[4] > 0.0 { 1.0 } else { -1.0 }
    } else if proj[3] > 0.0 {
        1.0
    } else {
        -1.0
    }
}

pub unsafe fn viewport(gl: &Gles2) -> [i32; 4] {
    let mut vp = [0i32; 4];
    gl.GetIntegerv(ffi::VIEWPORT, vp.as_mut_ptr());
    vp
}

/// Вернуть то, что Smithay считает состоянием по умолчанию внутри кадра.
pub unsafe fn restore(gl: &Gles2, fbo: u32, vp: [i32; 4]) {
    gl.BindFramebuffer(ffi::FRAMEBUFFER, fbo);
    gl.Viewport(vp[0], vp[1], vp[2], vp[3]);
    gl.Scissor(vp[0], vp[1], vp[2], vp[3]);
    gl.Enable(ffi::SCISSOR_TEST);
    gl.Enable(ffi::BLEND);
    gl.BlendFunc(ffi::ONE, ffi::ONE_MINUS_SRC_ALPHA);
    gl.ActiveTexture(ffi::TEXTURE1);
    gl.BindTexture(ffi::TEXTURE_2D, 0);
    gl.ActiveTexture(ffi::TEXTURE0);
    gl.BindTexture(ffi::TEXTURE_2D, 0);
    gl.BindBuffer(ffi::ARRAY_BUFFER, 0);
}

pub const UNIT_QUAD: [f32; 8] = [0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0];

/// Smithay рисует с делителем на своих атрибутах, а он хранится по номеру
/// атрибута: без сброса наши вершины схлопнулись бы в одну.
pub unsafe fn per_vertex(gl: &Gles2, attr: u32) {
    if gl.VertexAttribDivisor.is_loaded() {
        gl.VertexAttribDivisor(attr, 0);
    }
}

pub unsafe fn bind_positions(gl: &Gles2, attr: u32, data: &[f32]) {
    gl.BindBuffer(ffi::ARRAY_BUFFER, 0);
    gl.EnableVertexAttribArray(attr);
    per_vertex(gl, attr);
    gl.VertexAttribPointer(attr, 2, ffi::FLOAT, ffi::FALSE, 0, data.as_ptr() as *const _);
}

/// Нарисованное выше: что получила программа, чтобы взять размытый фон.
#[derive(Debug, Clone, Copy, Default)]
pub struct Blurred {
    pub tex: u32,
    /// frag → uv: (x0, y0, kx, ky)
    pub map: [f32; 4],
    pub clamp: [f32; 4],
}

struct Level {
    fbo: u32,
    tex: u32,
    w: i32,
    h: i32,
}

impl std::fmt::Debug for Level {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Level({}x{})", self.w, self.h)
    }
}

/// Цепочка текстур размытия: каждая вдвое меньше прошлой; общая на всех.
#[derive(Debug, Default)]
pub struct Chain {
    levels: Vec<Level>,
    size: (i32, i32),
}

const LEVELS: usize = 5;

impl Chain {
    unsafe fn ensure(&mut self, gl: &Gles2, w: i32, h: i32) {
        if self.size.0 >= w && self.size.1 >= h && !self.levels.is_empty() {
            return;
        }
        for l in self.levels.drain(..) {
            gl.DeleteFramebuffers(1, &l.fbo);
            gl.DeleteTextures(1, &l.tex);
        }
        self.size = (self.size.0.max(w), self.size.1.max(h));
        for i in 0..LEVELS {
            let lw = (self.size.0 >> (i + 1)).max(1);
            let lh = (self.size.1 >> (i + 1)).max(1);
            let (mut tex, mut fbo) = (0, 0);
            gl.GenTextures(1, &mut tex);
            gl.BindTexture(ffi::TEXTURE_2D, tex);
            gl.TexImage2D(ffi::TEXTURE_2D, 0, ffi::RGBA8 as i32, lw, lh, 0, ffi::RGBA, ffi::UNSIGNED_BYTE, ptr::null());
            gl.TexParameteri(ffi::TEXTURE_2D, ffi::TEXTURE_MIN_FILTER, ffi::LINEAR as i32);
            gl.TexParameteri(ffi::TEXTURE_2D, ffi::TEXTURE_MAG_FILTER, ffi::LINEAR as i32);
            gl.TexParameteri(ffi::TEXTURE_2D, ffi::TEXTURE_WRAP_S, ffi::CLAMP_TO_EDGE as i32);
            gl.TexParameteri(ffi::TEXTURE_2D, ffi::TEXTURE_WRAP_T, ffi::CLAMP_TO_EDGE as i32);
            gl.GenFramebuffers(1, &mut fbo);
            gl.BindFramebuffer(ffi::FRAMEBUFFER, fbo);
            gl.FramebufferTexture2D(ffi::FRAMEBUFFER, ffi::COLOR_ATTACHMENT0, ffi::TEXTURE_2D, tex, 0);
            self.levels.push(Level { fbo, tex, w: lw, h: lh });
        }
    }

    /// Размыть прямоугольник текущего кадра (координаты кадра). Состояние
    /// возвращается; `Blurred` действует до следующего вызова.
    pub unsafe fn run(
        &mut self,
        gl: &Gles2,
        down: &Raw,
        up: &Raw,
        rect: [f32; 4],
        passes: usize,
        offset: f32,
    ) -> Option<Blurred> {
        let vp = viewport(gl);
        let x0 = (rect[0].floor() as i32).clamp(0, vp[2]);
        let y0 = (rect[1].floor() as i32).clamp(0, vp[3]);
        let x1 = (rect[2].ceil() as i32).clamp(0, vp[2]);
        let y1 = (rect[3].ceil() as i32).clamp(0, vp[3]);
        let (w, h) = (x1 - x0, y1 - y0);
        if w <= 0 || h <= 0 {
            return None;
        }
        let mut prev = 0;
        gl.GetIntegerv(ffi::FRAMEBUFFER_BINDING, &mut prev);
        let prev = prev as u32;
        self.ensure(gl, vp[2], vp[3]);

        let passes = passes.clamp(1, LEVELS - 1);
        let dims: Vec<(i32, i32)> = (0..=passes).map(|i| ((w >> (i + 1)).max(1), (h >> (i + 1)).max(1))).collect();

        gl.Disable(ffi::SCISSOR_TEST);
        gl.Disable(ffi::BLEND);
        gl.ActiveTexture(ffi::TEXTURE0);

        // кадр → первый уровень
        gl.BindFramebuffer(ffi::READ_FRAMEBUFFER, prev);
        gl.BindFramebuffer(ffi::DRAW_FRAMEBUFFER, self.levels[0].fbo);
        gl.BlitFramebuffer(x0, y0, x1, y1, 0, 0, dims[0].0, dims[0].1, ffi::COLOR_BUFFER_BIT, ffi::LINEAR);

        let quad = UNIT_QUAD;
        let pass = |prog: &Raw, from: usize, to: usize, levels: &[Level]| {
            let (fw, fh) = dims[from];
            let (tw, th) = dims[to];
            let src = &levels[from];
            let umax = [fw as f32 / src.w as f32, fh as f32 / src.h as f32];
            gl.BindFramebuffer(ffi::FRAMEBUFFER, levels[to].fbo);
            gl.Viewport(0, 0, tw, th);
            gl.UseProgram(prog.id);
            gl.BindTexture(ffi::TEXTURE_2D, src.tex);
            gl.Uniform1i(prog.u("tex"), 0);
            gl.Uniform2f(prog.u("uv_max"), umax[0], umax[1]);
            gl.Uniform2f(prog.u("halfpixel"), 0.5 / src.w as f32, 0.5 / src.h as f32);
            gl.Uniform1f(prog.u("offset"), offset);
            bind_positions(gl, prog.a_pos, &quad);
            gl.DrawArrays(ffi::TRIANGLE_STRIP, 0, 4);
            gl.DisableVertexAttribArray(prog.a_pos);
        };
        for i in 1..=passes {
            pass(down, i - 1, i, &self.levels);
        }
        for i in (1..=passes).rev() {
            pass(up, i, i - 1, &self.levels);
        }

        let (uw, uh) = dims[0];
        let l = &self.levels[0];
        let kx = uw as f32 / l.w as f32 / w as f32;
        let ky = uh as f32 / l.h as f32 / h as f32;
        let result = Blurred {
            tex: l.tex,
            map: [x0 as f32, y0 as f32, kx, ky],
            clamp: [0.5 / l.w as f32, 0.5 / l.h as f32, (uw as f32 - 0.5) / l.w as f32, (uh as f32 - 0.5) / l.h as f32],
        };
        gl.UseProgram(0);
        restore(gl, prev, vp);
        Some(result)
    }
}
