//! Протоколы Wayland, которые понимает оболочка: на каждый — обработчик
//! и delegate_*! от Smithay.

mod compositor;
pub mod layer_shell;
pub mod xdg_shell;

use smithay::{
    backend::allocator::dmabuf::Dmabuf,
    delegate_cursor_shape, delegate_data_device, delegate_dmabuf, delegate_idle_inhibit, delegate_output,
    delegate_seat,
    input::{keyboard::LedState, pointer::CursorImageStatus, Seat, SeatHandler, SeatState},
    reexports::wayland_server::{protocol::wl_surface::WlSurface, Resource},
    wayland::{
        dmabuf::{DmabufGlobal, DmabufHandler, DmabufState, ImportNotifier},
        idle_inhibit::IdleInhibitHandler,
        output::OutputHandler,
        tablet_manager::TabletSeatHandler,
        selection::{
            data_device::{set_data_device_focus, ClientDndGrabHandler, DataDeviceHandler, DataDeviceState, ServerDndGrabHandler},
            SelectionHandler,
        },
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
        set_data_device_focus(dh, seat, client);

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
