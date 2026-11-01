//! Эффекты окон: скругление, рамка, тень, размытие, анимации появления и
//! закрытия, «желе» при перетаскивании. Анимации считает сам композитор на
//! каждом кадре монитора — окно и его деформация всегда из одного кадра, без
//! копии в отдельной программе и её задержки.

pub mod elements;
mod gl;
mod shaders;

use std::{collections::HashMap, rc::Rc, time::Instant};

use smithay::{
    backend::renderer::{
        element::Id,
        gles::{element::PixelShaderElement, GlesTexture},
        utils::CommitCounter,
    },
    desktop::Window,
    utils::{Logical, Rectangle},
};

use crate::settings::Settings;
pub use elements::{BlurParams, Glass, Programs};

/// Пружина: жёсткость при единичной массе и доля затухания.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Spring {
    pub k: f32,
    pub zeta: f32,
}

impl Spring {
    pub fn omega(self) -> f32 {
        self.k.sqrt()
    }
    /// От 0 к 1 за время x, с: чем меньше затухание, тем сильнее перелёт.
    pub fn value(self, x: f32) -> f32 {
        if x <= 0.0 {
            return 0.0;
        }
        let w = self.omega();
        if self.zeta >= 1.0 {
            return 1.0 - (-w * x).exp() * (1.0 + w * x);
        }
        let wd = w * (1.0 - self.zeta * self.zeta).sqrt();
        1.0 - (-self.zeta * w * x).exp() * ((wd * x).cos() + self.zeta * w / wd * (wd * x).sin())
    }
    /// Когда отклонение меньше полупроцента.
    pub fn settle(self) -> f32 {
        5.3 / (self.zeta.min(1.0) * self.omega())
    }
}

/// Движение стиля. Material You — токены Material 3 Expressive (движение
/// «expressive»): быстрые пространственные пружины с заметным перелётом.
pub fn motion(style: Style) -> Motion {
    match style {
        Style::Material => Motion {
            open: Spring { k: 800.0, zeta: 0.6 },
            shards: Spring { k: 380.0, zeta: 0.7 },
            close: Spring { k: 3800.0, zeta: 1.0 },
            geom: Spring { k: 800.0, zeta: 0.6 },
            ws: Spring { k: 380.0, zeta: 0.8 },
        },
        Style::Liquid => Motion {
            open: Spring { k: 240.0, zeta: 0.62 },
            shards: Spring { k: 170.0, zeta: 0.68 },
            close: Spring { k: 700.0, zeta: 1.0 },
            geom: Spring { k: 260.0, zeta: 0.68 },
            ws: Spring { k: 200.0, zeta: 0.82 },
        },
        _ => Motion {
            open: Spring { k: 280.0, zeta: 0.72 },
            shards: Spring { k: 190.0, zeta: 0.74 },
            close: Spring { k: 800.0, zeta: 1.0 },
            geom: Spring { k: 300.0, zeta: 0.86 },
            ws: Spring { k: 240.0, zeta: 0.92 },
        },
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Motion {
    pub open: Spring,
    pub shards: Spring,
    pub close: Spring,
    pub geom: Spring,
    pub ws: Spring,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Style {
    #[default]
    Delta,
    Gnome,
    Liquid,
    Material,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Open {
    /// окно собирается из плиток
    Assemble,
    /// растёт из капли изнутри, как окно приложений по кнопке «Начать»
    Inside,
    #[default]
    Popin,
    Slide,
    Fade,
}

impl Open {
    pub fn parse(s: &str) -> Self {
        match s {
            "assemble" => Self::Assemble,
            "inside" => Self::Inside,
            "slide" => Self::Slide,
            "fade" => Self::Fade,
            _ => Self::Popin,
        }
    }
}

/// Значения настроек, нужные на кадре.
#[derive(Debug, Clone, PartialEq)]
pub struct Params {
    pub style: Style,
    pub radius: f32,
    pub border: f32,
    pub shadow: f32,
    pub accent: [f32; 3],
    pub blur_on: bool,
    pub blur: BlurParams,
    pub ignore_alpha: f32,
    pub lens: f32,
    pub animations: bool,
    pub open: Open,
    pub close: Open,
    /// множитель времени появления и закрытия окон (больше — медленнее)
    pub time: f32,
    /// множитель остальных анимаций: сдвиги, смена стола
    pub global_time: f32,
    pub jelly: f32,
    pub motion: Motion,
}

impl Params {
    pub fn from_settings(s: &Settings) -> Self {
        let a = &s.appearance;
        let w = &s.windows;
        let style = match a.style.as_str() {
            "gnome" => Style::Gnome,
            "liquid" => Style::Liquid,
            "material" => Style::Material,
            _ => Style::Delta,
        };
        let frost = a.frost.clamp(0.0, 1.0);
        // те же размеры размытия, что были у правил delta-apply для Hyprland
        let size = match style {
            Style::Liquid => 3.0 + frost * 11.0,
            _ => 2.0 + frost * 8.0,
        };
        let passes = if frost < 0.3 { 2 } else if frost < 0.75 { 3 } else { 4 };
        let ignore_alpha = match style {
            Style::Liquid => (0.08 + 0.26 * frost).min(0.2).max(0.08),
            _ => 0.35,
        };
        Self {
            style,
            radius: w.rounding.clamp(0, 40) as f32,
            border: w.border.clamp(0, 10) as f32,
            shadow: 18.0,
            accent: parse_hex(&a.accent).unwrap_or([0.486, 0.361, 1.0]),
            blur_on: w.blur && matches!(style, Style::Delta | Style::Liquid),
            blur: BlurParams { passes, offset: 1.0 + size * 0.22, saturation: 1.17 },
            ignore_alpha,
            lens: if style == Style::Liquid { 34.0 } else { 0.0 },
            animations: w.animations,
            open: Open::parse(&w.open_anim),
            close: Open::parse(w.close_anim.as_deref().unwrap_or(&w.open_anim)),
            time: (w.anim_speed * w.open_speed).clamp(0.1, 16.0),
            global_time: w.anim_speed.clamp(0.1, 8.0),
            jelly: if w.animations { w.jelly.clamp(0.0, 1.7) } else { 0.0 },
            motion: motion(style),
        }
    }

    pub fn pad(&self) -> f32 {
        self.border + self.shadow
    }

    /// Сколько идёт появление или закрытие (до множителя скорости), с.
    pub fn duration(&self, kind: Open, opening: bool) -> f32 {
        if !opening && kind != Open::Assemble && kind != Open::Inside {
            return self.motion.close.settle().max(0.12);
        }
        match kind {
            Open::Assemble => self.motion.shards.settle() + 0.2,
            Open::Inside => self.motion.open.settle().max(0.3),
            Open::Popin | Open::Slide => self.motion.open.settle(),
            Open::Fade => 0.24,
        }
    }
}

fn parse_hex(s: &str) -> Option<[f32; 3]> {
    let s = s.strip_prefix('#')?;
    if s.len() != 6 {
        return None;
    }
    let n = u32::from_str_radix(s, 16).ok()?;
    Some([((n >> 16) & 255) as f32 / 255.0, ((n >> 8) & 255) as f32 / 255.0, (n & 255) as f32 / 255.0])
}

/// «Желе»: пять колец отстают от окна на пружинах; перенесено из Delta 0.6.
#[derive(Debug, Clone)]
pub struct Jelly {
    /// где держат, от левого верхнего угла окна
    pub grab: (f32, f32),
    rings: [[f32; 4]; 5],
    last: Instant,
    pub released: Option<Instant>,
    /// окно упало на зону: кончить сразу
    pub stop: bool,
}

impl Jelly {
    pub fn new(grab: (f32, f32), at: (f32, f32), now: Instant) -> Self {
        Self { grab, rings: [[at.0, at.1, 0.0, 0.0]; 5], last: now, released: None, stop: false }
    }

    /// Шаг за прошедшее время. Смещения колец и признак «улеглось».
    pub fn step(&mut self, target: (f32, f32), diag: f32, strength: f32, now: Instant) -> ([[f32; 2]; 5], bool) {
        let dt = now.saturating_duration_since(self.last).as_secs_f32().min(1.0 / 30.0);
        self.last = now;
        let kf = 1.35 - 0.4 * strength;
        let zeta = 0.72 - 0.17 * strength;
        let lim = 0.32 * diag;
        let mut calm = true;
        let mut out = [[0.0; 2]; 5];
        // при монитор быстрее 200 Гц шаг и так мал; два полушага держат устойчивость на просадках
        for (i, p) in self.rings.iter_mut().enumerate() {
            let r = (i + 1) as f32 / 5.0;
            let k = (560.0 - 430.0 * r) * kf;
            let c = 2.0 * k.sqrt() * zeta;
            for _ in 0..2 {
                let h = dt / 2.0;
                p[2] += (k * (target.0 - p[0]) - c * p[2]) * h;
                p[3] += (k * (target.1 - p[1]) - c * p[3]) * h;
                p[0] += p[2] * h;
                p[1] += p[3] * h;
            }
            let (mut ox, mut oy) = (p[0] - target.0, p[1] - target.1);
            let len = ox.hypot(oy);
            if len > lim {
                ox *= lim / len;
                oy *= lim / len;
                p[0] = target.0 + ox;
                p[1] = target.1 + oy;
            }
            if len > 0.4 || p[2].abs() + p[3].abs() > 8.0 {
                calm = false;
            }
            out[i] = [ox, oy];
        }
        (out, calm)
    }
}

/// Что окно показывает сейчас помимо обычной отрисовки.
#[derive(Debug, Default)]
pub struct WinFx {
    /// окно только что появилось — анимация начнётся с первого кадра
    pub opening: bool,
    pub open_start: Option<Instant>,
    /// откуда едет окно (разворот, край, возврат)
    pub geom: Option<(Rectangle<f64, Logical>, Instant)>,
    pub jelly: Option<Jelly>,
    pub tex: Option<(GlesTexture, (i32, i32))>,
    pub shards: Option<(Rc<Vec<f32>>, (i32, i32))>,
    pub mesh_id: Option<Id>,
    pub backdrop_id: Option<Id>,
    pub commit: CommitCounter,
    pub decor: Option<(PixelShaderElement, DecorKey)>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct DecorKey {
    pub area: Rectangle<i32, Logical>,
    pub active: bool,
    pub radius: f32,
    pub border: f32,
    pub color: [f32; 3],
    pub scale: u32,
}

/// Закрытое окно: снимок доигрывает анимацию.
#[derive(Debug)]
pub struct Closing {
    pub tex: GlesTexture,
    pub tex_size: (i32, i32),
    /// прямоугольник окна (логический, глобальный)
    pub rect: Rectangle<i32, Logical>,
    pub scale: f64,
    pub start: Instant,
    pub kind: Open,
    pub id: Id,
    pub commit: CommitCounter,
    pub shards: Option<Rc<Vec<f32>>>,
}

/// Смена рабочего стола: кто уезжает и в какую сторону.
#[derive(Debug)]
pub struct WsAnim {
    pub old: Vec<Window>,
    pub dir: f32,
    pub start: Instant,
}

/// Состояние эффектов композитора.
#[derive(Debug, Default)]
pub struct Fx {
    pub programs: Option<Rc<Programs>>,
    pub failed: bool,
    pub closing: Vec<Closing>,
    pub ws: HashMap<String, WsAnim>,
    /// изменилось ли хоть что-то на экране (для панелей на стекле)
    pub scene: CommitCounter,
    pub scene_hash: u64,
}

/// Плитки сборки: на каждую — 6 вершин по (x, y, cx, cy, seed, delay).
/// Физические пиксели снимка; середина задерживается меньше краёв.
pub fn build_shards(w: i32, h: i32, tile: f32) -> Rc<Vec<f32>> {
    let (fw, fh) = (w as f32, h as f32);
    let nx = ((fw / tile).round() as usize).clamp(3, 40);
    let ny = ((fh / tile).round() as usize).clamp(3, 30);
    let (tw, th) = (fw / nx as f32, fh / ny as f32);
    let mut v = Vec::with_capacity(nx * ny * 36);
    let far = (fw * fw + fh * fh).sqrt() * 0.5;
    for y in 0..ny {
        for x in 0..nx {
            let (x0, y0) = (x as f32 * tw, y as f32 * th);
            let (x1, y1) = (x0 + tw, y0 + th);
            let (cx, cy) = (x0 + tw * 0.5, y0 + th * 0.5);
            // псевдослучайно, но одинаково для каждого окна этого размера
            let seed = {
                let s = ((x as f32 + 1.0) * 12.9898 + (y as f32 + 1.0) * 78.233).sin() * 43758.547;
                s - s.floor()
            };
            let dist = ((cx - fw * 0.5).powi(2) + (cy - fh * 0.5).powi(2)).sqrt() / far;
            let delay = dist * 0.16 + seed * 0.05;
            for (px, py) in [(x0, y0), (x1, y0), (x0, y1), (x1, y0), (x1, y1), (x0, y1)] {
                v.extend_from_slice(&[px, py, cx, cy, seed, delay]);
            }
        }
    }
    Rc::new(v)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn spring_goes_to_one() {
        let s = Spring { k: 800.0, zeta: 0.6 };
        assert_eq!(s.value(0.0), 0.0);
        assert!((s.value(s.settle()) - 1.0).abs() < 0.01);
        // Material: заметный перелёт
        let peak = (1..100).map(|i| s.value(i as f32 * 0.005)).fold(0.0, f32::max);
        assert!(peak > 1.05);
    }

    #[test]
    fn shards_cover_snapshot() {
        let v = build_shards(800, 600, 64.0);
        assert_eq!(v.len() % 36, 0);
        let max_x = v.chunks(6).map(|c| c[0]).fold(0.0, f32::max);
        assert!((max_x - 800.0).abs() < 0.01);
    }
}
