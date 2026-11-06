//! HDR в сессии Delta. Кадр рисуется как обычно, но в отдельную текстуру с
//! плавающей точкой, а на монитор уходит одним проходом шейдера: PQ и BT.2020.
//! Без HDR ничего этого нет и кадр идёт прежним путём.

use std::{cell::Cell, path::PathBuf};

use smithay::{
    backend::{
        allocator::Fourcc,
        renderer::{
            damage::OutputDamageTracker,
            element::{Element, Id, Kind, RenderElement, RenderElementStates, UnderlyingStorage},
            gles::{GlesError, GlesFrame, GlesRenderer, GlesTarget, GlesTexProgram, GlesTexture, Uniform, UniformName, UniformType},
            utils::{CommitCounter, DamageBag, DamageSet, OpaqueRegions},
            Bind, Offscreen,
        },
    },
    output::Output,
    utils::{Buffer as BufferCoords, Physical, Rectangle, Scale, Size, Transform},
};

use crate::{config, fx::shaders};

/// Белый обычной картинки по BT.2408 — при яркости 100 % в настройках.
pub const SDR_WHITE: f32 = 203.0;

/// Какая яркость белого сейчас у монитора; None — монитор обычный.
struct OutputWhite(Cell<Option<f32>>);

pub fn output_white(output: &Output) -> Option<f32> {
    output.user_data().get::<OutputWhite>().and_then(|w| w.0.get())
}

/// Насыщенность обычной картинки в HDR (1 — как есть).
struct OutputSaturation(Cell<f32>);

pub fn output_saturation(output: &Output) -> f32 {
    output.user_data().get::<OutputSaturation>().map_or(1.0, |s| s.0.get())
}

pub fn set_output_saturation(output: &Output, saturation: f32) {
    output.user_data().insert_if_missing(|| OutputSaturation(Cell::new(1.0)));
    if let Some(s) = output.user_data().get::<OutputSaturation>() {
        s.0.set(saturation);
    }
}

pub fn set_output_white(output: &Output, white: Option<f32>) {
    output.user_data().insert_if_missing(|| OutputWhite(Cell::new(None)));
    if let Some(w) = output.user_data().get::<OutputWhite>() {
        w.0.set(white);
    }
}

/// Отметка «HDR выключен сочетанием клавиш»: монитор мог погаснуть, и включать
/// HDR при следующем запуске нельзя, пока его не включат в настройках.
fn switched_off_mark() -> Option<PathBuf> {
    let home = std::env::var_os("HOME")?;
    Some(PathBuf::from(home).join(".local/state/delta/hdr-off"))
}

pub fn switched_off() -> bool {
    switched_off_mark().is_some_and(|p| p.exists())
}

pub fn set_switched_off(off: bool) {
    let Some(mark) = switched_off_mark() else { return };
    if off {
        if let Some(dir) = mark.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let _ = std::fs::write(mark, "");
    } else {
        let _ = std::fs::remove_file(mark);
    }
}

#[derive(Debug)]
pub struct HdrPass {
    id: Id,
    texture: GlesTexture,
    tracker: OutputDamageTracker,
    damage: DamageBag<i32, Physical>,
    program: GlesTexProgram,
    size: Size<i32, Physical>,
    scale: Scale<f64>,
    /// первый кадр рисуется целиком, дальше в текстуре лежит предыдущий
    age: usize,
    /// яркость белого обычной картинки, кд/м²
    pub white: f32,
    /// её насыщенность
    saturation: f32,
}

impl HdrPass {
    pub fn new(renderer: &mut GlesRenderer, size: Size<i32, Physical>, scale: Scale<f64>, white: f32) -> Result<Self, String> {
        let buffer = size.to_logical(1).to_buffer(1, Transform::Normal);
        let texture = [Fourcc::Abgr16161616f, Fourcc::Abgr2101010]
            .iter()
            .find_map(|format| Offscreen::<GlesTexture>::create_buffer(renderer, *format, buffer).ok())
            .ok_or("видеокарта не даёт текстуру HDR")?;
        let program = renderer
            .compile_custom_texture_shader(shaders::HDR_OUT, &[UniformName::new("white", UniformType::_1f), UniformName::new("sat", UniformType::_1f)])
            .map_err(|e| format!("шейдер HDR: {e:?}"))?;
        Ok(Self {
            id: Id::new(),
            texture,
            tracker: OutputDamageTracker::new(size, scale, Transform::Normal),
            damage: DamageBag::new(4),
            program,
            size,
            scale,
            age: 0,
            white,
            saturation: 1.0,
        })
    }

    /// Текстура ещё подходит под этот размер и масштаб монитора?
    pub fn fits(&self, size: Size<i32, Physical>, scale: Scale<f64>) -> bool {
        self.size == size && self.scale == scale
    }

    pub fn set_white(&mut self, white: f32) {
        if (self.white - white).abs() > f32::EPSILON {
            self.white = white;
            self.damage.add([Rectangle::from_size(self.size)]);
        }
    }

    pub fn set_saturation(&mut self, saturation: f32) {
        if (self.saturation - saturation).abs() > f32::EPSILON {
            self.saturation = saturation;
            self.damage.add([Rectangle::from_size(self.size)]);
        }
    }

    /// Нарисовать кадр в текстуру. Какие поверхности попали на экран — в ответе.
    pub fn render<E: RenderElement<GlesRenderer>>(
        &mut self,
        renderer: &mut GlesRenderer,
        elements: &[E],
    ) -> Result<RenderElementStates, String> {
        let mut target: GlesTarget<'_> = renderer.bind(&mut self.texture).map_err(|e| format!("{e:?}"))?;
        let result = self
            .tracker
            .render_output(renderer, &mut target, self.age, elements, config::BACKGROUND)
            .map_err(|e| format!("{e:?}"))?;
        if let Some(damage) = result.damage {
            self.damage.add(damage.iter().copied());
        }
        self.age = 1;
        Ok(result.states)
    }

    pub fn frame(&self) -> HdrFrame<'_> {
        HdrFrame { pass: self }
    }
}

/// Готовая текстура кадра как единственный элемент для монитора.
#[derive(Debug)]
pub struct HdrFrame<'a> {
    pass: &'a HdrPass,
}

impl Element for HdrFrame<'_> {
    fn id(&self) -> &Id {
        &self.pass.id
    }
    fn current_commit(&self) -> CommitCounter {
        self.pass.damage.current_commit()
    }
    fn src(&self) -> Rectangle<f64, BufferCoords> {
        Rectangle::from_size(self.pass.size.to_logical(1).to_buffer(1, Transform::Normal).to_f64())
    }
    fn geometry(&self, _scale: Scale<f64>) -> Rectangle<i32, Physical> {
        Rectangle::from_size(self.pass.size)
    }
    fn damage_since(&self, _scale: Scale<f64>, commit: Option<CommitCounter>) -> DamageSet<i32, Physical> {
        self.pass
            .damage
            .damage_since(commit)
            .unwrap_or_else(|| DamageSet::from_slice(&[Rectangle::from_size(self.pass.size)]))
    }
    fn opaque_regions(&self, _scale: Scale<f64>) -> OpaqueRegions<i32, Physical> {
        OpaqueRegions::from_slice(&[Rectangle::from_size(self.pass.size)])
    }
    fn kind(&self) -> Kind {
        Kind::Unspecified
    }
}

impl RenderElement<GlesRenderer> for HdrFrame<'_> {
    fn draw(
        &self,
        frame: &mut GlesFrame<'_, '_>,
        src: Rectangle<f64, BufferCoords>,
        dst: Rectangle<i32, Physical>,
        damage: &[Rectangle<i32, Physical>],
        opaque_regions: &[Rectangle<i32, Physical>],
    ) -> Result<(), GlesError> {
        frame.render_texture_from_to(
            &self.pass.texture,
            src,
            dst,
            damage,
            opaque_regions,
            Transform::Normal,
            1.0,
            Some(&self.pass.program),
            &[Uniform::new("white", self.pass.white), Uniform::new("sat", self.pass.saturation)],
        )
    }

    fn underlying_storage(&self, _renderer: &mut GlesRenderer) -> Option<UnderlyingStorage<'_>> {
        None
    }
}
