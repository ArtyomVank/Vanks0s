//! wp_color_manager_v1: программа говорит, в каком цвете её кадр, и узнаёт,
//! какой цвет нужен монитору. Без этого протокола HDR виден только как обычная
//! картинка: игре и видео не на что опереться. Глобальный объект появляется,
//! когда HDR включают впервые: обычная сессия ведёт себя как раньше.

use std::sync::Mutex;

use smithay::{
    output::Output,
    reexports::{
        wayland_protocols::wp::color_management::v1::server::{
            wp_color_management_output_v1::{self, WpColorManagementOutputV1},
            wp_color_management_surface_feedback_v1::{self, WpColorManagementSurfaceFeedbackV1},
            wp_color_management_surface_v1::{self, WpColorManagementSurfaceV1},
            wp_color_manager_v1::{self, Feature, Primaries, RenderIntent, TransferFunction, WpColorManagerV1},
            wp_image_description_creator_icc_v1::{self, WpImageDescriptionCreatorIccV1},
            wp_image_description_creator_params_v1::{self, WpImageDescriptionCreatorParamsV1},
            wp_image_description_info_v1::WpImageDescriptionInfoV1,
            wp_image_description_v1::{self, WpImageDescriptionV1},
        },
        wayland_server::{
            backend::{ClientId, GlobalId},
            protocol::{wl_output::WlOutput, wl_surface::WlSurface},
            Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
        },
    },
    wayland::compositor::{with_states, Cacheable},
};

use crate::{hdr, Shell};

/// Как закодирован цвет поверхности.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tf {
    /// гамма 2.2 и sRGB: как любое обычное окно
    Gamma22,
    Pq,
    /// линейный scRGB: 1.0 — 80 кд/м²
    Linear,
    Bt1886,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Gamut {
    Srgb,
    Bt2020,
    DisplayP3,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ColorDesc {
    pub tf: Tf,
    pub gamut: Gamut,
}

impl ColorDesc {
    const SDR: Self = Self { tf: Tf::Gamma22, gamut: Gamut::Srgb };
    const HDR10: Self = Self { tf: Tf::Pq, gamut: Gamut::Bt2020 };

    /// Обычный цвет поверхности: её можно рисовать как есть.
    pub fn is_plain(&self) -> bool {
        *self == Self::SDR
    }

    pub fn tf_uniform(&self) -> f32 {
        match self.tf {
            Tf::Gamma22 => 0.0,
            Tf::Pq => 1.0,
            Tf::Linear => 2.0,
            Tf::Bt1886 => 3.0,
        }
    }

    /// Матрица из её основных цветов в BT.709, по столбцам.
    pub fn to_709(&self) -> [f32; 9] {
        match self.gamut {
            Gamut::Srgb => [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
            Gamut::Bt2020 => [1.6605, -0.1246, -0.0182, -0.5876, 1.1329, -0.1006, -0.0728, -0.0083, 1.1187],
            Gamut::DisplayP3 => [1.2249, -0.0420, -0.0197, -0.2247, 1.0419, -0.0786, 0.0, 0.0, 1.0979],
        }
    }

    fn identity(&self) -> u32 {
        // одинаковое описание — одинаковый номер; ноль протокол запрещает
        1 + match self.tf {
            Tf::Gamma22 => 0,
            Tf::Pq => 1,
            Tf::Linear => 2,
            Tf::Bt1886 => 3,
        } * 4
            + match self.gamut {
                Gamut::Srgb => 0,
                Gamut::Bt2020 => 1,
                Gamut::DisplayP3 => 2,
            }
    }
}

/// Цвет поверхности: двойная буферизация вместе с её кадром.
#[derive(Debug, Clone, Copy, Default)]
struct SurfaceColor(Option<ColorDesc>);

impl Cacheable for SurfaceColor {
    fn commit(&mut self, _dh: &DisplayHandle) -> Self {
        *self
    }
    fn merge_into(self, into: &mut Self, _dh: &DisplayHandle) {
        *into = self;
    }
}

#[derive(Default)]
pub struct ColorManagement {
    global: Option<GlobalId>,
    outputs: Vec<(WpColorManagementOutputV1, Output)>,
    feedbacks: Vec<WpColorManagementSurfaceFeedbackV1>,
    /// поверхности, которые хоть раз назвали свой цвет
    surfaces: Vec<WlSurface>,
    /// `done` уничтожает объект, а уничтожить его внутри запроса, который его
    /// создал, wayland-backend не даёт (паника) — отвечаем после прохода цикла
    infos: Vec<(WpImageDescriptionInfoV1, ColorDesc, MonitorInfo)>,
}

#[derive(Default)]
pub struct CreatorParams {
    tf: Option<Tf>,
    gamut: Option<Gamut>,
}

/// Данные объекта описания: что в нём и можно ли спросить подробности.
pub struct DescData {
    desc: ColorDesc,
    /// какой монитор описывает; None — описание от самой программы
    monitor: Option<MonitorInfo>,
}

#[derive(Clone, Copy)]
pub struct MonitorInfo {
    white: f32,
}

impl Shell {
    /// После прохода цикла: подробности об описаниях цвета, которые спросили.
    pub fn color_flush(&mut self) {
        for (info, desc, monitor) in self.color.infos.drain(..) {
            send_info(&info, desc, monitor);
        }
    }

    /// Монитор перешёл в HDR или обратно: программам пора спросить цвет заново.
    pub fn color_changed(&mut self, output: &Output) {
        if self.color.global.is_none() && hdr::output_white(output).is_some() {
            self.color.global = Some(self.display_handle.create_global::<Shell, WpColorManagerV1, ()>(1, ()));
            tracing::info!("управление цветом для программ включено");
        }
        self.color.outputs.retain(|(o, _)| o.is_alive());
        for (object, _) in self.color.outputs.iter().filter(|(_, o)| o == output) {
            object.image_description_changed();
        }
        self.color.feedbacks.retain(Resource::is_alive);
        let identity = self.preferred_color().0.identity();
        for feedback in &self.color.feedbacks {
            feedback.preferred_changed(identity);
        }
    }

    /// Какой цвет нужен поверхности: окна свободно переходят между мониторами,
    /// поэтому если хоть один в HDR, просим лучшее, а обычному монитору поможет шейдер.
    fn preferred_color(&self) -> (ColorDesc, Option<f32>) {
        match self.space.outputs().find_map(hdr::output_white) {
            Some(white) => (ColorDesc::HDR10, Some(white)),
            None => (ColorDesc::SDR, None),
        }
    }

    /// Поверхности с необычным цветом. Обычно их нет, и кадр идёт прежним путём.
    pub fn colored_surfaces(&mut self) -> Vec<(WlSurface, ColorDesc)> {
        if self.color.surfaces.is_empty() {
            return Vec::new();
        }
        self.color.surfaces.retain(Resource::is_alive);
        self.color
            .surfaces
            .iter()
            .filter_map(|surface| {
                let desc = with_states(surface, |states| states.cached_state.get::<SurfaceColor>().current().0)?;
                (!desc.is_plain()).then(|| (surface.clone(), desc))
            })
            .collect()
    }
}

fn set_surface_color(surface: &WlSurface, desc: Option<ColorDesc>) {
    if surface.is_alive() {
        with_states(surface, |states| states.cached_state.get::<SurfaceColor>().pending().0 = desc);
    }
}

impl GlobalDispatch<WpColorManagerV1, ()> for Shell {
    fn bind(
        _state: &mut Self,
        _dh: &DisplayHandle,
        _client: &Client,
        resource: New<WpColorManagerV1>,
        _data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        let manager = data_init.init(resource, ());
        manager.supported_intent(RenderIntent::Perceptual);
        for feature in [
            Feature::Parametric,
            Feature::SetLuminances,
            Feature::SetMasteringDisplayPrimaries,
            Feature::ExtendedTargetVolume,
            Feature::WindowsScrgb,
        ] {
            manager.supported_feature(feature);
        }
        for tf in [
            TransferFunction::Gamma22,
            TransferFunction::Srgb,
            TransferFunction::St2084Pq,
            TransferFunction::ExtLinear,
            TransferFunction::Bt1886,
        ] {
            manager.supported_tf_named(tf);
        }
        for primaries in [Primaries::Srgb, Primaries::Bt2020, Primaries::DisplayP3] {
            manager.supported_primaries_named(primaries);
        }
        manager.done();
    }
}

impl Dispatch<WpColorManagerV1, ()> for Shell {
    fn request(
        state: &mut Self,
        _client: &Client,
        manager: &WpColorManagerV1,
        request: wp_color_manager_v1::Request,
        _data: &(),
        _dh: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_color_manager_v1::Request::Destroy => {}
            wp_color_manager_v1::Request::GetOutput { id, output } => {
                let object = data_init.init(id, output.clone());
                if let Some(output) = Output::from_resource(&output) {
                    state.color.outputs.push((object, output));
                }
            }
            wp_color_manager_v1::Request::GetSurface { id, surface } => {
                data_init.init(id, surface);
            }
            wp_color_manager_v1::Request::GetSurfaceFeedback { id, surface } => {
                let object = data_init.init(id, surface);
                state.color.feedbacks.push(object);
            }
            wp_color_manager_v1::Request::CreateIccCreator { obj } => {
                data_init.init(obj, ());
                manager.post_error(wp_color_manager_v1::Error::UnsupportedFeature, "профили ICC не поддерживаются");
            }
            wp_color_manager_v1::Request::CreateParametricCreator { obj } => {
                data_init.init(obj, Mutex::new(CreatorParams::default()));
            }
            wp_color_manager_v1::Request::CreateWindowsScrgb { image_description } => {
                let desc = ColorDesc { tf: Tf::Linear, gamut: Gamut::Srgb };
                let object = data_init.init(image_description, DescData { desc, monitor: None });
                object.ready(desc.identity());
            }
            _ => manager.post_error(wp_color_manager_v1::Error::UnsupportedFeature, "не поддерживается"),
        }
    }
}

impl Dispatch<WpImageDescriptionCreatorIccV1, ()> for Shell {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WpImageDescriptionCreatorIccV1,
        _request: wp_image_description_creator_icc_v1::Request,
        _data: &(),
        _dh: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
    }
}

impl Dispatch<WpImageDescriptionCreatorParamsV1, Mutex<CreatorParams>> for Shell {
    fn request(
        _state: &mut Self,
        _client: &Client,
        creator: &WpImageDescriptionCreatorParamsV1,
        request: wp_image_description_creator_params_v1::Request,
        data: &Mutex<CreatorParams>,
        _dh: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        use wp_image_description_creator_params_v1::{Error, Request};
        let mut params = data.lock().unwrap();
        match request {
            Request::Create { image_description } => match (params.tf, params.gamut) {
                (Some(tf), Some(gamut)) => {
                    let desc = ColorDesc { tf, gamut };
                    let object = data_init.init(image_description, DescData { desc, monitor: None });
                    object.ready(desc.identity());
                }
                _ => {
                    data_init.init(image_description, DescData { desc: ColorDesc::SDR, monitor: None });
                    creator.post_error(Error::IncompleteSet, "нужны и передача, и основные цвета");
                }
            },
            Request::SetTfNamed { tf } => {
                params.tf = match tf.into_result() {
                    Ok(TransferFunction::Gamma22 | TransferFunction::Srgb) => Some(Tf::Gamma22),
                    Ok(TransferFunction::St2084Pq) => Some(Tf::Pq),
                    Ok(TransferFunction::ExtLinear) => Some(Tf::Linear),
                    Ok(TransferFunction::Bt1886) => Some(Tf::Bt1886),
                    _ => {
                        creator.post_error(Error::InvalidTf, "эта передача не поддерживается");
                        None
                    }
                };
            }
            Request::SetPrimariesNamed { primaries } => {
                params.gamut = match primaries.into_result() {
                    Ok(Primaries::Srgb) => Some(Gamut::Srgb),
                    Ok(Primaries::Bt2020) => Some(Gamut::Bt2020),
                    Ok(Primaries::DisplayP3) => Some(Gamut::DisplayP3),
                    _ => {
                        creator.post_error(Error::InvalidPrimariesNamed, "эти основные цвета не поддерживаются");
                        None
                    }
                };
            }
            Request::SetTfPower { .. } | Request::SetPrimaries { .. } => {
                creator.post_error(Error::UnsupportedFeature, "не поддерживается");
            }
            // яркость кадра свет считает сам: PQ абсолютен, а монитор сам свернёт верхи
            _ => {}
        }
    }
}

const BT2020_XY: [i32; 8] = [708_000, 292_000, 170_000, 797_000, 131_000, 46_000, 312_700, 329_000];
const SRGB_XY: [i32; 8] = [640_000, 330_000, 300_000, 600_000, 150_000, 60_000, 312_700, 329_000];
const P3_XY: [i32; 8] = [680_000, 320_000, 265_000, 690_000, 150_000, 60_000, 312_700, 329_000];

fn send_info(info: &WpImageDescriptionInfoV1, desc: ColorDesc, monitor: MonitorInfo) {
    let (xy, named) = match desc.gamut {
        Gamut::Srgb => (SRGB_XY, Primaries::Srgb),
        Gamut::Bt2020 => (BT2020_XY, Primaries::Bt2020),
        Gamut::DisplayP3 => (P3_XY, Primaries::DisplayP3),
    };
    let [rx, ry, gx, gy, bx, by, wx, wy] = xy;
    info.primaries(rx, ry, gx, gy, bx, by, wx, wy);
    info.primaries_named(named);
    info.target_primaries(rx, ry, gx, gy, bx, by, wx, wy);
    let white = monitor.white.round() as u32;
    match desc.tf {
        Tf::Pq => {
            info.tf_named(TransferFunction::St2084Pq);
            info.luminances(50, 10000, white);
            info.target_luminance(50, 10000);
        }
        _ => {
            info.tf_named(TransferFunction::Gamma22);
            info.luminances(2000, 80, 80);
            info.target_luminance(2000, 80);
        }
    }
    info.done();
}

impl Dispatch<WpImageDescriptionV1, DescData> for Shell {
    fn request(
        state: &mut Self,
        _client: &Client,
        object: &WpImageDescriptionV1,
        request: wp_image_description_v1::Request,
        data: &DescData,
        _dh: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_image_description_v1::Request::Destroy => {}
            wp_image_description_v1::Request::GetInformation { information } => {
                let info = data_init.init(information, ());
                match data.monitor {
                    Some(monitor) => state.color.infos.push((info, data.desc, monitor)),
                    None => object.post_error(wp_image_description_v1::Error::NoInformation, "описание от самой программы"),
                }
            }
            _ => {}
        }
    }
}

impl Dispatch<WpImageDescriptionInfoV1, ()> for Shell {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WpImageDescriptionInfoV1,
        _request: smithay::reexports::wayland_protocols::wp::color_management::v1::server::wp_image_description_info_v1::Request,
        _data: &(),
        _dh: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
    }
}

fn describe_monitor(white: Option<f32>) -> DescData {
    DescData {
        desc: if white.is_some() { ColorDesc::HDR10 } else { ColorDesc::SDR },
        monitor: Some(MonitorInfo { white: white.unwrap_or(hdr::SDR_WHITE) }),
    }
}

impl Dispatch<WpColorManagementOutputV1, WlOutput> for Shell {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WpColorManagementOutputV1,
        request: wp_color_management_output_v1::Request,
        output: &WlOutput,
        _dh: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_color_management_output_v1::Request::Destroy => {}
            wp_color_management_output_v1::Request::GetImageDescription { image_description } => {
                let white = Output::from_resource(output).as_ref().and_then(hdr::output_white);
                let data = describe_monitor(white);
                let identity = data.desc.identity();
                data_init.init(image_description, data).ready(identity);
            }
            _ => {}
        }
    }

    fn destroyed(state: &mut Self, _client: ClientId, resource: &WpColorManagementOutputV1, _data: &WlOutput) {
        state.color.outputs.retain(|(o, _)| o != resource);
    }
}

impl Dispatch<WpColorManagementSurfaceV1, WlSurface> for Shell {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &WpColorManagementSurfaceV1,
        request: wp_color_management_surface_v1::Request,
        surface: &WlSurface,
        _dh: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_color_management_surface_v1::Request::SetImageDescription { image_description, .. } => {
                let desc = image_description.data::<DescData>().map(|d| d.desc);
                set_surface_color(surface, desc);
                if !state.color.surfaces.contains(surface) {
                    state.color.surfaces.push(surface.clone());
                }
            }
            wp_color_management_surface_v1::Request::UnsetImageDescription
            | wp_color_management_surface_v1::Request::Destroy => set_surface_color(surface, None),
            _ => {}
        }
    }
}

impl Dispatch<WpColorManagementSurfaceFeedbackV1, WlSurface> for Shell {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &WpColorManagementSurfaceFeedbackV1,
        request: wp_color_management_surface_feedback_v1::Request,
        _surface: &WlSurface,
        _dh: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        use wp_color_management_surface_feedback_v1::Request;
        match request {
            Request::Destroy => {}
            Request::GetPreferred { image_description } | Request::GetPreferredParametric { image_description } => {
                let data = describe_monitor(state.preferred_color().1);
                let identity = data.desc.identity();
                data_init.init(image_description, data).ready(identity);
            }
            _ => {}
        }
    }

    fn destroyed(state: &mut Self, _client: ClientId, resource: &WpColorManagementSurfaceFeedbackV1, _data: &WlSurface) {
        state.color.feedbacks.retain(|f| f != resource);
    }
}
