//! Курсор оболочки — из темы xcursor (XCURSOR_THEME, XCURSOR_SIZE, как у
//! Hyprland и Delta). Программы просят фигуру по имени (cursor-shape-v1:
//! «text», «pointer», «grab»…) или присылают свою картинку-поверхность.

use std::{collections::HashMap, time::Duration};

use smithay::{
    backend::{
        allocator::Fourcc,
        renderer::element::memory::MemoryRenderBuffer,
    },
    input::pointer::CursorIcon,
    utils::{Point, Physical, Transform},
};
use xcursor::{parser::Image, CursorTheme};

/// Кадры одной фигуры; у анимированных (часики) их несколько.
struct Shape {
    frames: Vec<(Image, MemoryRenderBuffer)>,
    total_delay: u32,
}

pub struct Cursor {
    theme: CursorTheme,
    size: u32,
    shapes: HashMap<CursorIcon, Shape>,
}

impl Cursor {
    pub fn load() -> Self {
        let name = std::env::var("XCURSOR_THEME").unwrap_or_else(|_| "default".into());
        let size = std::env::var("XCURSOR_SIZE").ok().and_then(|s| s.parse().ok()).unwrap_or(24);
        Self::with_theme(&name, size)
    }

    /// Другая тема (hyprctl setcursor — так «Оформление» Delta меняет курсор).
    pub fn with_theme(name: &str, size: u32) -> Self {
        Self { theme: CursorTheme::load(name), size, shapes: HashMap::new() }
    }

    /// Картинка фигуры на этот момент времени и её «горячая точка».
    pub fn image(&mut self, icon: CursorIcon, time: Duration) -> (MemoryRenderBuffer, Point<i32, Physical>) {
        if !self.shapes.contains_key(&icon) {
            let shape = self.load_shape(icon).or_else(|| self.load_shape(CursorIcon::Default)).unwrap_or_else(fallback);
            self.shapes.insert(icon, shape);
        }
        let shape = &self.shapes[&icon];
        let mut ms = if shape.total_delay > 0 { time.as_millis() as u32 % shape.total_delay } else { 0 };
        for (image, buffer) in &shape.frames {
            if ms < image.delay || shape.total_delay == 0 {
                return (buffer.clone(), (image.xhot as i32, image.yhot as i32).into());
            }
            ms -= image.delay;
        }
        let (image, buffer) = &shape.frames[0];
        (buffer.clone(), (image.xhot as i32, image.yhot as i32).into())
    }

    fn load_shape(&self, icon: CursorIcon) -> Option<Shape> {
        // в старых темах фигуры зовутся по-иксовому (left_ptr, xterm): пробуем все имена
        let path = std::iter::once(icon.name())
            .chain(icon.alt_names().iter().copied())
            .find_map(|n| self.theme.load_icon(n))?;
        let data = std::fs::read(path).ok()?;
        let images = xcursor::parser::parse_xcursor(&data)?;
        // ближайший к нужному размер, все кадры этого размера
        let nearest = images.iter().min_by_key(|i| (i.size as i32 - self.size as i32).abs())?;
        let (w, h) = (nearest.width, nearest.height);
        let frames: Vec<_> = images
            .iter()
            .filter(|i| i.width == w && i.height == h)
            .map(|i| (i.clone(), buffer(i)))
            .collect();
        let total_delay = frames.iter().map(|(i, _)| i.delay).sum();
        Some(Shape { frames, total_delay })
    }
}

fn buffer(image: &Image) -> MemoryRenderBuffer {
    // pixels_rgba в xcursor — байты B,G,R,A подряд, это Argb8888 в little-endian
    MemoryRenderBuffer::from_slice(
        &image.pixels_rgba,
        Fourcc::Argb8888,
        (image.width as i32, image.height as i32),
        1,
        Transform::Normal,
        None,
    )
}

/// Темы нет вовсе — белая стрелка 16×16 с тёмным краем, нарисованная здесь.
fn fallback() -> Shape {
    let n = 16u32;
    let mut px = vec![0u8; (n * n * 4) as usize];
    for y in 0..n {
        for x in 0..=y.min(11) {
            let edge = x == 0 || x == y.min(11) || y == n - 1;
            let i = ((y * n + x) * 4) as usize;
            let c = if edge { 0x20 } else { 0xff };
            px[i..i + 4].copy_from_slice(&[c, c, c, 0xff]);
        }
    }
    let image = Image { size: n, width: n, height: n, xhot: 0, yhot: 0, delay: 0, pixels_rgba: px, pixels_argb: vec![] };
    let b = buffer(&image);
    Shape { frames: vec![(image, b)], total_delay: 0 }
}
