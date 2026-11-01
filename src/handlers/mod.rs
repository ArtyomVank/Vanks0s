//! Протоколы Wayland, которые понимает оболочка: на каждый — обработчик
//! и delegate_*! от Smithay.

mod compositor;
pub mod layer_shell;
pub mod xdg_shell;

use smithay::{
    backend::allocator::dmabuf::Dmabuf,
    delegate_content_type, delegate_cursor_shape, delegate_data_control, delegate_data_device, delegate_dmabuf,
    delegate_fractional_scale, delegate_idle_inhibit, delegate_output, delegate_pointer_constraints,
    delegate_pointer_gestures, delegate_presentation, delegate_primary_selection, delegate_relative_pointer,
    delegate_seat, delegate_single_pixel_buffer, delegate_viewporter, delegate_xdg_activation,
    input::{
        keyboard::LedState,
        pointer::{CursorImageStatus, PointerHandle},
        Seat, SeatHandler, SeatState,
    },
    reexports::wayland_server::{protocol::wl_surface::WlSurface, Resource},
    utils::{Logical, Point, SERIAL_COUNTER},
    wayland::{
        dmabuf::{DmabufGlobal, DmabufHandler, DmabufState, ImportNotifier},
        fractional_scale::FractionalScaleHandler,
        idle_inhibit::IdleInhibitHandler,
        output::OutputHandler,
        pointer_constraints::{with_pointer_constraint, PointerConstraintsHandler},
        tablet_manager::TabletSeatHandler,
        selection::{
            data_device::{set_data_device_focus, ClientDndGrabHandler, DataDeviceHandler, DataDeviceState, ServerDndGrabHandler},
            primary_selection::{set_primary_focus, PrimarySelectionHandler, PrimarySelectionState},
            wlr_data_control::{DataControlHandler, DataControlState},
            SelectionHandler,
        },
        xdg_activation::{XdgActivationHandler, XdgActivationState, XdgActivationToken, XdgActivationTokenData},
    },
};

use crate::Shell;

// --- wl_seat: клавиатура, мышь, касания ---
impl SeatHandler for Shell {
    type KeyboardFocus = WlSurface;
    type PointerFocus = WlSurface;
    type TouchFocus = WlSurface;

    fn seat_state(&mut self) -> &mut SeatState<Shell> {
        &mut self.seat_state
    }

    // программа под мышью просит курсор: фигуру по имени, свою картинку
    // или спрятать. В настоящей сессии рисуем сами, в окне отладки — сессия вокруг
    fn cursor_image(&mut self, _seat: &Seat<Self>, image: CursorImageStatus) {
        self.cursor_status = image;
    }

    fn led_state_changed(&mut self, _seat: &Seat<Self>, leds: LedState) {
        self.update_leds(leds);
    }

    // буфер обмена — у программы с фокусом клавиатуры; Delta — какое окно активно
    fn focus_changed(&mut self, seat: &Seat<Self>, focused: Option<&WlSurface>) {
        let dh = &self.display_handle;
        let client = focused.and_then(|s| dh.get_client(s.id()).ok());
        set_data_device_focus(dh, seat, client.clone());
        set_primary_focus(dh, seat, client);

        // фокус ушёл на панель Delta — активное окно для неё не меняется
        let window = focused.and_then(|s| self.window_for_surface(s));
        if focused.is_some() && window.is_none() {
            return;
        }
        let (addr, class, title) = match &window {
            Some(w) => {
                let (c, t) = crate::workspaces::class_title(w);
                (format!("{:x}", crate::workspaces::data(w).address), c, t)
            }
            None => (String::new(), String::new(), String::new()),
        };
        self.ipc_event("activewindow", &format!("{class},{title}"));
        self.ipc_event("activewindowv2", &addr);
    }
}
delegate_seat!(Shell);

// --- cursor-shape-v1: курсор по имени («text», «pointer»), без своих картинок ---
impl TabletSeatHandler for Shell {}
delegate_cursor_shape!(Shell);

// --- буфер обмена и перетаскивание между программами ---
impl SelectionHandler for Shell {
    type SelectionUserData = ();
}
impl DataDeviceHandler for Shell {
    fn data_device_state(&self) -> &DataDeviceState {
        &self.data_device_state
    }
}
impl ClientDndGrabHandler for Shell {}
impl ServerDndGrabHandler for Shell {}
delegate_data_device!(Shell);

// --- выходы (мониторы) и xdg-output ---
impl OutputHandler for Shell {}
delegate_output!(Shell);

// --- linux-dmabuf: кадры программ прямо из видеопамяти (только настоящая сессия) ---
impl DmabufHandler for Shell {
    fn dmabuf_state(&mut self) -> &mut DmabufState {
        &mut self.dmabuf_state
    }

    fn dmabuf_imported(&mut self, _global: &DmabufGlobal, dmabuf: Dmabuf, notifier: ImportNotifier) {
        if self.import_dmabuf(&dmabuf) {
            let _ = notifier.successful::<Shell>();
        } else {
            notifier.failed();
        }
    }
}
delegate_dmabuf!(Shell);

// --- мелкие протоколы, которые просто объявляем: масштаб, обрезка кадра и т. п. ---
delegate_viewporter!(Shell);
delegate_single_pixel_buffer!(Shell);
delegate_content_type!(Shell);
delegate_fractional_scale!(Shell);
delegate_presentation!(Shell);
delegate_relative_pointer!(Shell);
delegate_pointer_gestures!(Shell);

impl FractionalScaleHandler for Shell {
    fn new_fractional_scale(&mut self, _surface: WlSurface) {}
}

// --- второй буфер обмена: выделил — вставил средней кнопкой ---
impl PrimarySelectionHandler for Shell {
    fn primary_selection_state(&self) -> &PrimarySelectionState {
        &self.primary_selection_state
    }
}
delegate_primary_selection!(Shell);

// --- буфер обмена для менеджеров вроде cliphist и wl-copy без окна ---
impl DataControlHandler for Shell {
    fn data_control_state(&self) -> &DataControlState {
        &self.data_control_state
    }
}
delegate_data_control!(Shell);

// --- xdg-activation: программа просит показать своё окно (ссылка из мессенджера).
// Просьба без действия пользователя окно не поднимает, как и в Hyprland focus_on_activate ---
impl XdgActivationHandler for Shell {
    fn activation_state(&mut self) -> &mut XdgActivationState {
        &mut self.xdg_activation_state
    }

    fn request_activation(&mut self, _token: XdgActivationToken, token_data: XdgActivationTokenData, surface: WlSurface) {
        // токен старше 10 секунд — не считается просьбой пользователя
        if token_data.timestamp.elapsed().as_secs() >= 10 {
            return;
        }
        if let Some(window) = self.window_for_surface(&surface) {
            self.activate_window(&window, SERIAL_COUNTER.next_serial());
        }
    }
}
delegate_xdg_activation!(Shell);

// --- захват мыши: игры прячут курсор и получают только относительные сдвиги ---
impl PointerConstraintsHandler for Shell {
    fn new_constraint(&mut self, surface: &WlSurface, pointer: &PointerHandle<Self>) {
        // мышь уже над этой поверхностью — захват сразу; иначе при наведении
        if pointer.current_focus().as_ref() == Some(surface) {
            with_pointer_constraint(surface, pointer, |c| {
                if let Some(c) = c {
                    c.activate();
                }
            });
        }
    }

    fn cursor_position_hint(&mut self, surface: &WlSurface, pointer: &PointerHandle<Self>, location: Point<f64, Logical>) {
        // программа говорит, где оставить курсор, когда отпустит мышь
        let locked = with_pointer_constraint(surface, pointer, |c| c.is_some_and(|c| c.is_active()));
        if !locked {
            return;
        }
        if let Some((_, origin)) = self.surface_under(pointer.current_location()) {
            pointer.set_location(origin + location);
        }
    }
}
delegate_pointer_constraints!(Shell);

// --- запрет простоя: видео и игры просят не гасить экран (protocols/idle_notify.rs) ---
impl IdleInhibitHandler for Shell {
    fn inhibit(&mut self, surface: WlSurface) {
        self.idle_inhibitors.push(surface);
        self.idle_notify.set_inhibited(true);
    }

    fn uninhibit(&mut self, surface: WlSurface) {
        self.idle_inhibitors.retain(|s| *s != surface);
        self.idle_notify.set_inhibited(!self.idle_inhibitors.is_empty());
    }
}
delegate_idle_inhibit!(Shell);
