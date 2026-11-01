//! wlr-layer-shell — слои у краёв экрана: панели, доки, обои, уведомления,
//! виджеты. На нём стоит вся Delta (Quickshell PanelWindow / WlrLayershell).
//!
//! Слои рисует Space сам: фон и нижний — под окнами, верхний и поверх всего
//! — над ними. Здесь — где слой на экране, первая настройка, фокус клавиатуры.

use std::sync::atomic::{AtomicBool, Ordering};

use smithay::{
    delegate_layer_shell,
    desktop::{layer_map_for_output, LayerSurface, PopupKind, WindowSurfaceType},
    output::Output,
    reexports::wayland_server::protocol::{wl_output::WlOutput, wl_surface::WlSurface},
    utils::SERIAL_COUNTER,
    wayland::{
        compositor::{add_pre_commit_hook, with_states},
        shell::{
            wlr_layer::{
                Anchor, KeyboardInteractivity, Layer, LayerSurface as WlrLayerSurface, LayerSurfaceCachedState,
                LayerSurfaceData, WlrLayerShellHandler, WlrLayerShellState,
            },
            xdg::PopupSurface,
        },
    },
};

use crate::Shell;

/// Поверхность, с которой сняли роль слоя.
#[derive(Default)]
struct LayerRemoved(AtomicBool);

fn mark_removed(surface: &WlSurface, removed: bool) {
    with_states(surface, |states| {
        states.data_map.insert_if_missing_threadsafe(LayerRemoved::default);
        states.data_map.get::<LayerRemoved>().unwrap().0.store(removed, Ordering::Relaxed);
    });
}

/// Обход ошибки Smithay 0.7. Слой убирают так: destroy, затем пустой commit
/// (протокол это разрешает, так делает Quickshell). Smithay к этому времени
/// уже сбросил якоря слоя, его проверка видит «ширина 0 без якорей» и отключает
/// программу за ошибку протокола. Вызывается для новой поверхности, поэтому
/// наша проверка идёт раньше той: подставляем якоря, и размер 0 становится верным.
pub fn guard_removed_layer(surface: &WlSurface) {
    add_pre_commit_hook::<Shell, _>(surface, |_, _, surface| {
        with_states(surface, |states| {
            if states.data_map.get::<LayerRemoved>().is_some_and(|r| r.0.load(Ordering::Relaxed)) {
                states.cached_state.get::<LayerSurfaceCachedState>().pending().anchor = Anchor::all();
            }
        });
    });
}

impl WlrLayerShellHandler for Shell {
    fn shell_state(&mut self) -> &mut WlrLayerShellState {
        &mut self.layer_shell_state
    }

    fn new_layer_surface(&mut self, surface: WlrLayerSurface, output: Option<WlOutput>, _layer: Layer, namespace: String) {
        // та же поверхность снова стала слоем: подставленные якоря больше не нужны
        mark_removed(surface.wl_surface(), false);
        with_states(surface.wl_surface(), |states| {
            states.cached_state.get::<LayerSurfaceCachedState>().pending().anchor = Anchor::empty();
        });
        // без монитора — на тот, где мышь (как Hyprland), иначе на первый
        let output = output.as_ref().and_then(Output::from_resource).or_else(|| self.output_under_pointer());
        let Some(output) = output else {
            tracing::warn!(namespace, "слой без монитора — закрываю");
            surface.send_close();
            return;
        };
        let mut map = layer_map_for_output(&output);
        if let Err(e) = map.map_layer(&LayerSurface::new(surface, namespace.clone())) {
            tracing::warn!(namespace, "слой не встал: {e}");
        }
    }

    fn new_popup(&mut self, _parent: WlrLayerSurface, popup: PopupSurface) {
        // меню слоя (Quickshell PopupWindow): то же, что у окон
        self.unconstrain_popup(&popup);
        let _ = self.popups.track_popup(PopupKind::Xdg(popup));
    }

    fn layer_destroyed(&mut self, surface: WlrLayerSurface) {
        mark_removed(surface.wl_surface(), true);
        let had_focus = self
            .seat
            .get_keyboard()
            .and_then(|k| k.current_focus())
            .is_some_and(|f| &f == surface.wl_surface());
        for output in self.space.outputs().cloned().collect::<Vec<_>>() {
            let mut map = layer_map_for_output(&output);
            let found = map.layers().find(|l| l.layer_surface() == &surface).cloned();
            if let Some(layer) = found {
                map.unmap_layer(&layer);
            }
        }
        if had_focus {
            self.focus_top();
        }
    }
}
delegate_layer_shell!(Shell);

/// Кадр поверхности слоя: расставить слои монитора, первая настройка,
/// фокус клавиатуры для слоёв, которые его требуют (меню, блокировка Delta).
pub fn handle_commit(shell: &mut Shell, surface: &WlSurface) {
    let Some(output) = shell
        .space
        .outputs()
        .find(|o| layer_map_for_output(o).layer_for_surface(surface, WindowSurfaceType::TOPLEVEL).is_some())
        .cloned()
    else {
        return;
    };

    let initial_configure_sent = with_states(surface, |states| {
        states.data_map.get::<LayerSurfaceData>().map(|d| d.lock().unwrap().initial_configure_sent).unwrap_or(true)
    });

    let mut map = layer_map_for_output(&output);
    // расставить до первой настройки — с учётом размера, который просит слой
    let zones_changed = map.arrange();
    let layer = map.layer_for_surface(surface, WindowSurfaceType::TOPLEVEL).cloned();
    drop(map);

    let Some(layer) = layer else { return };
    if !initial_configure_sent {
        layer.layer_surface().send_configure();
    }

    // «исключительный» ввод верхних слоёв: клавиатура сразу им
    let state = layer.cached_state();
    if !shell.is_locked() && state.keyboard_interactivity == KeyboardInteractivity::Exclusive && matches!(state.layer, Layer::Top | Layer::Overlay) {
        let keyboard = shell.seat.get_keyboard().unwrap();
        if keyboard.current_focus().as_ref() != Some(layer.wl_surface()) {
            keyboard.set_focus(shell, Some(layer.wl_surface().clone()), SERIAL_COUNTER.next_serial());
        }
    }

    // панель заняла край — развёрнутые окна ужимаются под неё
    if zones_changed {
        shell.zones_changed(&output);
    }
}

impl Shell {
    /// Монитор под мышью, иначе первый.
    pub fn output_under_pointer(&self) -> Option<Output> {
        let pos = self.seat.get_pointer().map(|p| p.current_location()).unwrap_or_default();
        self.space.output_under(pos).next().or_else(|| self.space.outputs().next()).cloned()
    }

    /// Слой под точкой (только указанные уровни, сверху вниз) и точка его
    /// поверхности в координатах стола.
    pub fn layer_surface_under(
        &self,
        pos: smithay::utils::Point<f64, smithay::utils::Logical>,
        layers: &[Layer],
    ) -> Option<(WlSurface, smithay::utils::Point<f64, smithay::utils::Logical>, LayerSurface)> {
        let output = self.space.output_under(pos).next()?;
        let output_geo = self.space.output_geometry(output)?;
        let map = layer_map_for_output(output);
        for &level in layers {
            for layer in map.layers_on(level).rev() {
                let Some(geo) = map.layer_geometry(layer) else { continue };
                let local = pos - output_geo.loc.to_f64() - geo.loc.to_f64();
                if let Some((surface, at)) = layer.surface_under(local, WindowSurfaceType::ALL) {
                    let at = (at + geo.loc + output_geo.loc).to_f64();
                    return Some((surface, at, layer.clone()));
                }
            }
        }
        None
    }
}
